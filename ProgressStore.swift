import Foundation

struct WatchProgress: Codable, Identifiable {
    let key: String            // stream id (movie id or episode id)
    let itemID: String         // parent title id
    let itemType: String
    let name: String
    let poster: String?
    let episodeLabel: String?
    var position: Double       // seconds
    var duration: Double
    var updated: Date

    var id: String { key }
    var fraction: Double { duration > 0 ? position / duration : 0 }

    /// Enough to open the detail screen; DetailView refetches full metadata.
    var metaItem: MetaItem {
        MetaItem(id: itemID, type: itemType, name: name, poster: poster, background: nil,
                 description: nil, releaseInfo: nil, runtime: nil, genres: nil, videos: nil)
    }
}

/// Remembers where you stopped. Stored locally; entries past 90% are treated as finished and dropped.
@MainActor
final class ProgressStore: ObservableObject {
    @Published private(set) var entries: [String: WatchProgress] = [:]
    private var defaultsKey: String { "watchProgress" + ProfileStore.suffix }
    /// Called when something is watched past 90% (the app uses it to fill the Already watched list).
    var onFinished: (@MainActor (MetaItem) -> Void)?
    /// Last position seen per stream while playing, so watch time can be counted for the stats page.
    private var lastPosition: [String: Double] = [:]
    /// Streams that passed 90% this session. Used to delete finished downloads once the player is closed.
    private var finishedKeys = Set<String>()

    func takeFinishedKeys() -> Set<String> {
        defer { finishedKeys = [] }
        return finishedKeys
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let list = try? JSONDecoder().decode([WatchProgress].self, from: data) {
            entries = Dictionary(list.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        }
    }

    /// Re-reads what's saved on the device (used after an account sync brings in newer progress).
    func reload() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let list = try? JSONDecoder().decode([WatchProgress].self, from: data) else { entries = [:]; return }
        entries = Dictionary(list.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func clearAll() {
        entries = [:]
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    func progress(for key: String) -> WatchProgress? { entries[key] }

    /// Seconds to resume from, or 0 to start at the beginning.
    func resumePosition(for key: String) -> Double {
        guard let p = entries[key], p.fraction >= 0.02, p.fraction < 0.9 else { return 0 }
        return p.position
    }

    func update(_ ctx: PlaybackContext, position: Double, duration: Double) {
        guard !PrivateMode.isOn else { return }
        guard duration > 0, position.isFinite else { return }
        if let last = lastPosition[ctx.key], position > last, position - last <= 15 {
            StatsStore.shared.record(seconds: position - last, item: ctx.item)
        }
        lastPosition[ctx.key] = position
        let fraction = position / duration
        if fraction >= 0.9 { finishedKeys.insert(ctx.key); onFinished?(ctx.item); clear(ctx.key); return }
        guard fraction >= 0.02 else { return }
        entries[ctx.key] = WatchProgress(key: ctx.key, itemID: ctx.item.id, itemType: ctx.item.type,
                                         name: ctx.item.name, poster: ctx.item.poster,
                                         episodeLabel: ctx.episodeLabel, position: position,
                                         duration: duration, updated: Date())
        persist()
    }

    func clear(_ key: String) {
        if entries.removeValue(forKey: key) != nil { persist() }
    }

    /// Removes every saved position for a title (used by "Remove from Continue watching").
    func clearTitle(_ itemID: String) {
        let keys = entries.values.filter { $0.itemID == itemID }.map(\.key)
        for k in keys { entries.removeValue(forKey: k) }
        if !keys.isEmpty { persist() }
    }

    /// One entry per title (the most recently watched episode), newest first.
    var continueWatching: [WatchProgress] {
        var latest: [String: WatchProgress] = [:]
        for e in entries.values where e.fraction >= 0.02 && e.fraction < 0.9 {
            if let cur = latest[e.itemID], cur.updated >= e.updated { continue }
            latest[e.itemID] = e
        }
        return latest.values.sorted { $0.updated > $1.updated }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(Array(entries.values)) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
