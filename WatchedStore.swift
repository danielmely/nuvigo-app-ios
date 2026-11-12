import Foundation
import Combine

/// A movie or show you've already seen, with your own 1-10 rating if you gave one.
nonisolated struct WatchedItem: Codable, Identifiable, Hashable {
    let id: String          // IMDb id of the movie or show
    let type: String        // "movie" or "series"
    var name: String
    var poster: String?
    var year: String?
    var genres: [String]
    var rating: Int?        // 1...10
    var date: Date

    var metaItem: MetaItem {
        MetaItem(id: id, type: type, name: name, poster: poster, background: nil, description: nil,
                 releaseInfo: year, runtime: nil, genres: genres.isEmpty ? nil : genres, videos: nil)
    }
}

/// Everything you've watched and rated. Fed by the Mark watched button, finished playback and your Trakt history.
@MainActor
final class WatchedStore: ObservableObject {
    @Published private(set) var items: [WatchedItem] = []
    private var hidden: Set<String> = []     // removed on purpose, so a Trakt import doesn't bring them back

    private var itemsKey: String { "watchedItems" + ProfileStore.suffix }
    private var hiddenKey: String { "watchedHidden" + ProfileStore.suffix }

    init() { reload() }

    /// Re-reads what's saved on the device (used after an account sync).
    func reload() {
        if let data = UserDefaults.standard.data(forKey: itemsKey),
           let list = try? JSONDecoder().decode([WatchedItem].self, from: data) {
            items = list.sorted { $0.date > $1.date }
        } else { items = [] }
        hidden = Set(UserDefaults.standard.stringArray(forKey: hiddenKey) ?? [])
    }

    var sorted: [WatchedItem] { items }

    func clearAll() {
        items = []; hidden = []
        UserDefaults.standard.removeObject(forKey: itemsKey)
        UserDefaults.standard.removeObject(forKey: hiddenKey)
    }
    func contains(_ id: String) -> Bool { items.contains { $0.id == id } }
    func isHidden(_ id: String) -> Bool { hidden.contains(id) }

    func mark(_ meta: MetaItem, watched: Bool = true) {
        if watched {
            hidden.remove(meta.id)
            guard !contains(meta.id) else { persist(); return }
            items.insert(WatchedItem(id: meta.id, type: meta.type, name: meta.name, poster: meta.poster,
                                     year: meta.releaseInfo.map { String($0.prefix(4)) }, genres: meta.genres ?? [],
                                     rating: nil, date: Date()), at: 0)
        } else {
            remove(meta.id)
            return
        }
        persist()
    }

    func remove(_ id: String) {
        items.removeAll { $0.id == id }
        hidden.insert(id)
        persist()
    }

    func rate(_ id: String, _ value: Int?) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].rating = value.map { min(max($0, 1), 10) }
        persist()
    }

    /// Adds titles from your Trakt history that aren't here yet (unless you removed them).
    func addImported(_ metas: [MetaItem]) {
        var added = false
        for m in metas where !contains(m.id) && !hidden.contains(m.id) {
            items.append(WatchedItem(id: m.id, type: m.type, name: m.name, poster: m.poster,
                                     year: m.releaseInfo.map { String($0.prefix(4)) }, genres: m.genres ?? [],
                                     rating: nil, date: Date.distantPast.addingTimeInterval(1)))
            added = true
        }
        if added { items.sort { $0.date > $1.date }; persist() }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: itemsKey) }
        UserDefaults.standard.set(Array(hidden), forKey: hiddenKey)
    }
}

// MARK: Recommendations

struct Recommendation: Identifiable {
    let item: MetaItem
    let percent: Int       // "likely to like" score, 40...99
    let reason: String
    var id: String { item.id }
}

/// Picks titles you haven't seen that match the genres of what you rated highly.
enum Recommender {
    static func recommend(from watched: [WatchedItem], candidates: [MetaItem], count: Int = 3) -> [Recommendation] {
        let seen = Set(watched.map(\.id))

        // Taste: each genre gets +/- weight from your ratings. Unrated titles count as a mild like (7).
        var weight: [String: Double] = [:]
        for w in watched {
            let r = Double((w.rating ?? 7) - 5) / 5            // 1 -> -0.8, 5 -> 0, 10 -> +1
            for g in Set(w.genres) { weight[g, default: 0] += r }
        }
        let peak = max(weight.values.map(abs).max() ?? 1, 0.0001)
        let taste = weight.mapValues { $0 / peak }              // -1...1
        guard !taste.isEmpty else { return [] }

        let seriesShare = Double(watched.filter { $0.type == "series" }.count) / Double(max(watched.count, 1))

        var scored: [(Recommendation, Double)] = []
        var used = Set<String>()
        for c in candidates where !seen.contains(c.id) && used.insert(c.id).inserted {
            guard let genres = c.genres, !genres.isEmpty else { continue }
            let known = genres.compactMap { taste[$0] }
            guard !known.isEmpty else { continue }
            var raw = known.reduce(0, +) / Double(genres.count)
            raw += (c.type == "series" ? seriesShare : 1 - seriesShare) * 0.1   // lean toward what you watch more
            let pct = min(99, max(40, Int((62 + 36 * raw).rounded())))
            scored.append((Recommendation(item: c, percent: pct, reason: reason(for: c, watched: watched)), raw))
        }
        // Best three by score, shown highest percentage first (left to right).
        return scored.sorted { $0.1 > $1.1 }.prefix(count).map(\.0).sorted { $0.percent > $1.percent }
    }

    /// "Because you rated Inception 9/10", using your highest-rated title that shares a genre.
    private static func reason(for c: MetaItem, watched: [WatchedItem]) -> String {
        let mine = Set(c.genres ?? [])
        let match = watched.filter { !mine.isDisjoint(with: $0.genres) }
            .max { ($0.rating ?? 7) < ($1.rating ?? 7) }
        guard let m = match else { return "Matches your taste" }
        if let r = m.rating { return "Because you rated \(m.name) \(r)/10" }
        return "Because you watched \(m.name)"
    }
}
