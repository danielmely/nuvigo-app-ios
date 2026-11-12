import Foundation
import Combine

/// A folder on a media server, such as "Movies" or "TV Shows".
nonisolated struct LibraryFolder: Identifiable, Hashable {
    let id: String
    let name: String
}

/// A folder together with the server it lives on.
nonisolated struct LibraryFolderRef: Identifiable, Hashable {
    let prefix: String
    let sourceName: String
    let folder: LibraryFolder

    var id: String { "\(prefix)|\(folder.id)" }
    var title: String { "\(sourceName) · \(folder.name)" }
}

/// Your own media server (Jellyfin, Plex). Ids carry a prefix ("jf:", "plex:") so they never
/// get mixed up with addon ids.
@MainActor
protocol LibrarySource: AnyObject {
    var sourceName: String { get }
    var idPrefix: String { get }
    var isConnected: Bool { get }
    func libraries() async -> [LibraryFolder]
    func items(in folder: LibraryFolder) async -> [MetaItem]
    func search(_ query: String) async -> [MetaItem]
    func meta(id: String) async -> MetaItem?
    func streamURL(id: String) -> URL?
}

private func minutesText(_ minutes: Int?) -> String? {
    guard let minutes, minutes > 0 else { return nil }
    return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
}

// MARK: - Jellyfin

@MainActor
final class JellyfinSource: ObservableObject, LibrarySource {
    struct Session: Codable, Equatable {
        var server: String
        var token: String
        var userID: String
        var username: String
    }

    @Published private(set) var session: Session?
    @Published private(set) var busy = false
    @Published var error: String?

    let sourceName = "Jellyfin"
    let idPrefix = "jf:"
    var isConnected: Bool { session != nil }
    private let keychainKey = "jellyfin.session"

    init() {
        if let data = Keychain.load(key: keychainKey) {
            session = try? JSONDecoder().decode(Session.self, from: data)
        }
    }

    private func headers(token: String?) -> [String: String] {
        var auth = "MediaBrowser Client=\"NuviGo\", Device=\"iPhone\", DeviceId=\"\(DeviceID.value)\", Version=\"1.0\""
        if let token { auth += ", Token=\"\(token)\"" }
        return ["X-Emby-Authorization": auth, "Content-Type": "application/json", "Accept": "application/json"]
    }

    func signIn(server raw: String, username: String, password: String) async {
        error = nil
        busy = true
        defer { busy = false }
        var server = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while server.hasSuffix("/") { server.removeLast() }
        if !server.contains("://") { server = "http://" + server }
        guard let url = URL(string: server + "/Users/AuthenticateByName") else {
            error = "That server address doesn't look right."
            return
        }
        do {
            let (status, data) = try await HTTP.send(url, method: "POST", headers: headers(token: nil),
                                                     body: HTTP.json(["Username": username, "Pw": password]))
            guard status == 200, let obj = HTTP.object(data),
                  let token = obj["AccessToken"] as? String,
                  let user = obj["User"] as? [String: Any],
                  let uid = user["Id"] as? String else {
                error = status == 401 ? "Wrong username or password." : "The server returned \(status)."
                return
            }
            let s = Session(server: server, token: token, userID: uid, username: username)
            if let enc = try? JSONEncoder().encode(s) { Keychain.save(enc, key: keychainKey) }
            session = s
        } catch {
            self.error = "Couldn't reach the server. \(error.localizedDescription)"
        }
    }

    func signOut() {
        session = nil
        Keychain.delete(key: keychainKey)
    }

    // MARK: Requests

    private func get(_ path: String, _ query: [String: String] = [:]) async -> [String: Any]? {
        guard let s = session, let url = HTTP.url(s.server + path, query: query),
              let (status, data) = try? await HTTP.send(url, headers: headers(token: s.token)),
              status == 200 else { return nil }
        return HTTP.object(data)
    }

    private func raw(_ id: String) -> String { String(id.dropFirst(idPrefix.count)) }

    private func map(_ d: [String: Any]) -> MetaItem? {
        guard let s = session, let id = d["Id"] as? String, let name = d["Name"] as? String,
              let kind = d["Type"] as? String, kind == "Movie" || kind == "Series" else { return nil }
        let tags = d["ImageTags"] as? [String: Any]
        let backdrops = d["BackdropImageTags"] as? [Any]
        let ticks = d["RunTimeTicks"] as? Int
        return MetaItem(
            id: idPrefix + id, type: kind == "Series" ? "series" : "movie", name: name,
            poster: tags?["Primary"] != nil ? "\(s.server)/Items/\(id)/Images/Primary?maxWidth=400" : nil,
            background: (backdrops?.isEmpty == false) ? "\(s.server)/Items/\(id)/Images/Backdrop?maxWidth=1000" : nil,
            description: d["Overview"] as? String,
            releaseInfo: (d["ProductionYear"] as? Int).map(String.init),
            runtime: minutesText(ticks.map { $0 / 600_000_000 }),
            genres: d["Genres"] as? [String], videos: nil)
    }

    private let fields = "Overview,Genres,ProductionYear,RunTimeTicks"

    // MARK: LibrarySource

    func libraries() async -> [LibraryFolder] {
        guard let s = session, let obj = await get("/Users/\(s.userID)/Views"),
              let items = obj["Items"] as? [[String: Any]] else { return [] }
        return items.compactMap { d in
            guard let id = d["Id"] as? String, let name = d["Name"] as? String,
                  ["movies", "tvshows"].contains(d["CollectionType"] as? String ?? "") else { return nil }
            return LibraryFolder(id: id, name: name)
        }
    }

    func items(in folder: LibraryFolder) async -> [MetaItem] {
        guard let s = session,
              let obj = await get("/Users/\(s.userID)/Items", [
                "ParentId": folder.id, "Recursive": "true", "IncludeItemTypes": "Movie,Series",
                "SortBy": "SortName", "Fields": fields, "Limit": "400"]),
              let items = obj["Items"] as? [[String: Any]] else { return [] }
        return items.compactMap(map)
    }

    func search(_ query: String) async -> [MetaItem] {
        guard let s = session,
              let obj = await get("/Users/\(s.userID)/Items", [
                "SearchTerm": query, "Recursive": "true", "IncludeItemTypes": "Movie,Series",
                "Fields": fields, "Limit": "20"]),
              let items = obj["Items"] as? [[String: Any]] else { return [] }
        return items.compactMap(map)
    }

    func meta(id: String) async -> MetaItem? {
        guard let s = session, let d = await get("/Users/\(s.userID)/Items/\(raw(id))", ["Fields": fields]),
              var item = map(d) else { return nil }
        guard item.type == "series",
              let eps = await get("/Shows/\(raw(id))/Episodes", ["UserId": s.userID, "Fields": "Overview"]),
              let list = eps["Items"] as? [[String: Any]] else { return item }
        let videos: [Video] = list.compactMap { e in
            guard let eid = e["Id"] as? String else { return nil }
            let hasThumb = (e["ImageTags"] as? [String: Any])?["Primary"] != nil
            return Video(id: idPrefix + eid, title: e["Name"] as? String, name: nil,
                         season: e["ParentIndexNumber"] as? Int, episode: e["IndexNumber"] as? Int,
                         thumbnail: hasThumb ? "\(s.server)/Items/\(eid)/Images/Primary?maxWidth=400" : nil)
        }
        item = MetaItem(id: item.id, type: item.type, name: item.name, poster: item.poster,
                        background: item.background, description: item.description,
                        releaseInfo: item.releaseInfo, runtime: item.runtime, genres: item.genres, videos: videos)
        return item
    }

    /// An HLS stream the server transcodes to H.264/AAC, which AVPlayer can always play.
    func streamURL(id: String) -> URL? {
        guard let s = session else { return nil }
        let rawID = raw(id)
        return HTTP.url("\(s.server)/Videos/\(rawID)/master.m3u8", query: [
            "api_key": s.token, "MediaSourceId": rawID, "DeviceId": DeviceID.value,
            "VideoCodec": "h264", "AudioCodec": "aac", "TranscodingMaxAudioChannels": "2",
            "SegmentContainer": "ts", "MaxStreamingBitrate": "20000000"])
    }
}

// MARK: - Plex

@MainActor
final class PlexSource: ObservableObject, LibrarySource {
    struct Session: Codable, Equatable {
        var userToken: String
        var server: String
        var serverToken: String
        var serverName: String
    }

    struct Pin: Equatable {
        let id: Int
        let code: String
        let authURL: URL
    }

    @Published private(set) var session: Session?
    @Published private(set) var pin: Pin?
    @Published var error: String?

    let sourceName = "Plex"
    let idPrefix = "plex:"
    var isConnected: Bool { session != nil }
    private let keychainKey = "plex.session"

    init() {
        if let data = Keychain.load(key: keychainKey) {
            session = try? JSONDecoder().decode(Session.self, from: data)
        }
    }

    private var plexHeaders: [String: String] {
        ["Accept": "application/json",
         "X-Plex-Product": "NuviGo",
         "X-Plex-Version": "1.0",
         "X-Plex-Platform": "iOS",
         "X-Plex-Client-Identifier": DeviceID.value]
    }

    /// Shows `pin` (a link to approve on plex.tv), polls until approved, then finds your server.
    /// Cancel the surrounding Task to abort.
    func signIn() async {
        error = nil
        defer { pin = nil }
        do {
            guard let url = HTTP.url("https://plex.tv/api/v2/pins", query: ["strong": "true"]) else { return }
            let (status, data) = try await HTTP.send(url, method: "POST", headers: plexHeaders)
            guard (status == 200 || status == 201), let obj = HTTP.object(data),
                  let id = obj["id"] as? Int, let code = obj["code"] as? String,
                  let auth = URL(string: "https://app.plex.tv/auth#?clientID=\(DeviceID.value)&code=\(code)&context%5Bdevice%5D%5Bproduct%5D=NuviGo")
            else { error = "Plex returned \(status)."; return }
            pin = Pin(id: id, code: code, authURL: auth)

            for _ in 0..<150 {   // about five minutes
                try await Task.sleep(for: .seconds(2))
                guard let poll = HTTP.url("https://plex.tv/api/v2/pins/\(id)", query: ["code": code]) else { return }
                let (_, body) = try await HTTP.send(poll, headers: plexHeaders)
                if let token = HTTP.object(body)?["authToken"] as? String {
                    await connectServer(userToken: token)
                    return
                }
            }
            error = "Sign-in timed out. Try again."
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    func signOut() {
        session = nil
        Keychain.delete(key: keychainKey)
    }

    /// Picks the first server on your account that answers, preferring direct connections over relays.
    private func connectServer(userToken: String) async {
        guard let url = HTTP.url("https://plex.tv/api/v2/resources", query: ["includeHttps": "1", "includeRelay": "1"]),
              let (status, data) = try? await HTTP.send(url, headers: plexHeaders.merging(["X-Plex-Token": userToken]) { $1 }),
              status == 200, let devices = HTTP.array(data) else {
            error = "Couldn't list your Plex servers."
            return
        }
        let servers = devices.filter { ($0["provides"] as? String ?? "").contains("server") }
            .sorted { ($0["owned"] as? Bool ?? false) && !($1["owned"] as? Bool ?? false) }
        for device in servers {
            let token = (device["accessToken"] as? String) ?? userToken
            let conns = (device["connections"] as? [[String: Any]] ?? [])
                .sorted { !($0["relay"] as? Bool ?? false) && ($1["relay"] as? Bool ?? false) }
            for conn in conns {
                guard var uri = conn["uri"] as? String else { continue }
                while uri.hasSuffix("/") { uri.removeLast() }
                guard let probe = URL(string: uri + "/identity"),
                      let (code, _) = try? await HTTP.send(probe, headers: plexHeaders.merging(["X-Plex-Token": token]) { $1 }, timeout: 4),
                      code == 200 else { continue }
                let s = Session(userToken: userToken, server: uri, serverToken: token,
                                serverName: (device["name"] as? String) ?? "Plex")
                if let enc = try? JSONEncoder().encode(s) { Keychain.save(enc, key: keychainKey) }
                session = s
                return
            }
        }
        error = "Signed in, but none of your Plex servers could be reached."
    }

    // MARK: Requests

    private func get(_ path: String, _ query: [String: String] = [:]) async -> [String: Any]? {
        guard let s = session, let url = HTTP.url(s.server + path, query: query),
              let (status, data) = try? await HTTP.send(url, headers: plexHeaders.merging(["X-Plex-Token": s.serverToken]) { $1 }),
              status == 200 else { return nil }
        return HTTP.object(data)?["MediaContainer"] as? [String: Any]
    }

    private func raw(_ id: String) -> String { String(id.dropFirst(idPrefix.count)) }

    private func image(_ path: String?) -> String? {
        guard let s = session, let path else { return nil }
        return "\(s.server)\(path)?X-Plex-Token=\(s.serverToken)"
    }

    private func map(_ d: [String: Any]) -> MetaItem? {
        let key = (d["ratingKey"] as? String) ?? (d["ratingKey"] as? Int).map(String.init)
        guard let key, let title = d["title"] as? String, let kind = d["type"] as? String,
              kind == "movie" || kind == "show" else { return nil }
        let genres = (d["Genre"] as? [[String: Any]])?.compactMap { $0["tag"] as? String }
        let minutes = (d["duration"] as? Int).map { $0 / 60_000 }
        return MetaItem(
            id: idPrefix + key, type: kind == "show" ? "series" : "movie", name: title,
            poster: image(d["thumb"] as? String), background: image(d["art"] as? String),
            description: d["summary"] as? String,
            releaseInfo: (d["year"] as? Int).map(String.init),
            runtime: kind == "movie" ? minutesText(minutes) : nil,
            genres: genres, videos: nil)
    }

    // MARK: LibrarySource

    func libraries() async -> [LibraryFolder] {
        guard let c = await get("/library/sections"), let dirs = c["Directory"] as? [[String: Any]] else { return [] }
        return dirs.compactMap { d in
            guard let key = (d["key"] as? String) ?? (d["key"] as? Int).map(String.init),
                  let title = d["title"] as? String,
                  ["movie", "show"].contains(d["type"] as? String ?? "") else { return nil }
            return LibraryFolder(id: key, name: title)
        }
    }

    func items(in folder: LibraryFolder) async -> [MetaItem] {
        guard let c = await get("/library/sections/\(folder.id)/all",
                                ["X-Plex-Container-Start": "0", "X-Plex-Container-Size": "400"]),
              let list = c["Metadata"] as? [[String: Any]] else { return [] }
        return list.compactMap(map)
    }

    func search(_ query: String) async -> [MetaItem] {
        guard let c = await get("/search", ["query": query, "limit": "20"]),
              let list = c["Metadata"] as? [[String: Any]] else { return [] }
        return list.compactMap(map)
    }

    func meta(id: String) async -> MetaItem? {
        guard let c = await get("/library/metadata/\(raw(id))"),
              let d = (c["Metadata"] as? [[String: Any]])?.first, let item = map(d) else { return nil }
        guard item.type == "series",
              let leaves = await get("/library/metadata/\(raw(id))/allLeaves"),
              let list = leaves["Metadata"] as? [[String: Any]] else { return item }
        let videos: [Video] = list.compactMap { e in
            guard let key = (e["ratingKey"] as? String) ?? (e["ratingKey"] as? Int).map(String.init) else { return nil }
            return Video(id: idPrefix + key, title: e["title"] as? String, name: nil,
                         season: e["parentIndex"] as? Int, episode: e["index"] as? Int,
                         thumbnail: image(e["thumb"] as? String))
        }
        return MetaItem(id: item.id, type: item.type, name: item.name, poster: item.poster,
                        background: item.background, description: item.description,
                        releaseInfo: item.releaseInfo, runtime: item.runtime, genres: item.genres, videos: videos)
    }

    /// An HLS stream Plex transcodes for the phone, which AVPlayer can always play.
    func streamURL(id: String) -> URL? {
        guard let s = session else { return nil }
        return HTTP.url("\(s.server)/video/:/transcode/universal/start.m3u8", query: [
            "path": "/library/metadata/\(raw(id))", "mediaIndex": "0", "partIndex": "0",
            "protocol": "hls", "offset": "0", "fastSeek": "1", "directPlay": "0", "directStream": "1",
            "maxVideoBitrate": "20000", "session": DeviceID.value,
            "X-Plex-Platform": "iOS", "X-Plex-Product": "NuviGo",
            "X-Plex-Client-Identifier": DeviceID.value, "X-Plex-Token": s.serverToken])
    }
}
