import Foundation
import Combine

enum FeatureFlags {
    /// Turns torrent playback through a debrid service on or off. Set to false for an App Store build
    /// if you'd rather not ship it: reviewers look hard at torrent-related features.
    static let debridEnabled = true
}

enum DebridError: LocalizedError {
    case notConnected, notCached
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Connect a debrid account in the Account tab first."
        case .notCached: return "This torrent isn't cached yet, so it can't start instantly. Try another stream."
        case .failed(let m): return m
        }
    }
}

enum DebridService: String, CaseIterable, Identifiable {
    case realDebrid, torBox, allDebrid, premiumize

    var id: String { rawValue }

    var name: String {
        switch self {
        case .realDebrid: return "Real-Debrid"
        case .torBox: return "TorBox"
        case .allDebrid: return "AllDebrid"
        case .premiumize: return "Premiumize"
        }
    }

    var tokenHelp: String {
        switch self {
        case .realDebrid: return "Find your token at real-debrid.com/apitoken."
        case .torBox: return "Find your API key in TorBox → Settings."
        case .allDebrid: return "Create an API key at alldebrid.com/apikeys."
        case .premiumize: return "Find your API key at premiumize.me/account."
        }
    }

    var keychainKey: String {
        switch self {
        case .realDebrid: return "debrid.realdebrid.token"   // same key as before, so existing logins carry over
        case .torBox: return "debrid.torbox.token"
        case .allDebrid: return "debrid.alldebrid.token"
        case .premiumize: return "debrid.premiumize.token"
        }
    }
}

nonisolated struct DebridAccount {
    var username: String?
    var isPremium: Bool
}

/// The user's own debrid accounts (Real-Debrid, TorBox, AllDebrid). Tokens live in the Keychain.
/// More than one can be connected: a torrent is tried on each in turn until one has it cached.
@MainActor
final class DebridAuth: ObservableObject {
    @Published private(set) var tokens: [DebridService: String] = [:]
    @Published private(set) var accounts: [DebridService: DebridAccount] = [:]
    @Published private(set) var checking: DebridService?
    @Published var error: String?

    init() {
        for s in DebridService.allCases {
            if let data = Keychain.load(key: s.keychainKey), let t = String(data: data, encoding: .utf8) {
                tokens[s] = t
                Task { await refreshUser(s) }
            }
        }
    }

    var isConnected: Bool { FeatureFlags.debridEnabled && !tokens.isEmpty }

    func isConnected(_ s: DebridService) -> Bool { tokens[s] != nil }

    /// "Real-Debrid, TorBox"
    var connectedNames: String {
        DebridService.allCases.filter { tokens[$0] != nil }.map(\.name).joined(separator: ", ")
    }

    /// Validates the token with the service before saving it.
    func connect(_ service: DebridService, token raw: String) async {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        checking = service; error = nil
        defer { checking = nil }
        do {
            let account = try await Self.user(service, token: t)
            Keychain.save(Data(t.utf8), key: service.keychainKey)
            tokens[service] = t
            accounts[service] = account
        } catch {
            self.error = error.localizedDescription
        }
    }

    func disconnect(_ service: DebridService) {
        tokens[service] = nil; accounts[service] = nil; error = nil
        Keychain.delete(key: service.keychainKey)
    }

    func refreshUser(_ service: DebridService) async {
        guard let token = tokens[service], let a = try? await Self.user(service, token: token) else { return }
        accounts[service] = a
    }

    private static func user(_ s: DebridService, token: String) async throws -> DebridAccount {
        switch s {
        case .realDebrid: return try await RealDebrid.user(token: token)
        case .torBox: return try await TorBox.user(token: token)
        case .allDebrid: return try await AllDebrid.user(token: token)
        case .premiumize: return try await Premiumize.user(token: token)
        }
    }

    /// Turns a torrent info hash into a direct, playable URL using the first connected service that has it.
    func resolve(infoHash: String, fileIdx: Int?) async throws -> URL {
        guard isConnected else { throw DebridError.notConnected }
        var lastError: Error = DebridError.notCached
        for service in DebridService.allCases {
            guard let token = tokens[service] else { continue }
            do {
                switch service {
                case .realDebrid: return try await RealDebrid.resolve(token: token, infoHash: infoHash, fileIdx: fileIdx)
                case .torBox: return try await TorBox.resolve(token: token, infoHash: infoHash, fileIdx: fileIdx)
                case .allDebrid: return try await AllDebrid.resolve(token: token, infoHash: infoHash, fileIdx: fileIdx)
                case .premiumize: return try await Premiumize.resolve(token: token, infoHash: infoHash, fileIdx: fileIdx)
                }
            } catch DebridError.notCached {
                continue
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}

// MARK: - Picking a file

enum FilePick {
    private static func ext(_ name: String) -> String { (name as NSString).pathExtension.lowercased() }

    /// Index of the file to play. Honors the addon's file index when given, otherwise the biggest video,
    /// preferring formats AVPlayer plays.
    static func best(names: [String], sizes: [Int], fileIdx: Int?) -> Int? {
        if let i = fileIdx, names.indices.contains(i) { return i }
        let video = names.indices.filter { ["mp4", "m4v", "mov", "mkv", "avi", "webm"].contains(ext(names[$0])) }
        let friendly = video.filter { ["mp4", "m4v", "mov"].contains(ext(names[$0])) }
        let size: (Int) -> Int = { sizes.indices.contains($0) ? sizes[$0] : 0 }
        return friendly.max { size($0) < size($1) } ?? video.max { size($0) < size($1) }
    }
}

// MARK: - Real-Debrid

enum RealDebrid {
    private static let base = "https://api.real-debrid.com/rest/1.0"

    private struct User: Decodable { let username: String; let type: String? }
    private struct Added: Decodable { let id: String }
    private struct TFile: Decodable { let id: Int; let path: String; let bytes: Int }
    private struct TorrentInfo: Decodable { let status: String; let files: [TFile]?; let links: [String]? }
    private struct Unrestricted: Decodable { let download: String }

    static func user(token: String) async throws -> DebridAccount {
        let (status, data) = try await request("/user", token: token)
        guard status == 200, let user = try? JSONDecoder().decode(User.self, from: data) else { throw failure(status) }
        return DebridAccount(username: user.username, isPremium: user.type == "premium")
    }

    /// Adds the magnet, picks a file, waits briefly for it to be ready, then unrestricts the link.
    /// Cached torrents are ready within a second or two; anything slower is treated as "not cached".
    static func resolve(token: String, infoHash: String, fileIdx: Int?) async throws -> URL {
        let (s1, d1) = try await request("/torrents/addMagnet", method: "POST",
                                         form: ["magnet": "magnet:?xt=urn:btih:\(infoHash)"], token: token)
        guard s1 == 200 || s1 == 201, let added = try? JSONDecoder().decode(Added.self, from: d1) else { throw failure(s1) }

        do {
            var selected = false
            for _ in 0..<20 {
                let (s, d) = try await request("/torrents/info/\(added.id)", token: token)
                guard s == 200, let info = try? JSONDecoder().decode(TorrentInfo.self, from: d) else { throw failure(s) }

                switch info.status {
                case "waiting_files_selection":
                    if !selected {
                        let files = info.files ?? []
                        let i = FilePick.best(names: files.map(\.path), sizes: files.map(\.bytes), fileIdx: fileIdx)
                        _ = try await request("/torrents/selectFiles/\(added.id)", method: "POST",
                                              form: ["files": i.map { String(files[$0].id) } ?? "all"], token: token)
                        selected = true
                    }
                case "downloaded":
                    guard let link = info.links?.first else { throw DebridError.failed("Real-Debrid returned no link.") }
                    let (s2, d2) = try await request("/unrestrict/link", method: "POST", form: ["link": link], token: token)
                    guard s2 == 200,
                          let un = try? JSONDecoder().decode(Unrestricted.self, from: d2),
                          let url = URL(string: un.download) else { throw failure(s2) }
                    return url
                case "magnet_error", "error", "virus", "dead":
                    throw DebridError.failed("Real-Debrid couldn't process this torrent (\(info.status)).")
                default:
                    break   // magnet_conversion, queued, downloading…
                }
                try await Task.sleep(for: .seconds(1))
            }
            throw DebridError.notCached
        } catch {
            _ = try? await request("/torrents/delete/\(added.id)", method: "DELETE", token: token)
            throw error
        }
    }

    private static func failure(_ status: Int) -> DebridError {
        switch status {
        case 401, 403: return .failed("Real-Debrid rejected your API token.")
        case 429: return .failed("Real-Debrid is rate limiting requests. Try again in a minute.")
        default: return .failed("Real-Debrid returned an error (\(status)).")
        }
    }

    private static func request(_ path: String, method: String = "GET", form: [String: String]? = nil,
                                token: String) async throws -> (Int, Data) {
        var headers = ["Authorization": "Bearer \(token)"]
        if form != nil { headers["Content-Type"] = "application/x-www-form-urlencoded" }
        return try await HTTP.send(URL(string: base + path)!, method: method, headers: headers,
                                   body: form.map(HTTP.form), timeout: 30)
    }
}

// MARK: - TorBox

enum TorBox {
    private static let base = "https://api.torbox.app/v1/api"

    static func user(token: String) async throws -> DebridAccount {
        let (status, data) = try await HTTP.send(URL(string: base + "/user/me")!,
                                                 headers: ["Authorization": "Bearer \(token)"])
        guard status == 200, let d = HTTP.object(data)?["data"] as? [String: Any] else { throw failure(status) }
        let plan = d["plan"] as? Int ?? 0
        return DebridAccount(username: d["email"] as? String, isPremium: plan > 0)
    }

    /// Only starts torrents TorBox already has cached, so playback is instant.
    static func resolve(token: String, infoHash: String, fileIdx: Int?) async throws -> URL {
        let auth = ["Authorization": "Bearer \(token)"]

        // 1. Is it cached?
        guard let checkURL = HTTP.url(base + "/torrents/checkcached",
                                      query: ["hash": infoHash, "format": "object", "list_files": "false"]) else { throw DebridError.notCached }
        let (cs, cd) = try await HTTP.send(checkURL, headers: auth, timeout: 30)
        guard cs == 200 else { throw failure(cs) }
        let cached = (HTTP.object(cd)?["data"] as? [String: Any]).map { !$0.isEmpty }
            ?? ((HTTP.object(cd)?["data"] as? [Any]).map { !$0.isEmpty } ?? false)
        guard cached else { throw DebridError.notCached }

        // 2. Add it (instant for cached torrents).
        let boundary = "nuvigo-\(UUID().uuidString)"
        let body = HTTP.multipart(["magnet": "magnet:?xt=urn:btih:\(infoHash)", "seed": "1", "allow_zip": "false"],
                                  boundary: boundary)
        var headers = auth
        headers["Content-Type"] = "multipart/form-data; boundary=\(boundary)"
        let (as_, ad) = try await HTTP.send(URL(string: base + "/torrents/createtorrent")!, method: "POST",
                                            headers: headers, body: body, timeout: 30)
        guard (as_ == 200 || as_ == 201), let data = HTTP.object(ad)?["data"] as? [String: Any],
              let torrentID = data["torrent_id"] as? Int ?? data["id"] as? Int else { throw failure(as_) }

        // 3. Read the file list.
        for _ in 0..<10 {
            if let listURL = HTTP.url(base + "/torrents/mylist", query: ["id": String(torrentID), "bypass_cache": "true"]),
               let (ls, ld) = try? await HTTP.send(listURL, headers: auth), ls == 200,
               let t = HTTP.object(ld)?["data"] as? [String: Any],
               let files = t["files"] as? [[String: Any]], !files.isEmpty {
                let names = files.map { ($0["name"] as? String) ?? ($0["short_name"] as? String) ?? "" }
                let sizes = files.map { $0["size"] as? Int ?? 0 }
                guard let i = FilePick.best(names: names, sizes: sizes, fileIdx: fileIdx),
                      let fileID = files[i]["id"] as? Int else { throw DebridError.failed("No playable video file in this torrent.") }

                // 4. Get the download link.
                guard let dlURL = HTTP.url(base + "/torrents/requestdl", query: [
                        "token": token, "torrent_id": String(torrentID), "file_id": String(fileID), "zip_link": "false"]) else { break }
                let (ds, dd) = try await HTTP.send(dlURL, headers: auth)
                guard ds == 200, let link = HTTP.object(dd)?["data"] as? String, let url = URL(string: link) else { throw failure(ds) }
                return url
            }
            try await Task.sleep(for: .seconds(1))
        }
        throw DebridError.notCached
    }

    private static func failure(_ status: Int) -> DebridError {
        switch status {
        case 401, 403: return .failed("TorBox rejected your API key.")
        case 429: return .failed("TorBox is rate limiting requests. Try again in a minute.")
        default: return .failed("TorBox returned an error (\(status)).")
        }
    }
}

// MARK: - AllDebrid

enum AllDebrid {
    private static let base = "https://api.alldebrid.com"
    private static let agent = "NuviGo"

    static func user(token: String) async throws -> DebridAccount {
        let (status, data) = try await get("/v4/user", token: token)
        guard status == 200, let d = HTTP.object(data)?["data"] as? [String: Any],
              let user = d["user"] as? [String: Any] else { throw failure(status) }
        return DebridAccount(username: user["username"] as? String, isPremium: user["isPremium"] as? Bool ?? false)
    }

    /// AllDebrid reports whether a magnet is already cached ("ready") the moment it's uploaded.
    static func resolve(token: String, infoHash: String, fileIdx: Int?) async throws -> URL {
        let (us, ud) = try await post("/v4/magnet/upload", form: ["magnets[]": "magnet:?xt=urn:btih:\(infoHash)"], token: token)
        guard us == 200, let data = HTTP.object(ud)?["data"] as? [String: Any],
              let magnet = (data["magnets"] as? [[String: Any]])?.first else { throw failure(us) }
        if let err = magnet["error"] as? [String: Any], let msg = err["message"] as? String {
            throw DebridError.failed("AllDebrid: \(msg)")
        }
        guard let id = magnet["id"] as? Int else { throw DebridError.failed("AllDebrid returned no torrent id.") }

        do {
            guard magnet["ready"] as? Bool == true else { throw DebridError.notCached }

            let (ss, sd) = try await post("/v4.1/magnet/status", form: ["id": String(id)], token: token)
            guard ss == 200, let sdata = HTTP.object(sd)?["data"] as? [String: Any] else { throw failure(ss) }
            let status: [String: Any]? = (sdata["magnets"] as? [String: Any]) ?? (sdata["magnets"] as? [[String: Any]])?.first
            guard let links = status?["links"] as? [[String: Any]], !links.isEmpty else { throw DebridError.notCached }

            let names = links.map { ($0["filename"] as? String) ?? "" }
            let sizes = links.map { $0["size"] as? Int ?? 0 }
            guard let i = FilePick.best(names: names, sizes: sizes, fileIdx: fileIdx),
                  let link = links[i]["link"] as? String else { throw DebridError.failed("No playable video file in this torrent.") }

            let (ls, ld) = try await get("/v4/link/unlock", query: ["link": link], token: token)
            guard ls == 200, let udata = HTTP.object(ld)?["data"] as? [String: Any],
                  let direct = udata["link"] as? String, let url = URL(string: direct) else { throw failure(ls) }
            return url
        } catch {
            _ = try? await get("/v4/magnet/delete", query: ["id": String(id)], token: token)
            throw error
        }
    }

    private static func get(_ path: String, query: [String: String] = [:], token: String) async throws -> (Int, Data) {
        var q = query
        q["agent"] = agent
        return try await HTTP.send(HTTP.url(base + path, query: q)!, headers: ["Authorization": "Bearer \(token)"], timeout: 30)
    }

    private static func post(_ path: String, form: [String: String], token: String) async throws -> (Int, Data) {
        try await HTTP.send(HTTP.url(base + path, query: ["agent": agent])!, method: "POST",
                            headers: ["Authorization": "Bearer \(token)",
                                      "Content-Type": "application/x-www-form-urlencoded"],
                            body: HTTP.form(form), timeout: 30)
    }

    private static func failure(_ status: Int) -> DebridError {
        switch status {
        case 401, 403: return .failed("AllDebrid rejected your API key.")
        case 429: return .failed("AllDebrid is rate limiting requests. Try again in a minute.")
        default: return .failed("AllDebrid returned an error (\(status)).")
        }
    }
}

// MARK: - Premiumize

enum Premiumize {
    private static let base = "https://www.premiumize.me/api"

    static func user(token: String) async throws -> DebridAccount {
        guard let url = HTTP.url(base + "/account/info", query: ["apikey": token]) else { throw failure(0) }
        let (status, data) = try await HTTP.send(url)
        guard status == 200, let obj = HTTP.object(data), obj["status"] as? String == "success" else {
            throw failure(status == 200 ? 401 : status)
        }
        let until = (obj["premium_until"] as? Double) ?? Double(obj["premium_until"] as? Int ?? 0)
        let id = (obj["customer_id"] as? String) ?? (obj["customer_id"] as? Int).map(String.init)
        return DebridAccount(username: id, isPremium: until > Date().timeIntervalSince1970)
    }

    /// Direct download only works for torrents Premiumize already has cached; anything else is "not cached".
    static func resolve(token: String, infoHash: String, fileIdx: Int?) async throws -> URL {
        guard let url = HTTP.url(base + "/transfer/directdl", query: ["apikey": token]) else { throw DebridError.notCached }
        let (status, data) = try await HTTP.send(url, method: "POST",
                                                 headers: ["Content-Type": "application/x-www-form-urlencoded"],
                                                 body: HTTP.form(["src": "magnet:?xt=urn:btih:\(infoHash)"]), timeout: 30)
        guard status == 200 else { throw failure(status) }
        guard let obj = HTTP.object(data), obj["status"] as? String == "success",
              let files = obj["content"] as? [[String: Any]], !files.isEmpty else { throw DebridError.notCached }
        let names = files.map { ($0["path"] as? String) ?? "" }
        let sizes = files.map { ($0["size"] as? Int) ?? Int($0["size"] as? Double ?? 0) }
        guard let i = FilePick.best(names: names, sizes: sizes, fileIdx: fileIdx),
              let link = (files[i]["stream_link"] as? String) ?? (files[i]["link"] as? String),
              let direct = URL(string: link) else { throw DebridError.failed("No playable video file in this torrent.") }
        return direct
    }

    private static func failure(_ status: Int) -> DebridError {
        switch status {
        case 401, 403: return .failed("Premiumize rejected your API key.")
        case 429: return .failed("Premiumize is rate limiting requests. Try again in a minute.")
        default: return .failed("Premiumize returned an error (\(status)).")
        }
    }
}
