import Foundation
import Combine

/// OpenSubtitles.com account. Adds subtitle tracks (in your phone's languages) to titles with IMDb ids.
@MainActor
final class OpenSubtitlesAuth: ObservableObject {
    struct Session: Codable {
        var token: String
        var baseURL: String
        var username: String
    }

    @Published private(set) var session: Session?
    @Published private(set) var busy = false
    @Published var error: String?

    private let keychainKey = "opensubtitles.session"
    private let userAgent = "NuviGo v1.0"
    var isSignedIn: Bool { session != nil }
    @Published private(set) var hasKey = UserKey.openSubtitles.isSet
    var isConfigured: Bool { hasKey }

    func saveKey(_ key: String) { UserKey.openSubtitles.save(key); hasKey = UserKey.openSubtitles.isSet }
    func removeKey() { UserKey.openSubtitles.remove(); hasKey = false; signOut() }

    init() {
        if let data = Keychain.load(key: keychainKey) {
            session = try? JSONDecoder().decode(Session.self, from: data)
        }
    }

    private func headers(token: String? = nil) -> [String: String] {
        var h = ["Api-Key": UserKey.openSubtitles.value,
                 "User-Agent": userAgent,
                 "Content-Type": "application/json",
                 "Accept": "application/json"]
        if let token { h["Authorization"] = "Bearer \(token)" }
        return h
    }

    func signIn(username: String, password: String) async {
        error = nil
        guard isConfigured else { error = "Add your OpenSubtitles API key first."; return }
        busy = true
        defer { busy = false }
        guard let url = URL(string: "https://api.opensubtitles.com/api/v1/login") else { return }
        do {
            let (status, data) = try await HTTP.send(url, method: "POST", headers: headers(),
                                                     body: HTTP.json(["username": username, "password": password]))
            guard status == 200, let obj = HTTP.object(data), let token = obj["token"] as? String else {
                error = status == 401 || status == 400 ? "Wrong username or password." : "OpenSubtitles returned \(status)."
                return
            }
            let base = (obj["base_url"] as? String) ?? "api.opensubtitles.com"
            let s = Session(token: token, baseURL: base, username: username)
            session = s
            if let enc = try? JSONEncoder().encode(s) { Keychain.save(enc, key: keychainKey) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func signOut() {
        session = nil
        Keychain.delete(key: keychainKey)
    }

    /// Your phone's preferred languages, then English.
    private var languages: [String] {
        var out: [String] = []
        for id in Locale.preferredLanguages {
            if let code = Locale(identifier: id).language.languageCode?.identifier, !out.contains(code) { out.append(code) }
        }
        if !out.contains("en") { out.append("en") }
        return out
    }

    /// Up to three tracks per language, most downloaded first. Each track is resolved to a file when selected.
    func search(_ ref: TitleRef, isSeries: Bool) async -> [SubtitleTrack] {
        guard let session else { return [] }
        let langs = languages
        var query = ["languages": langs.joined(separator: ","),
                     "order_by": "download_count",
                     "order_direction": "desc"]
        if isSeries, let s = ref.season, let e = ref.episode {
            query["parent_imdb_id"] = ref.imdb
            query["season_number"] = String(s)
            query["episode_number"] = String(e)
        } else {
            query["imdb_id"] = ref.imdb
        }
        guard let url = HTTP.url("https://\(session.baseURL)/api/v1/subtitles", query: query),
              let (status, data) = try? await HTTP.send(url, headers: headers(token: session.token)), status == 200,
              let list = HTTP.object(data)?["data"] as? [[String: Any]] else { return [] }

        var perLanguage: [String: Int] = [:]
        var tracks: [SubtitleTrack] = []
        for entry in list {
            guard let attrs = entry["attributes"] as? [String: Any],
                  let lang = attrs["language"] as? String,
                  let files = attrs["files"] as? [[String: Any]],
                  let fileID = files.first?["file_id"] as? Int,
                  perLanguage[lang, default: 0] < 3 else { continue }
            perLanguage[lang, default: 0] += 1
            tracks.append(SubtitleTrack(url: "", lang: lang, fileID: fileID))
        }
        // Keep the order of the user's languages.
        return tracks.sorted {
            (langs.firstIndex(of: $0.lang ?? "") ?? 99) < (langs.firstIndex(of: $1.lang ?? "") ?? 99)
        }
    }

    /// Turns a `fileID` into a temporary download link. Free accounts have a daily download limit.
    func download(fileID: Int) async -> URL? {
        guard let session, let url = URL(string: "https://\(session.baseURL)/api/v1/download"),
              let (status, data) = try? await HTTP.send(url, method: "POST", headers: headers(token: session.token),
                                                        body: HTTP.json(["file_id": fileID])),
              status == 200, let link = HTTP.object(data)?["link"] as? String else { return nil }
        return URL(string: link)
    }
}
