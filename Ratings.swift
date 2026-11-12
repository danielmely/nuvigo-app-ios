import Foundation
import Combine

/// IMDb and Rotten Tomatoes ratings (plus a plot summary), from OMDb.
struct TitleRatings: Codable {
    var imdb: String?      // "8.8"
    var votes: String?     // "2.7M"
    var tomatoes: String?  // "87%"
    var plot: String?
    var rated: String?     // "PG-13", "TV-MA", "Not Rated"
    var director: String?  // first credited director
    var cast: [String] = [] // first three actors
}

enum Ratings {
    static var isConfigured: Bool { OMDbKey.isSet }
    private nonisolated(unsafe) static var cache: [String: TitleRatings] = loadDisk()
    private static let lock = NSLock()

    private static var diskURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ratings.json")
    }
    private static func loadDisk() -> [String: TitleRatings] {
        (try? Data(contentsOf: diskURL)).flatMap { try? JSONDecoder().decode([String: TitleRatings].self, from: $0) } ?? [:]
    }
    /// Keeps looked-up ratings between launches (it lives in Caches, so Clear cache wipes it).
    static func persist() {
        lock.lock(); let snapshot = cache; lock.unlock()
        if let d = try? JSONEncoder().encode(snapshot) { try? d.write(to: diskURL, options: .atomic) }
    }
    static func clearCache() {
        lock.lock(); cache = [:]; lock.unlock()
        try? FileManager.default.removeItem(at: diskURL)
    }

    static func load(imdbID: String) async -> TitleRatings? {
        guard isConfigured, imdbID.hasPrefix("tt") else { return nil }
        lock.lock(); let hit = cache[imdbID]; lock.unlock()
        if let hit { return hit }
        guard let url = HTTP.url("https://www.omdbapi.com/", query: ["apikey": OMDbKey.value, "i": imdbID, "plot": "short"]),
              let (status, data) = try? await HTTP.send(url), status == 200,
              let obj = HTTP.object(data), (obj["Response"] as? String) == "True" else { return nil }

        func clean(_ v: Any?) -> String? {
            guard let s = v as? String, s != "N/A", !s.isEmpty else { return nil }
            return s
        }
        var out = TitleRatings()
        out.imdb = clean(obj["imdbRating"])
        out.votes = clean(obj["imdbVotes"]).flatMap(shortVotes)
        out.plot = clean(obj["Plot"])
        out.rated = clean(obj["Rated"])
        out.director = clean(obj["Director"]).flatMap { d in
            d.split(separator: ",").first.map { String($0).replacingOccurrences(of: #"\s*\(.*\)"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
        }
        out.cast = (clean(obj["Actors"]) ?? "").split(separator: ",").prefix(3).map { $0.trimmingCharacters(in: .whitespaces) }
        for r in (obj["Ratings"] as? [[String: Any]]) ?? [] where (r["Source"] as? String) == "Rotten Tomatoes" {
            out.tomatoes = clean(r["Value"])
        }
        lock.lock(); cache[imdbID] = out; lock.unlock()
        return out
    }

    /// "2,712,345" -> "2.7M"
    private static func shortVotes(_ s: String) -> String? {
        guard let n = Double(s.replacingOccurrences(of: ",", with: "")) else { return nil }
        switch n {
        case 1_000_000...: return String(format: "%.1fM", n / 1_000_000)
        case 1_000...: return String(format: "%.0fK", n / 1_000)
        default: return String(Int(n))
        }
    }
}
