import Foundation
import Combine
@preconcurrency import CoreSpotlight
import UniformTypeIdentifiers

/// Lets you find your in-progress and watched titles from the iPhone's own search.
/// Only titles and names are indexed. Nothing is indexed in Private mode.
enum SpotlightIndexer {
    static let prefix = "nuvigo.title."
    private static let domain = "com.nuvigo.titles"

    @MainActor
    static func reindex(progress: ProgressStore, watched: WatchedStore) {
        let index = CSSearchableIndex.default()
        // Collect everything here on the main actor first, then replace what's indexed.
        var seen = Set<String>()
        var items: [CSSearchableItem] = []

        func add(id: String, type: String, name: String, detail: String) {
            guard !name.isEmpty, seen.insert(type + id).inserted else { return }
            let attrs = CSSearchableItemAttributeSet(contentType: .content)
            attrs.title = name
            attrs.contentDescription = detail
            let item = CSSearchableItem(uniqueIdentifier: "\(prefix)\(type).\(id)", domainIdentifier: domain, attributeSet: attrs)
            item.expirationDate = Date().addingTimeInterval(60 * 86_400)
            items.append(item)
        }
        if !PrivateMode.isOn {
            for e in progress.continueWatching.prefix(40) {
                add(id: e.itemID, type: e.itemType, name: e.name, detail: "Continue watching" + (e.episodeLabel.map { " · \($0)" } ?? ""))
            }
            for w in watched.items.prefix(200) {
                add(id: w.id, type: w.type, name: w.name, detail: "Watched in NuviGo")
            }
        }
        let toIndex = items
        index.deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            if !toIndex.isEmpty { index.indexSearchableItems(toIndex) { _ in } }
        }
    }

    static func removeAll() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in }
    }
}
