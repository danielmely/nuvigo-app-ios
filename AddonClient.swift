import Foundation
import Combine

struct Addon: Identifiable {
    let baseURL: URL          // manifest URL minus "/manifest.json"
    let manifest: AddonManifest
    var id: String { baseURL.absoluteString }

    /// Does this addon serve `resource` for the given content type and id?
    func supports(_ resource: String, type: String, id: String) -> Bool {
        guard let decl = manifest.resources.first(where: { $0.name == resource }) else { return false }
        let types = decl.types ?? manifest.types
        let prefixes = decl.idPrefixes ?? manifest.idPrefixes
        if let types, !types.contains(type) { return false }
        if let prefixes, !prefixes.contains(where: { id.hasPrefix($0) }) { return false }
        return true
    }
}

enum AddonError: LocalizedError {
    case invalidURL, badStatus(Int)
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "That doesn't look like a valid addon URL."
        case .badStatus(let c): return "The addon responded with an error (\(c))."
        }
    }
}

enum AddonClient {
    /// Accepts https://host/.../manifest.json, stremio://host/..., or a bare base URL.
    static func normalize(_ input: String) -> URL? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("stremio://") { s = "https://" + s.dropFirst("stremio://".count) }
        if s.hasSuffix("/manifest.json") { s = String(s.dropLast("/manifest.json".count)) }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), ["http", "https"].contains(url.scheme?.lowercased()) else { return nil }
        return url
    }

    static func fetchAddon(_ base: URL) async throws -> Addon {
        let url = URL(string: base.absoluteString + "/manifest.json")!
        let manifest: AddonManifest = try await get(url, cache: true)
        return Addon(baseURL: base, manifest: manifest)
    }

    /// `extra` maps Stremio extra names to values, e.g. ["genre": "Action"] or ["search": "dune"].
    static func catalog(_ addon: Addon, type: String, id: String, extra: [String: String] = [:]) async throws -> [MetaItem] {
        var path = "\(addon.baseURL.absoluteString)/catalog/\(type)/\(id)"
        if !extra.isEmpty {
            path += "/" + extra.sorted { $0.key < $1.key }.map { "\($0.key)=\(encode($0.value))" }.joined(separator: "&")
        }
        guard let url = URL(string: path + ".json") else { throw AddonError.invalidURL }
        let metas = (try await get(url, cache: true) as CatalogResponse).metas
        await ContentFilter.shared.note(metas)
        return metas
    }

    static func subtitles(_ addon: Addon, type: String, id: String) async throws -> [SubtitleTrack] {
        guard let url = URL(string: "\(addon.baseURL.absoluteString)/subtitles/\(type)/\(id).json") else { throw AddonError.invalidURL }
        return (try await get(url) as SubtitleResponse).subtitles
    }

    private static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
    }

    static func meta(_ addon: Addon, type: String, id: String) async throws -> MetaItem {
        guard let url = URL(string: "\(addon.baseURL.absoluteString)/meta/\(type)/\(id).json") else { throw AddonError.invalidURL }
        return (try await get(url, cache: true) as MetaResponse).meta
    }

    static func streams(_ addon: Addon, type: String, id: String) async throws -> [Stream] {
        guard let url = URL(string: "\(addon.baseURL.absoluteString)/stream/\(type)/\(id).json") else { throw AddonError.invalidURL }
        let hit = streamLock.withLock { streamCache[url] }
        if let hit, Date().timeIntervalSince(hit.at) < 600 { return hit.streams }
        let streams = (try await get(url) as StreamResponse).streams
        streamLock.withLock { streamCache[url] = (Date(), streams) }
        return streams
    }

    /// Stream lists fetched at start-up are kept for ten minutes so opening a title is instant.
    private nonisolated(unsafe) static var streamCache: [URL: (at: Date, streams: [Stream])] = [:]
    private static let streamLock = NSLock()
    static func clearStreamCache() { streamLock.withLock { streamCache = [:] } }

    /// With `cache`, a good response is saved to disk and used if the network fails later (offline).
    private static func get<T: Decodable>(_ url: URL, cache: Bool = false) async throws -> T {
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 20
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw AddonError.badStatus(http.statusCode)
            }
            let value = try JSONDecoder().decode(T.self, from: data)
            if cache { ResponseCache.save(data, for: url) }
            return value
        } catch {
            if cache, let saved = ResponseCache.load(url), let value = try? JSONDecoder().decode(T.self, from: saved) {
                return value
            }
            throw error
        }
    }
}
