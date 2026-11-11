import Foundation

/// The Movie Database. With your own free API key (added in Account) it fills in missing posters and descriptions.
/// Signing in also lets you rate titles from the detail screen.
@MainActor
final class TMDBAuth: ObservableObject {
    @Published private(set) var sessionID: String?
    @Published private(set) var busy = false
    @Published var error: String?

    private let keychainKey = "tmdb.session"
    private let base = "https://api.themoviedb.org/3"
    private let imageBase = "https://image.tmdb.org/t/p"
    private var found: [String: (id: Int, isTV: Bool, poster: String?, backdrop: String?, overview: String?)] = [:]

    @Published private(set) var hasKey = UserKey.tmdb.isSet
    var isSignedIn: Bool { sessionID != nil }
    var isConfigured: Bool { hasKey }

    func saveKey(_ key: String) { UserKey.tmdb.save(key); hasKey = UserKey.tmdb.isSet }
    func removeKey() { UserKey.tmdb.remove(); hasKey = false; signOut() }

    init() {
        sessionID = Keychain.load(key: keychainKey).flatMap { String(data: $0, encoding: .utf8) }
    }

    private func url(_ path: String, _ extra: [String: String] = [:]) -> URL? {
        var q = extra
        q["api_key"] = UserKey.tmdb.value
        return HTTP.url(base + path, query: q)
    }

    func signIn() async {
        error = nil
        guard isConfigured else { error = "Add your TMDB API key first."; return }
        busy = true
        defer { busy = false }
        do {
            guard let tokenURL = url("/authentication/token/new"),
                  case let (status, data) = try await HTTP.send(tokenURL), status == 200,
                  let token = HTTP.object(data)?["request_token"] as? String else {
                error = "TMDB didn't respond."
                return
            }
            let approve = HTTP.url("https://www.themoviedb.org/authenticate/\(token)",
                                   query: ["redirect_to": "\(Config.callbackScheme)://tmdb"])!
            _ = try await WebAuth.start(url: approve, callbackScheme: Config.callbackScheme)

            guard let sessionURL = url("/authentication/session/new") else { return }
            let (s2, d2) = try await HTTP.send(sessionURL, method: "POST",
                                               headers: ["Content-Type": "application/json"],
                                               body: HTTP.json(["request_token": token]))
            guard s2 == 200, let id = HTTP.object(d2)?["session_id"] as? String else {
                error = "TMDB sign-in wasn't approved."
                return
            }
            sessionID = id
            Keychain.save(Data(id.utf8), key: keychainKey)
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    func signOut() {
        sessionID = nil
        Keychain.delete(key: keychainKey)
    }

    private func lookup(_ imdb: String) async -> (id: Int, isTV: Bool, poster: String?, backdrop: String?, overview: String?)? {
        if let hit = found[imdb] { return hit }
        guard isConfigured, let u = url("/find/\(imdb)", ["external_source": "imdb_id"]),
              let (status, data) = try? await HTTP.send(u), status == 200, let obj = HTTP.object(data) else { return nil }
        let movie = (obj["movie_results"] as? [[String: Any]])?.first
        let tv = (obj["tv_results"] as? [[String: Any]])?.first
        guard let hit = movie ?? tv, let id = hit["id"] as? Int else { return nil }
        let result = (id: id, isTV: movie == nil,
                      poster: hit["poster_path"] as? String,
                      backdrop: hit["backdrop_path"] as? String,
                      overview: hit["overview"] as? String)
        found[imdb] = result
        return result
    }

    /// Fills in only what the addon left blank: poster, background and description.
    func enrich(_ item: MetaItem) async -> MetaItem {
        guard item.id.hasPrefix("tt"), item.poster == nil || item.background == nil || (item.description ?? "").isEmpty,
              let t = await lookup(item.id) else { return item }
        return MetaItem(
            id: item.id, type: item.type, name: item.name,
            poster: item.poster ?? t.poster.map { "\(imageBase)/w500\($0)" },
            background: item.background ?? t.backdrop.map { "\(imageBase)/w780\($0)" },
            description: (item.description ?? "").isEmpty ? t.overview : item.description,
            releaseInfo: item.releaseInfo, runtime: item.runtime,
            genres: item.genres, videos: item.videos)
    }

    /// The YouTube key of this title's official trailer, if TMDB has one.
    func trailerKey(for item: MetaItem) async -> String? {
        guard item.id.hasPrefix("tt"), let t = await lookup(String(item.id.prefix(while: { $0 != ":" }))),
              let u = url("/\(t.isTV ? "tv" : "movie")/\(t.id)/videos"),
              let (status, data) = try? await HTTP.send(u), status == 200,
              let obj = HTTP.object(data), let list = obj["results"] as? [[String: Any]] else { return nil }
        let youtube = list.filter { ($0["site"] as? String) == "YouTube" && $0["key"] is String }
        let trailers = youtube.filter { ($0["type"] as? String) == "Trailer" }
        let official = trailers.first(where: { ($0["official"] as? Bool) == true })
        let teaser = youtube.first(where: { ($0["type"] as? String) == "Teaser" })
        let pick = official ?? trailers.first ?? teaser
        return pick?["key"] as? String
    }

    /// Rates a movie or show from 1 to 10.
    func rate(_ item: MetaItem, value: Int) async -> Bool {
        guard let sessionID, item.id.hasPrefix("tt"), let t = await lookup(item.id),
              let u = url("/\(t.isTV ? "tv" : "movie")/\(t.id)/rating", ["session_id": sessionID]),
              let (status, _) = try? await HTTP.send(u, method: "POST",
                                                     headers: ["Content-Type": "application/json;charset=utf-8"],
                                                     body: HTTP.json(["value": Double(min(max(value, 1), 10))])) else { return false }
        return status == 200 || status == 201
    }

    // MARK: Discover (streaming services and genres)

    private var imdbCache: [String: String] = [:]
    private var providerLogoCache: [Int: URL]?

    /// Logo images for streaming services, straight from TMDB (watch-provider ID -> logo URL).
    func providerLogos() async -> [Int: URL] {
        if let hit = providerLogoCache { return hit }
        guard isConfigured else { return [:] }
        let region = Locale.current.region?.identifier ?? "US"
        var out: [Int: URL] = [:]
        for kind in ["movie", "tv"] {
            guard let u = url("/watch/providers/\(kind)", ["watch_region": region]),
                  let (status, data) = try? await HTTP.send(u), status == 200,
                  let results = HTTP.object(data)?["results"] as? [[String: Any]] else { continue }
            for r in results {
                guard let id = r["provider_id"] as? Int, out[id] == nil,
                      let path = r["logo_path"] as? String,
                      let logo = URL(string: "\(imageBase)/w154\(path)") else { continue }
                out[id] = logo
            }
        }
        if !out.isEmpty { providerLogoCache = out }
        return out
    }

    /// Popular titles available on one streaming service, or in one genre.
    /// `provider` is a TMDB watch-provider ID; `genreID` a TMDB genre ID. At least one should be set.
    func discover(isTV: Bool, provider: Int? = nil, genreID: Int? = nil, page: Int = 1) async -> [MetaItem] {
        guard isConfigured else { return [] }
        let kind = isTV ? "tv" : "movie"
        var q = ["sort_by": "popularity.desc", "page": String(page), "include_adult": "false"]
        if let provider {
            q["with_watch_providers"] = String(provider)
            q["watch_region"] = Locale.current.region?.identifier ?? "US"
            q["with_watch_monetization_types"] = "flatrate|free|ads"
        }
        if let genreID { q["with_genres"] = String(genreID) }
        guard let u = url("/discover/\(kind)", q),
              let (status, data) = try? await HTTP.send(u), status == 200,
              let results = HTTP.object(data)?["results"] as? [[String: Any]] else { return [] }

        // Addons key titles by IMDb ID, so look each one up (in parallel, cached).
        let ids = results.compactMap { $0["id"] as? Int }
        var imdb: [Int: String] = [:]
        await withTaskGroup(of: (Int, String?).self) { group in
            for id in ids {
                group.addTask { (id, await self.imdbID(kind: kind, tmdbID: id)) }
            }
            for await (id, tt) in group { if let tt { imdb[id] = tt } }
        }

        return results.compactMap { r in
            guard let id = r["id"] as? Int, let tt = imdb[id] else { return nil }
            let name = (r["title"] as? String) ?? (r["name"] as? String) ?? ""
            let date = (r["release_date"] as? String) ?? (r["first_air_date"] as? String) ?? ""
            return MetaItem(
                id: tt, type: isTV ? "series" : "movie", name: name,
                poster: (r["poster_path"] as? String).map { "\(imageBase)/w500\($0)" },
                background: (r["backdrop_path"] as? String).map { "\(imageBase)/w780\($0)" },
                description: r["overview"] as? String,
                releaseInfo: date.isEmpty ? nil : String(date.prefix(4)),
                runtime: nil, genres: nil, videos: nil)
        }
    }

    private func imdbID(kind: String, tmdbID: Int) async -> String? {
        let key = "\(kind)/\(tmdbID)"
        if let hit = imdbCache[key] { return hit }
        guard let u = url("/\(kind)/\(tmdbID)/external_ids"),
              let (status, data) = try? await HTTP.send(u), status == 200,
              let tt = HTTP.object(data)?["imdb_id"] as? String, !tt.isEmpty else { return nil }
        imdbCache[key] = tt
        return tt
    }
}
