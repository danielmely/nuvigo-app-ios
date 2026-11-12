import Foundation
import Combine

nonisolated extension BrowseCategory.Kind {
    // Shared so the Browse cards and the cover-art loader always agree on which card is which.
    static let trending = BrowseCategory.Kind.keyword(["trend", "featured"])
    static let popular = BrowseCategory.Kind.keyword(["popular", "top"])
}

/// Poster art for the Browse cards, built from the user's own addons, Trakt lists and libraries.
/// "Continue watching" and "Downloads" are filled live in BrowseView from local data.
enum CoverArt {
    nonisolated static let perCard = 4
    /// Each card gets a bigger pool than it shows, so BrowseView can skip covers another card already uses.
    nonisolated static let pool = 16

    /// Swaps small poster sizes for large ones so the cards stay sharp.
    nonisolated static func hiRes(_ url: URL) -> URL {
        var s = url.absoluteString
        if s.contains("image.tmdb.org/t/p/") {
            for size in ["w92", "w154", "w185", "w342", "w500"] { s = s.replacingOccurrences(of: "/t/p/\(size)/", with: "/t/p/w780/") }
        } else if s.contains("metahub.space/poster/") {
            for size in ["small", "medium"] { s = s.replacingOccurrences(of: "/poster/\(size)/", with: "/poster/large/") }
        }
        return URL(string: s) ?? url
    }

    /// The biggest version available, for the full-screen cover view.
    nonisolated static func ultra(_ url: URL) -> URL {
        var s = url.absoluteString
        if s.contains("image.tmdb.org/t/p/") {
            for size in ["w92", "w154", "w185", "w342", "w500", "w780", "w1280"] { s = s.replacingOccurrences(of: "/t/p/\(size)/", with: "/t/p/original/") }
        } else if s.contains("metahub.space/poster/") {
            for size in ["small", "medium"] { s = s.replacingOccurrences(of: "/poster/\(size)/", with: "/poster/large/") }
        }
        return URL(string: s) ?? url
    }

    private static func urls(_ items: [MetaItem]) -> [URL] {
        Array(items.compactMap { $0.poster.flatMap(URL.init(string:)) }.prefix(pool))
    }

    private static func year(_ m: MetaItem) -> Int {
        m.releaseInfo.flatMap { Int($0.prefix(4)) } ?? 0
    }

    private static func named(_ words: [String]) -> (CatalogDecl) -> Bool {
        { cat in
            let hay = (cat.id + " " + (cat.name ?? "")).lowercased()
            return words.contains { hay.contains($0) }
        }
    }

    /// Items from the first browsable catalog that matches.
    private static func firstCatalog(_ addons: [Addon], type: String? = nil,
                                     match: (CatalogDecl) -> Bool) async -> [MetaItem] {
        for addon in addons {
            for cat in addon.manifest.catalogs where cat.isBrowsable && (type == nil || cat.type == type) && match(cat) {
                if let items = try? await AddonClient.catalog(addon, type: cat.type, id: cat.id), !items.isEmpty {
                    return items
                }
            }
        }
        return []
    }

    @MainActor
    static func load(addons: [Addon], trakt: TraktAuth, services: Services) async -> [BrowseCategory.Kind: [URL]] {
        var out: [BrowseCategory.Kind: [URL]] = [:]

        async let trendingItems = firstCatalog(addons, match: named(["trend", "featured"]))
        async let popularItems = firstCatalog(addons, match: named(["popular", "top"]))
        async let anyItems = firstCatalog(addons) { _ in true }
        async let movieItems = firstCatalog(addons, type: "movie") { _ in true }
        async let seriesItems = firstCatalog(addons, type: "series") { _ in true }
        async let freshItems = firstCatalog(addons, type: "movie", match: named(["new", "latest", "recent", "release"]))

        let fallback = await anyItems
        let trendingList = await trendingItems
        let popularList = await popularItems
        out[.trending] = urls(trendingList.isEmpty ? fallback : trendingList)
        out[.popular] = urls(popularList.isEmpty ? fallback : popularList)
        out[.type("movie")] = urls(await movieItems)
        out[.type("series")] = urls(await seriesItems)
        let fresh = await freshItems
        let freshPool = fresh.isEmpty ? await movieItems : fresh
        out[.newReleases] = urls(freshPool.sorted { year($0) > year($1) })

        if trakt.isSignedIn {
            let saved = await WatchlistLoader.load(Array(trakt.watchlist.prefix(8)), addons: addons)
            out[.watchlist] = urls(saved)

            var seen = Set<String>()
            let entries = await trakt.upcoming().filter { seen.insert($0.imdb).inserted }
                .prefix(8).map { TraktListEntry(type: "series", id: $0.imdb) }
            out[.upcoming] = urls(await WatchlistLoader.load(Array(entries), addons: addons))
        }

        for ref in services.folders {
            if let src = services.librarySources.first(where: { $0.idPrefix == ref.prefix }) {
                out[.library(ref.id)] = urls(await src.items(in: ref.folder))
            }
        }
        return out
    }
}
