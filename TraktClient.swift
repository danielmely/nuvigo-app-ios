import Foundation

// MARK: - Config
// Create an app at https://trakt.tv/oauth/applications (redirect URI: urn:ietf:wg:oauth:2.0:oob)
// and paste its Client ID / Secret here. Device-code login needs both.
enum TraktConfig {
    static let clientID = "YOUR_TRAKT_CLIENT_ID"
    static let clientSecret = "YOUR_TRAKT_CLIENT_SECRET"
    static var isConfigured: Bool { !clientID.hasPrefix("YOUR_") && !clientSecret.hasPrefix("YOUR_") }
    static let base = URL(string: "https://api.trakt.tv")!
}

// MARK: - Models

struct TraktToken: Codable {
    let access_token: String
    let refresh_token: String
    let expires_in: Int
    let created_at: Int

    var expiryDate: Date { Date(timeIntervalSince1970: TimeInterval(created_at + expires_in)) }
    /// Refresh when less than a day is left.
    var needsRefresh: Bool { expiryDate.timeIntervalSinceNow < 86_400 }
}

struct TraktDeviceCode: Decodable {
    let device_code: String
    let user_code: String
    let verification_url: String
    let expires_in: Int
    let interval: Int
}

struct TraktListEntry: Hashable {
    let type: String   // "movie" or "series" (addon terms)
    let id: String     // IMDb id
}

/// What is being watched, in addon terms: type ("movie"/"series") and the stream id
/// (movie: "tt1234567", episode: "tt1234567:1:2").
struct ScrobbleTarget {
    let type: String
    let id: String
}

struct TraktUpcoming: Identifiable {
    let imdb: String
    let showTitle: String
    let season: Int
    let episode: Int
    let episodeTitle: String?
    let airs: Date

    var id: String { "\(imdb):\(season):\(episode)" }
    var label: String { "S\(season)E\(episode)" + (episodeTitle.map { " · \($0)" } ?? "") }
}

// MARK: - Auth + API

@MainActor
final class TraktAuth: ObservableObject {
    @Published private(set) var token: TraktToken?
    @Published private(set) var deviceCode: TraktDeviceCode?
    @Published var error: String?
    /// Watched keys from Trakt: "tt1234567" for movies, "tt1234567:1:2" for episodes.
    @Published private(set) var watchedKeys: Set<String> = []
    @Published private(set) var watchlist: [TraktListEntry] = []

    private let keychainKey = "trakt.token"
    var isSignedIn: Bool { token != nil }

    init() {
        if let data = Keychain.load(key: keychainKey) {
            token = try? JSONDecoder().decode(TraktToken.self, from: data)
        }
        if token != nil { Task { await refreshWatched(); await refreshWatchlist() } }
    }

    func isWatched(_ id: String) -> Bool { watchedKeys.contains(id) }
    func isInWatchlist(_ id: String) -> Bool { watchlist.contains { $0.id == id } }

    // MARK: Watched history

    private struct Ids: Decodable { let imdb: String? }
    private struct WatchedMovie: Decodable { struct M: Decodable { let ids: Ids }; let movie: M }
    private struct WatchedShow: Decodable {
        struct S: Decodable { let ids: Ids }
        struct Season: Decodable { struct Ep: Decodable { let number: Int }; let number: Int; let episodes: [Ep] }
        let show: S
        let seasons: [Season]?
    }

    /// Pulls watched movies and episodes from Trakt. Call after sign-in and after finishing playback.
    func refreshWatched() async {
        guard let bearer = await validAccessToken() else { watchedKeys = []; return }
        var keys = Set<String>()
        if let (st, data) = try? await send("/sync/watched/movies", method: "GET", bearer: bearer), st == 200,
           let list = try? JSONDecoder().decode([WatchedMovie].self, from: data) {
            for m in list { if let id = m.movie.ids.imdb { keys.insert(id) } }
        }
        if let (st, data) = try? await send("/sync/watched/shows", method: "GET", bearer: bearer), st == 200,
           let list = try? JSONDecoder().decode([WatchedShow].self, from: data) {
            for s in list {
                guard let id = s.show.ids.imdb else { continue }
                for season in s.seasons ?? [] {
                    for ep in season.episodes { keys.insert("\(id):\(season.number):\(ep.number)") }
                }
            }
        }
        watchedKeys = keys
    }

    // MARK: Device-code login

    /// Shows `deviceCode` for the user to enter at trakt.tv/activate, then polls until approved.
    /// Cancel the surrounding Task to abort.
    func signIn() async {
        error = nil
        guard TraktConfig.isConfigured else {
            error = "Add your Trakt Client ID and Secret in TraktClient.swift first."
            return
        }
        do {
            let (status, data) = try await send("/oauth/device/code", body: ["client_id": TraktConfig.clientID])
            guard status == 200 else { error = "Trakt returned \(status)."; return }
            let code = try JSONDecoder().decode(TraktDeviceCode.self, from: data)
            deviceCode = code

            let deadline = Date().addingTimeInterval(TimeInterval(code.expires_in))
            var interval = max(code.interval, 1)
            while Date() < deadline {
                try await Task.sleep(for: .seconds(interval))
                let (st, body) = try await send("/oauth/device/token", body: [
                    "code": code.device_code,
                    "client_id": TraktConfig.clientID,
                    "client_secret": TraktConfig.clientSecret,
                ])
                switch st {
                case 200:
                    store(try JSONDecoder().decode(TraktToken.self, from: body))
                    deviceCode = nil
                    await refreshWatched()
                    await refreshWatchlist()
                    return
                case 400: continue                 // waiting for the user
                case 429: interval += 1            // slow down
                case 418: error = "Sign-in was denied."; deviceCode = nil; return
                case 410: error = "The code expired. Try again."; deviceCode = nil; return
                default:  error = "Sign-in failed (\(st))."; deviceCode = nil; return
                }
            }
            error = "The code expired. Try again."
            deviceCode = nil
        } catch is CancellationError {
            deviceCode = nil
        } catch {
            self.error = error.localizedDescription
            deviceCode = nil
        }
    }

    func signOut() {
        token = nil
        deviceCode = nil
        watchedKeys = []
        watchlist = []
        Keychain.delete(key: keychainKey)
    }

    private func store(_ t: TraktToken) {
        token = t
        if let data = try? JSONEncoder().encode(t) { Keychain.save(data, key: keychainKey) }
    }

    /// Returns a usable access token, refreshing it first if it's about to expire.
    private func validAccessToken() async -> String? {
        guard let t = token else { return nil }
        guard t.needsRefresh else { return t.access_token }
        do {
            let (st, data) = try await send("/oauth/token", body: [
                "refresh_token": t.refresh_token,
                "client_id": TraktConfig.clientID,
                "client_secret": TraktConfig.clientSecret,
                "redirect_uri": "urn:ietf:wg:oauth:2.0:oob",
                "grant_type": "refresh_token",
            ])
            if st == 200 {
                let fresh = try JSONDecoder().decode(TraktToken.self, from: data)
                store(fresh)
                return fresh.access_token
            }
            if st == 401 || st == 400 { signOut() }   // refresh token revoked/expired
        } catch {}
        return t.access_token
    }

    // MARK: Watchlist

    func refreshWatchlist() async {
        guard let bearer = await validAccessToken() else { watchlist = []; return }
        var list: [TraktListEntry] = []
        if let (st, data) = try? await send("/sync/watchlist/movies", method: "GET", bearer: bearer), st == 200,
           let movies = try? JSONDecoder().decode([WatchedMovie].self, from: data) {
            list += movies.compactMap { $0.movie.ids.imdb }.map { TraktListEntry(type: "movie", id: $0) }
        }
        if let (st, data) = try? await send("/sync/watchlist/shows", method: "GET", bearer: bearer), st == 200,
           let shows = try? JSONDecoder().decode([WatchedShow].self, from: data) {
            list += shows.compactMap { $0.show.ids.imdb }.map { TraktListEntry(type: "series", id: $0) }
        }
        watchlist = list
    }

    /// Adds or removes a title (IMDb-style ids only).
    func toggleWatchlist(type: String, id: String) async {
        guard id.hasPrefix("tt"), let bearer = await validAccessToken() else { return }
        let key = type == "movie" ? "movies" : "shows"
        let path = isInWatchlist(id) ? "/sync/watchlist/remove" : "/sync/watchlist"
        _ = try? await send(path, body: [key: [["ids": ["imdb": id]]]], bearer: bearer)
        await refreshWatchlist()
    }

    /// Marks a title watched or unwatched in your Trakt history (a show applies to every episode).
    func setWatched(_ watched: Bool, type: String, id: String) async {
        guard id.hasPrefix("tt"), let bearer = await validAccessToken() else { return }
        let key = type == "movie" ? "movies" : "shows"
        _ = try? await send(watched ? "/sync/history" : "/sync/history/remove",
                            body: [key: [["ids": ["imdb": id]]]], bearer: bearer)
        await refreshWatched()
    }

    // MARK: Calendar

    /// Episodes of shows you follow that air in the next `days` days.
    func upcoming(days: Int = 14) async -> [TraktUpcoming] {
        guard let bearer = await validAccessToken() else { return [] }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        let start = f.string(from: Date().addingTimeInterval(-86_400))
        guard let (st, data) = try? await send("/calendars/my/shows/\(start)/\(days + 1)", method: "GET", bearer: bearer),
              st == 200, let list = HTTP.array(data) else { return [] }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        let cutoff = Date().addingTimeInterval(-43_200)
        return list.compactMap { d -> TraktUpcoming? in
            guard let ep = d["episode"] as? [String: Any], let show = d["show"] as? [String: Any],
                  let ids = show["ids"] as? [String: Any], let imdb = ids["imdb"] as? String,
                  let title = show["title"] as? String, let s = ep["season"] as? Int, let n = ep["number"] as? Int,
                  let aired = d["first_aired"] as? String,
                  let date = withFraction.date(from: aired) ?? plain.date(from: aired), date > cutoff else { return nil }
            return TraktUpcoming(imdb: imdb, showTitle: title, season: s, episode: n,
                                 episodeTitle: ep["title"] as? String, airs: date)
        }.sorted { $0.airs < $1.airs }
    }

    // MARK: Scrobbling

    /// action: "start", "pause" or "stop". Trakt marks an item watched when you stop at ≥80%.
    func scrobble(_ action: String, target: ScrobbleTarget, progress: Double) async {
        guard let bearer = await validAccessToken(), let body = scrobbleBody(target, progress: progress) else { return }
        _ = try? await send("/scrobble/\(action)", body: body, bearer: bearer)
        if action == "stop" { await refreshWatched() }
    }

    private func scrobbleBody(_ t: ScrobbleTarget, progress: Double) -> [String: Any]? {
        let parts = t.id.split(separator: ":").map(String.init)
        guard let imdb = parts.first, imdb.hasPrefix("tt") else { return nil }   // only IMDb-style ids
        let p = min(max(progress, 0), 100)
        if t.type == "movie" {
            return ["movie": ["ids": ["imdb": imdb]], "progress": p]
        }
        if t.type == "series", parts.count == 3, let s = Int(parts[1]), let e = Int(parts[2]) {
            return ["show": ["ids": ["imdb": imdb]], "episode": ["season": s, "number": e], "progress": p]
        }
        return nil
    }

    // MARK: HTTP

    private func send(_ path: String, method: String = "POST", body: [String: Any]? = nil, bearer: String? = nil) async throws -> (Int, Data) {
        var req = URLRequest(url: TraktConfig.base.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("2", forHTTPHeaderField: "trakt-api-version")
        req.setValue(TraktConfig.clientID, forHTTPHeaderField: "trakt-api-key")
        if let bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        return ((resp as? HTTPURLResponse)?.statusCode ?? 0, data)
    }
}
