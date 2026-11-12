import Foundation
import Combine

/// Anime trackers don't use IMDb ids, so NuviGo looks the show up by title and updates your list.
/// Only titles that look like anime are sent: an "Anime" genre, or an addon id from Kitsu, MAL, AniList or AniDB.
enum AnimeCheck {
    static func isAnime(_ item: MetaItem) -> Bool {
        if item.genres?.contains(where: { $0.lowercased() == "anime" }) == true { return true }
        return ["kitsu:", "mal:", "anilist:", "anidb:"].contains { item.id.hasPrefix($0) }
    }

    /// The episode number for series, nil for movies.
    static func episodeNumber(_ ctx: PlaybackContext) -> Int? {
        let parts = ctx.key.split(separator: ":")
        guard ctx.item.type == "series", parts.count >= 2, let last = parts.last else { return nil }
        return Int(last)
    }
}

// MARK: - AniList

@MainActor
final class AniListAuth: ObservableObject {
    @Published private(set) var token: String?
    @Published private(set) var busy = false
    @Published var error: String?

    private let keychainKey = "anilist.token"
    private var mediaCache: [String: (id: Int, episodes: Int?)] = [:]
    var isSignedIn: Bool { token != nil }
    var isConfigured: Bool { Config.isSet(Config.anilistClientID) }

    init() {
        token = Keychain.load(key: keychainKey).flatMap { String(data: $0, encoding: .utf8) }
    }

    func signIn() async {
        error = nil
        guard isConfigured else { error = "Add your AniList Client ID in Config.swift first."; return }
        busy = true
        defer { busy = false }
        do {
            var c = URLComponents(string: "https://anilist.co/api/v2/oauth/authorize")!
            c.queryItems = [URLQueryItem(name: "client_id", value: Config.anilistClientID),
                            URLQueryItem(name: "response_type", value: "token")]
            let callback = try await WebAuth.start(url: c.url!, callbackScheme: Config.callbackScheme)
            // The token comes back in the URL fragment: nuvigo://anilist#access_token=…
            let pairs = Dictionary((callback.fragment ?? "").split(separator: "&").compactMap { part -> (String, String)? in
                let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
                return kv.count == 2 ? (kv[0], kv[1]) : nil
            }, uniquingKeysWith: { a, _ in a })
            guard let t = pairs["access_token"] else { error = "AniList didn't return a token."; return }
            token = t
            Keychain.save(Data(t.utf8), key: keychainKey)
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    func signOut() {
        token = nil
        Keychain.delete(key: keychainKey)
    }

    func update(_ ctx: PlaybackContext) async {
        guard let token, AnimeCheck.isAnime(ctx.item), let media = await lookup(ctx.item.name) else { return }
        let episode = AnimeCheck.episodeNumber(ctx)
        let finishedSeries = episode != nil && media.episodes != nil && episode! >= media.episodes!
        var vars: [String: Any] = ["id": media.id, "s": (episode == nil || finishedSeries) ? "COMPLETED" : "CURRENT"]
        if let episode { vars["p"] = episode }
        _ = await graphQL("mutation($id:Int,$p:Int,$s:MediaListStatus){SaveMediaListEntry(mediaId:$id,progress:$p,status:$s){id}}",
                          vars, token: token)
    }

    private func lookup(_ title: String) async -> (id: Int, episodes: Int?)? {
        if let hit = mediaCache[title] { return hit }
        guard let data = await graphQL("query($s:String){Media(search:$s,type:ANIME){id episodes}}", ["s": title], token: nil),
              let root = HTTP.object(data)?["data"] as? [String: Any],
              let media = root["Media"] as? [String: Any],
              let id = media["id"] as? Int else { return nil }
        let hit = (id: id, episodes: media["episodes"] as? Int)
        mediaCache[title] = hit
        return hit
    }

    private func graphQL(_ query: String, _ variables: [String: Any], token: String?) async -> Data? {
        guard let url = URL(string: "https://graphql.anilist.co") else { return nil }
        var headers = ["Content-Type": "application/json", "Accept": "application/json"]
        if let token { headers["Authorization"] = "Bearer \(token)" }
        let body = HTTP.json(["query": query, "variables": variables])
        guard let (status, data) = try? await HTTP.send(url, method: "POST", headers: headers, body: body), status == 200 else { return nil }
        return data
    }
}

// MARK: - MyAnimeList

@MainActor
final class MALAuth: ObservableObject {
    struct Tokens: Codable {
        var access: String
        var refresh: String
        var expires: Date
    }

    @Published private(set) var tokens: Tokens?
    @Published private(set) var busy = false
    @Published var error: String?

    private let keychainKey = "mal.tokens"
    private let redirect = "\(Config.callbackScheme)://mal"
    private var mediaCache: [String: (id: Int, episodes: Int?)] = [:]
    var isSignedIn: Bool { tokens != nil }
    var isConfigured: Bool { Config.isSet(Config.malClientID) }

    init() {
        if let data = Keychain.load(key: keychainKey) {
            tokens = try? JSONDecoder().decode(Tokens.self, from: data)
        }
    }

    /// OAuth with PKCE (MyAnimeList only supports the "plain" challenge method).
    func signIn() async {
        error = nil
        guard isConfigured else { error = "Add your MyAnimeList Client ID in Config.swift first."; return }
        busy = true
        defer { busy = false }
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        let verifier = String((0..<64).map { _ in alphabet.randomElement()! })
        do {
            var c = URLComponents(string: "https://myanimelist.net/v1/oauth2/authorize")!
            c.queryItems = [URLQueryItem(name: "response_type", value: "code"),
                            URLQueryItem(name: "client_id", value: Config.malClientID),
                            URLQueryItem(name: "code_challenge", value: verifier),
                            URLQueryItem(name: "code_challenge_method", value: "plain"),
                            URLQueryItem(name: "redirect_uri", value: redirect)]
            let callback = try await WebAuth.start(url: c.url!, callbackScheme: Config.callbackScheme)
            guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value else {
                error = "MyAnimeList didn't return a code."
                return
            }
            try await exchange(["client_id": Config.malClientID, "grant_type": "authorization_code",
                                "code": code, "redirect_uri": redirect, "code_verifier": verifier])
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    func signOut() {
        tokens = nil
        Keychain.delete(key: keychainKey)
    }

    private func exchange(_ form: [String: String]) async throws {
        guard let url = URL(string: "https://myanimelist.net/v1/oauth2/token") else { return }
        let (status, data) = try await HTTP.send(url, method: "POST",
                                                 headers: ["Content-Type": "application/x-www-form-urlencoded"],
                                                 body: HTTP.form(form))
        guard status == 200, let obj = HTTP.object(data),
              let access = obj["access_token"] as? String,
              let refresh = obj["refresh_token"] as? String else {
            if status == 400 || status == 401 { signOut() }
            error = "MyAnimeList sign-in failed (\(status))."
            return
        }
        let expires = Date().addingTimeInterval(TimeInterval((obj["expires_in"] as? Int) ?? 2_592_000))
        let t = Tokens(access: access, refresh: refresh, expires: expires)
        tokens = t
        if let enc = try? JSONEncoder().encode(t) { Keychain.save(enc, key: keychainKey) }
    }

    private func accessToken() async -> String? {
        guard let t = tokens else { return nil }
        if t.expires.timeIntervalSinceNow > 86_400 { return t.access }
        try? await exchange(["client_id": Config.malClientID, "grant_type": "refresh_token", "refresh_token": t.refresh])
        return tokens?.access
    }

    func update(_ ctx: PlaybackContext) async {
        guard AnimeCheck.isAnime(ctx.item), let token = await accessToken(),
              let media = await lookup(ctx.item.name, token: token) else { return }
        let episode = AnimeCheck.episodeNumber(ctx)
        let finished = episode == nil || (media.episodes != nil && episode! >= media.episodes!)
        var form = ["status": finished ? "completed" : "watching"]
        if let episode { form["num_watched_episodes"] = String(episode) }
        guard let url = URL(string: "https://api.myanimelist.net/v2/anime/\(media.id)/my_list_status") else { return }
        _ = try? await HTTP.send(url, method: "PATCH", headers: [
            "Authorization": "Bearer \(token)",
            "Content-Type": "application/x-www-form-urlencoded",
        ], body: HTTP.form(form))
    }

    private func lookup(_ title: String, token: String) async -> (id: Int, episodes: Int?)? {
        if let hit = mediaCache[title] { return hit }
        guard title.count >= 3,
              let url = HTTP.url("https://api.myanimelist.net/v2/anime", query: ["q": title, "limit": "1", "fields": "num_episodes"]),
              let (status, data) = try? await HTTP.send(url, headers: ["Authorization": "Bearer \(token)"]), status == 200,
              let list = HTTP.object(data)?["data"] as? [[String: Any]],
              let node = list.first?["node"] as? [String: Any],
              let id = node["id"] as? Int else { return nil }
        let count = node["num_episodes"] as? Int
        let hit = (id: id, episodes: (count ?? 0) > 0 ? count : nil)
        mediaCache[title] = hit
        return hit
    }
}
