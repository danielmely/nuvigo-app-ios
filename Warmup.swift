import Foundation
import Combine

/// Start-up helpers: fetch things ahead of time so screens open with everything already in hand.
enum Warmup {
    /// First page of every catalog that doesn't need a search or genre (up to 30), all at once, a few at a time.
    static func catalogs(_ addons: [Addon]) async -> [MetaItem] {
        var targets: [(Addon, CatalogDecl)] = []
        for a in addons { for c in a.manifest.catalogs where c.isBrowsable { targets.append((a, c)) } }
        targets = Array(targets.prefix(30))
        var out: [MetaItem] = []
        await withTaskGroup(of: [MetaItem].self) { group in
            var it = targets.makeIterator()
            func next() { if let (a, c) = it.next() { group.addTask { (try? await AddonClient.catalog(a, type: c.type, id: c.id)) ?? [] } } }
            for _ in 0..<5 { next() }
            while let items = await group.next() {
                out += items
                if Task.isCancelled { group.cancelAll(); break }
                next()
            }
        }
        return out
    }

    /// Full OMDb details (IMDb score, Rotten Tomatoes, plot, cast) for the title page.
    static func ratings(_ items: [MetaItem]) async {
        guard Ratings.isConfigured else { return }
        let ids = items.map(\.id).filter { $0.hasPrefix("tt") }
        await withTaskGroup(of: Void.self) { group in
            var it = ids.makeIterator()
            func next() { if let id = it.next() { group.addTask { _ = await Ratings.load(imdbID: id) } } }
            for _ in 0..<6 { next() }
            while await group.next() != nil { if Task.isCancelled { group.cancelAll(); break }; next() }
        }
    }

    /// Metadata (backgrounds, episode lists) from the first addon that serves it. Saved to disk by the client.
    static func details(_ items: [MetaItem], addons: [Addon]) async -> [MetaItem] {
        var out: [MetaItem] = []
        await withTaskGroup(of: MetaItem?.self) { group in
            var it = items.makeIterator()
            func next() {
                guard let item = it.next() else { return }
                group.addTask {
                    for a in addons where a.supports("meta", type: item.type, id: item.id) {
                        if let m = try? await AddonClient.meta(a, type: item.type, id: item.id) { return m }
                    }
                    return nil
                }
            }
            for _ in 0..<6 { next() }
            while let m = await group.next() {
                if let m { out.append(m) }
                if Task.isCancelled { group.cancelAll(); break }
                next()
            }
        }
        return out
    }

    /// Stream lists for the first few movies, kept in memory for ten minutes.
    static func streams(_ items: [MetaItem], addons: [Addon]) async {
        await withTaskGroup(of: Void.self) { group in
            for item in items {
                for a in addons where a.supports("stream", type: item.type, id: item.id) {
                    group.addTask { _ = try? await AddonClient.streams(a, type: item.type, id: item.id) }
                }
            }
            for await _ in group { if Task.isCancelled { group.cancelAll(); break } }
        }
    }
}
