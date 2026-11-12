import SwiftUI
import Combine

/// The maturity classes a person can hide. TV ratings are folded into the nearest movie class:
/// TV-Y, TV-Y7 and TV-G count as G, TV-PG as PG, TV-14 as PG-13 and TV-MA as R.
enum RatingClass: String, CaseIterable, Identifiable {
    case g = "G", pg = "PG", pg13 = "PG-13", r = "R", nc17 = "NC-17", unrated = "Unrated"
    var id: String { rawValue }

    static func classify(_ rated: String?) -> RatingClass {
        switch (rated ?? "").uppercased().trimmingCharacters(in: .whitespaces) {
        case "G", "TV-Y", "TV-Y7", "TV-Y7-FV", "TV-G", "APPROVED", "PASSED": return .g
        case "PG", "TV-PG", "GP", "M": return .pg
        case "PG-13", "TV-14": return .pg13
        case "R", "TV-MA": return .r
        case "NC-17", "X": return .nc17
        default: return .unrated   // "Not Rated", "Unrated", "N/A" and anything unknown
        }
    }
}

/// Hides titles by maturity rating everywhere they show up. Ratings come from OMDb and are remembered
/// on the device, so each title is looked up once. A title whose rating is not known yet stays visible
/// until the lookup finishes, then disappears. Without an OMDb key nothing can be classified.
@MainActor
final class ContentFilter: ObservableObject {
    static let shared = ContentFilter()

    @Published private(set) var hidden: Set<String> = []
    @Published private(set) var classes: [String: String] = [:]   // IMDb id -> RatingClass raw value

    private var posterIDs: [String: String] = [:]                  // poster URL -> IMDb id
    private var seen: Set<String> = []
    private var working = false
    private let hiddenKey = "hiddenRatings"
    private let classesKey = "ratingClasses"

    var isActive: Bool { !hidden.isEmpty }

    private init() {
        classes = (UserDefaults.standard.dictionary(forKey: classesKey) as? [String: String]) ?? [:]
        reloadHidden()
        // Picks up changes made by an account sync or a reset.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reloadHidden() }
        }
    }

    private func reloadHidden() {
        let raw = UserDefaults.standard.string(forKey: hiddenKey) ?? ""
        var set = Set(raw.split(separator: "|").map(String.init))
        if ProfileStore.activeIsKids { set.formUnion(ProfileStore.kidsHidden) }
        guard set != hidden else { return }
        hidden = set
        if isActive { fetchMissing() }
    }

    /// Called when the active profile changes (a kids profile hides more).
    func profileChanged() { reloadHidden() }

    func clearCache() {
        classes = [:]; seen = []
        UserDefaults.standard.removeObject(forKey: classesKey)
        if isActive { fetchMissing() }
    }

    /// What the Hide by rating switches say, ignoring the kids profile lock.
    func isHiddenClass(_ c: RatingClass) -> Bool { hidden.contains(c.rawValue) }

    func setHidden(_ c: RatingClass, _ on: Bool) {
        var set = hidden
        if on { set.insert(c.rawValue) } else { set.remove(c.rawValue) }
        UserDefaults.standard.set(RatingClass.allCases.map(\.rawValue).filter(set.contains).joined(separator: "|"), forKey: hiddenKey)
        reloadHidden()
    }

    // MARK: Checks

    private func baseID(_ id: String) -> String { String(id.split(separator: ":").first ?? Substring(id)) }

    func isHidden(id: String) -> Bool {
        guard isActive else { return false }
        let b = baseID(id)
        guard b.hasPrefix("tt") else { return false }
        guard let c = classes[b] else { return false }
        return hidden.contains(c)
    }

    func isHidden(_ item: MetaItem) -> Bool { isHidden(id: item.id) }

    func isHiddenPoster(_ url: URL) -> Bool {
        guard isActive, let id = posterIDs[url.absoluteString] else { return false }
        return isHidden(id: id)
    }

    func visible(_ items: [MetaItem]) -> [MetaItem] { isActive ? items.filter { !isHidden($0) } : items }

    // MARK: Lookups

    /// Called with every list of titles the app loads, so their ratings are ready before they are shown.
    func note(_ items: [MetaItem]) {
        for i in items {
            if let p = i.poster { posterIDs[p] = baseID(i.id) }
            if i.id.hasPrefix("tt") { seen.insert(baseID(i.id)) }
        }
        if isActive { fetchMissing() }
    }

    func note(ids: [String]) {
        for id in ids where id.hasPrefix("tt") { seen.insert(baseID(id)) }
        if isActive { fetchMissing() }
    }

    /// Looks up ratings now and returns when done (used by the start-up screen).
    func classifyNow(_ ids: [String]) async {
        guard Ratings.isConfigured else { return }
        let wanted = Array(Set(ids.filter { $0.hasPrefix("tt") }.map(baseID))).filter { classes[$0] == nil }
        guard !wanted.isEmpty else { return }
        for id in wanted { seen.insert(id) }
        var found: [String: String] = [:]
        await withTaskGroup(of: (String, String?, Bool).self) { group in
            var it = wanted.makeIterator()
            func next() { if let id = it.next() { group.addTask { let r = await Ratings.load(imdbID: id); return (id, r?.rated, r != nil) } } }
            for _ in 0..<6 { next() }
            while let (id, rated, ok) = await group.next() {
                if let r = rated { found[id] = RatingClass.classify(r).rawValue }
                else if ok { found[id] = RatingClass.unrated.rawValue }
                if Task.isCancelled { group.cancelAll(); break }
                next()
            }
        }
        if !found.isEmpty {
            classes.merge(found) { $1 }
            UserDefaults.standard.set(classes, forKey: classesKey)
        }
    }

    private func fetchMissing() {
        guard Ratings.isConfigured, !working else { return }
        let pending = Array(seen.filter { classes[$0] == nil }.prefix(60))
        guard !pending.isEmpty else { return }
        working = true
        Task {
            var found: [String: String] = [:]
            await withTaskGroup(of: (String, String?).self) { group in
                var it = pending.makeIterator()
                var running = 0
                func next() { if let id = it.next() { group.addTask { (id, await Ratings.load(imdbID: id)?.rated) }; running += 1 } }
                for _ in 0..<4 { next() }
                while running > 0, let (id, rated) = await group.next() {
                    running -= 1
                    if let r = rated { found[id] = RatingClass.classify(r).rawValue }
                    else if await Ratings.load(imdbID: id) != nil { found[id] = RatingClass.unrated.rawValue }
                    next()
                }
            }
            working = false
            if !found.isEmpty {
                classes.merge(found) { $1 }
                UserDefaults.standard.set(classes, forKey: classesKey)
            }
            if isActive, seen.contains(where: { classes[$0] == nil }), !found.isEmpty { fetchMissing() }
        }
    }
}
