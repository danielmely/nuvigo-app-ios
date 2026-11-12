import SwiftUI
import Combine

nonisolated struct BrowseCategory: Identifiable, Hashable {
    nonisolated enum Kind: Hashable {
        case continueWatching, watchlist, upcoming, downloads, watched
        case type(String)     // "movie" or "series"
        case genre(String)
        case newReleases          // recent movies
        case keyword([String])   // catalogs whose id or name contains any of these
        case library(String)  // LibraryFolderRef.id
    }

    let kind: Kind
    let title: String
    let symbol: String
    let tint: Color
    var subtitle: String? = nil
    var emoji: String? = nil   // shown instead of the symbol when set

    var id: String { title }
}

struct BrowseView: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @EnvironmentObject var store: AddonStore
    @EnvironmentObject var trakt: TraktAuth
    @EnvironmentObject var progress: ProgressStore
    @EnvironmentObject var services: Services
    @EnvironmentObject var network: NetworkMonitor
    @EnvironmentObject var downloads: DownloadManager
    @EnvironmentObject var preload: Preloader
    @EnvironmentObject var watched: WatchedStore
    @EnvironmentObject var account: NuviAccount
    @EnvironmentObject var filter: ContentFilter

    @Environment(\.scenePhase) private var scenePhase
    @State private var homeRows: [CatalogRow] = []
    @State private var lastRefresh = Date()
    @State private var pullPeak: CGFloat = 0
    @State private var pullY: CGFloat = 0
    @State private var remoteArt: [BrowseCategory.Kind: [URL]] = [:]
    /// Your own card order: card titles joined by "|". Syncs with your account. Empty means the default order.
    @AppStorage("dashboardOrder") private var orderRaw = ""

    private static let genreTints: [Color] = [.blue, .green, .purple, .red, .mint, .cyan, .brown, .indigo]

    private var genres: [String] {
        Array(Set(store.addons.flatMap { $0.manifest.catalogs.flatMap { $0.genreOptions } })).sorted()
    }

    /// The six cards that fill the first screen, in this order.
    private var primaryCategories: [BrowseCategory] {
        let resume = progress.continueWatching.count
        return [
            .init(kind: .continueWatching, title: "Continue watching", symbol: "play.circle.fill", tint: .indigo,
                  subtitle: resume > 0 ? "\(resume) in progress" : nil, emoji: "▶️"),
            .init(kind: .popular, title: "Popular", symbol: "star.fill", tint: .yellow, emoji: "⭐️"),
            .init(kind: .type("movie"), title: "Movies", symbol: "film.fill", tint: .red, emoji: "🎬"),
            .init(kind: .type("series"), title: "Series", symbol: "tv.fill", tint: .pink, emoji: "📺"),
            .init(kind: .trending, title: "Trending", symbol: "flame.fill", tint: .orange, emoji: "🔥"),
            .init(kind: .type("anime"), title: "Anime", symbol: "sparkles.tv.fill", tint: .purple, emoji: "🎌")
        ]
    }

    /// Everything else, shown below the six cards.
    private var moreCategories: [BrowseCategory] {
        var list: [BrowseCategory] = []
        list.append(.init(kind: .newReleases, title: "New releases", symbol: "sparkles", tint: .mint,
                          subtitle: "Recent movies", emoji: "✨"))
        if trakt.isSignedIn {
            list.append(.init(kind: .upcoming, title: "Coming up", symbol: "calendar", tint: .red,
                              subtitle: "New episodes", emoji: "📆"))
        }
        let saved = trakt.watchlist.count
        list.append(.init(kind: .watchlist, title: "Watchlist", symbol: "bookmark.fill", tint: .teal,
                          subtitle: saved > 0 ? "\(saved) saved" : nil, emoji: "🍿"))
        list.append(.init(kind: .watched, title: "Already watched", symbol: "checkmark.circle.fill", tint: .teal,
                          subtitle: watched.items.isEmpty ? "Rate and get picks" : "\(watched.items.count) titles", emoji: "✅"))
        if !downloads.entries.isEmpty {
            let sub = downloads.activeCount > 0 ? "\(downloads.activeCount) downloading"
                                                : "\(downloads.doneCount) saved · \(DownloadManager.sizeText(downloads.totalBytes))"
            list.append(.init(kind: .downloads, title: "Downloads", symbol: "arrow.down.circle.fill",
                              tint: .green, subtitle: sub, emoji: "📲"))
        }
        for ref in services.folders {
            list.append(.init(kind: .library(ref.id), title: ref.title,
                              symbol: ref.prefix == "jf:" ? "externaldrive.fill" : "server.rack",
                              tint: ref.prefix == "jf:" ? .purple : .orange, subtitle: "Your server",
                              emoji: "📀"))
        }
        for (i, g) in genres.filter({ $0.lowercased() != "anime" }).enumerated() {
            list.append(.init(kind: .genre(g), title: g, symbol: "tag.fill",
                              tint: Self.genreTints[i % Self.genreTints.count]))
        }
        return list
    }


    /// Every card in the order you chose (new cards go at the end, in their default order).
    private var orderedCategories: [BrowseCategory] {
        let base = primaryCategories + moreCategories
        let saved = orderRaw.split(separator: "|").map(String.init)
        let rank = Dictionary(saved.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return base.enumerated()
            .sorted { (rank[$0.element.id] ?? 10_000 + $0.offset) < (rank[$1.element.id] ?? 10_000 + $1.offset) }
            .map(\.element)
    }

    /// The first six cards fill the first screen; the rest sit below the divider.
    private var topCategories: [BrowseCategory] { Array(orderedCategories.prefix(max(primaryCategories.count, 1))) }
    private var restCategories: [BrowseCategory] { Array(orderedCategories.dropFirst(max(primaryCategories.count, 1))) }

    /// Press and hold a card, then drop it on another card to put it in that spot.
    private func moveCard(_ dragged: String, onto target: String) {
        var ids = orderedCategories.map(\.id)
        guard dragged != target, let from = ids.firstIndex(of: dragged), let to = ids.firstIndex(of: target) else { return }
        let item = ids.remove(at: from)
        ids.insert(item, at: to)
        withAnimation(.easeInOut(duration: 0.2)) { orderRaw = ids.joined(separator: "|") }
    }

    /// Reloads the home rows and the card artwork together.
    private func refreshAll() async {
        lastRefresh = Date()
        async let rows = HomeRows.load(store.addons)
        async let art = CoverArt.load(addons: store.addons, trakt: trakt, services: services)
        homeRows = await rows
        remoteArt = await art
    }

    private func rawPosters(for category: BrowseCategory) -> [URL] {
        switch category.kind {
        case .continueWatching:
            return progress.continueWatching.filter { !filter.isHidden(id: $0.itemID) }.compactMap { $0.poster.flatMap(URL.init(string:)) }
        case .downloads:
            return downloads.entries.filter { !filter.isHidden(id: $0.itemID) }.compactMap { $0.metaItem.poster.flatMap(URL.init(string:)) }
        case .watched:
            return watched.items.filter { !filter.isHidden(id: $0.id) }.compactMap { $0.poster.flatMap(URL.init(string:)) }
        default:
            return (remoteArt[category.kind] ?? []).filter { !filter.isHiddenPoster($0) }
        }
    }

    /// Every cover appears on one card only: cards are filled in order and skip posters already shown.
    private var cardArt: [String: [URL]] {
        var used = Set<URL>()
        var out: [String: [URL]] = [:]
        for cat in orderedCategories {
            var mine: [URL] = []
            for u in rawPosters(for: cat).map(CoverArt.hiRes) where !used.contains(u) {
                mine.append(u)
                used.insert(u)
                if mine.count == CoverArt.perCard { break }
            }
            out[cat.id] = mine
        }
        return out
    }

    private static func isStorage(_ c: BrowseCategory) -> Bool {
        switch c.kind {
        case .downloads, .library: return true
        default: return false
        }
    }

    /// Two columns on iPhone, four on iPad and other wide windows.
    private var columnCount: Int { hSize == .regular ? 4 : 2 }
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: Self.gridSpacing), count: columnCount) }

    private func moreGrid(_ cats: [BrowseCategory], art: [String: [URL]]) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(cats) { cat in
                NavigationLink(value: cat) { CategoryCard(category: cat, posters: art[cat.id] ?? []) }
                    .buttonStyle(.plain)
                    .draggable(cat.id)
                    .dropDestination(for: String.self) { ids, _ in
                        guard let id = ids.first else { return false }
                        moveCard(id, onto: cat.id); return true
                    }
            }
        }
        .padding(.horizontal)
    }

    private static let gridSpacing: CGFloat = 12
    /// How far the content must stretch past the top before a release refreshes.
    private static var pullNeeded: CGFloat { UIScreen.main.bounds.height * 0.29 }
    private static let minCardHeight: CGFloat = 144

    /// The category cards share one full screen of height; extra categories push it taller.
    private var categoryGrid: some View {
        let art = cardArt
        let rows = max(1, (topCategories.count + columnCount - 1) / columnCount)
        let minTotal = CGFloat(rows) * Self.minCardHeight + CGFloat(rows - 1) * Self.gridSpacing
        return GeometryReader { geo in
            let cardH = max(Self.minCardHeight,
                            (geo.size.height - CGFloat(rows - 1) * Self.gridSpacing) / CGFloat(rows))
            LazyVGrid(columns: columns, spacing: Self.gridSpacing) {
                ForEach(topCategories) { cat in
                    NavigationLink(value: cat) { CategoryCard(category: cat, posters: art[cat.id] ?? [], height: cardH) }
                        .buttonStyle(.plain)
                        .draggable(cat.id)
                        .dropDestination(for: String.self) { ids, _ in
                            guard let id = ids.first else { return false }
                            moveCard(id, onto: cat.id); return true
                        }
                }
            }
            .padding(.horizontal)
        }
        // Leaves room at the bottom of the first screen for the top sliver (about 5%) of the next row, as a scroll hint.
        .containerRelativeFrame(.vertical) { length, _ in max(minTotal, length - 94) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                // Measures how far the content is pulled down past the top.
                Color.clear.frame(height: 0)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: PullOffsetKey.self, value: g.frame(in: .named("pull")).minY)
                    })
                if !network.isOnline {
                    Label("You're offline. Showing saved titles.", systemImage: "wifi.slash")
                        .font(.footnote)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal)
                }
                if store.addons.isEmpty && services.folders.isEmpty && !store.isLoading {
                    ContentUnavailableView("No addons installed",
                                           systemImage: "puzzlepiece.extension",
                                           description: Text("Add one in the Addons tab, or connect Jellyfin or Plex in Account."))
                        .padding(.top, 80)
                } else {
                    let art = cardArt
                    VStack(alignment: .leading, spacing: 22) {
                        categoryGrid
                        // Thin lines separate the groups: main cards | extras | downloads and libraries.
                        let extras = restCategories.filter { !Self.isStorage($0) }
                        let storage = restCategories.filter { Self.isStorage($0) }
                        if !extras.isEmpty {
                            Rectangle().fill(Color.secondary.opacity(0.55)).frame(height: 1).padding(.horizontal)
                            moreGrid(extras, art: art)
                        }
                        if !storage.isEmpty {
                            Rectangle().fill(Color.secondary.opacity(0.55)).frame(height: 1).padding(.horizontal)
                            moreGrid(storage, art: art)
                        }
                        let resume = progress.continueWatching.filter { !filter.isHidden(id: $0.itemID) }
                        if !resume.isEmpty {
                            PosterRow(title: "Continue watching") {
                                ForEach(resume) { ContinueCard(entry: $0).frame(width: 120) }
                            }
                        }
                        ForEach(homeRows) { row in
                            let shown = filter.visible(row.items)
                            if !shown.isEmpty {
                                PosterRow(title: row.title) {
                                    ForEach(shown) { PosterLink(item: $0).frame(width: 120) }
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: BrowseCategory.self) { CategoryView(category: $0) }
            .navigationDestination(for: MetaItem.self) { DetailView(item: $0) }
            .task(id: "\(store.addons.map(\.id).joined(separator: ","))|\(trakt.watchlist.count)|\(trakt.isSignedIn)|\(services.folders.map(\.id).joined(separator: ","))|\(preload.done)") {
                guard preload.done else { return }   // the start-up screen is still loading everything
                filter.note(ids: progress.continueWatching.map(\.itemID) + downloads.entries.map(\.itemID) + watched.items.map(\.id))
                filter.note(preload.homeRows.flatMap(\.items))
                if homeRows.isEmpty && remoteArt.isEmpty && !(preload.homeRows.isEmpty && preload.art.isEmpty) {
                    homeRows = preload.homeRows       // already fetched during start-up: show it right away
                    remoteArt = preload.art
                    lastRefresh = Date()
                    return
                }
                await refreshAll()
            }
            .coordinateSpace(name: "pull")
            .overlay(alignment: .top) {
                // Appears as you pull down, so people know to keep going.
                if pullY > 8 && !preload.refreshing {
                    VStack(spacing: 4) {
                        // Your logo is revealed clockwise as you pull; fully revealed means it will refresh.
                        let reveal = min(1, pullY / Self.pullNeeded)
                        ZStack {
                            if let mark = LogoData.mark {
                                Image(uiImage: mark).resizable().scaledToFit().opacity(0.16)
                                Image(uiImage: mark).resizable().scaledToFit()
                                    .mask {
                                        // A wedge that sweeps clockwise from the top.
                                        Circle()
                                            .trim(from: 0, to: reveal)
                                            .stroke(Color.black, style: StrokeStyle(lineWidth: 44))
                                            .frame(width: 22, height: 22)
                                            .rotationEffect(.degrees(-90))
                                    }
                            }
                        }
                        .frame(width: 44, height: 44)
                        Text("Keep pulling to refresh")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 6)
                    .opacity(min(1, Double(pullY) / 60))
                    .allowsHitTesting(false)
                }
            }
            .onPreferenceChange(PullOffsetKey.self) { y in
                // The refresh fires when you let go after pulling down far enough: about three quarters
                // of the screen of finger travel (the scroll view resists, so that is roughly 29% of the
                // screen of stretch).
                let needed = Self.pullNeeded
                pullY = y
                if y > pullPeak { pullPeak = y }
                if y <= 1 {
                    let pulled = pullPeak
                    pullPeak = 0
                    if pulled >= needed, !preload.refreshing {
                        // The loading screen returns with just "Refreshing…" under the bar.
                        Task {
                            await preload.refresh(store: store, trakt: trakt, services: services, account: account, progress: progress)
                            homeRows = preload.homeRows
                            remoteArt = preload.art
                            lastRefresh = Date()
                        }
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // Coming back to the app after 5+ minutes: refresh quietly.
                guard phase == .active, Date().timeIntervalSince(lastRefresh) > 300 else { return }
                Task { await refreshAll() }
            }
        }
    }
}

private struct PullOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct CategoryCard: View {
    let category: BrowseCategory
    var posters: [URL] = []
    var height: CGFloat = 170

    private static let labelHeight: CGFloat = 40

    var body: some View {
        let hasCover = !posters.isEmpty
        VStack(alignment: .leading, spacing: 6) {
            // Cover art only; the words and icon sit underneath.
            ZStack(alignment: .topLeading) {
                if hasCover {
                    PosterMosaic(urls: posters)
                    Color.black.opacity(0.20)          // 20% tint: the art stays 80% visible
                } else {
                    category.tint.opacity(0.15)        // nothing to show yet (signed out, empty list, offline)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Title and subtitle on the left, the category icon to their right.
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(LocalizedStringKey(category.title.capitalized)).font(.headline).foregroundStyle(.primary).lineLimit(1)
                    Text(LocalizedStringKey((category.subtitle ?? " ").capitalized)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let emoji = category.emoji {
                    Text(emoji).font(.title2)
                } else {
                    Image(systemName: category.symbol).font(.title3).foregroundStyle(category.tint)
                }
            }
            .frame(height: Self.labelHeight - 4, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(category.title.capitalized + (category.subtitle.map { ", " + $0 } ?? ""))
        .accessibilityAddTraits(.isButton)
    }
}

/// 1 poster fills the card, 2 or 3 sit side by side, 4 make a 2 x 2 grid.
private struct PosterMosaic: View {
    let urls: [URL]

    var body: some View {
        GeometryReader { geo in
            let big = urls.count >= 4
            let cols = big ? 2 : max(urls.count, 1)
            let rows = big ? 2 : 1
            let shown = Array(urls.prefix(cols * rows))
            let w = geo.size.width / CGFloat(cols)
            let h = geo.size.height / CGFloat(rows)
            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<cols, id: \.self) { c in
                            let i = r * cols + c
                            AsyncImage(url: i < shown.count ? shown[i] : nil) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                Color.gray.opacity(0.3)
                            }
                            .frame(width: w, height: h)
                            .clipped()
                        }
                    }
                }
            }
        }
    }
}

/// A thin black outline around text, drawn with four tight hard shadows, so white words stay readable on photos.
private extension View {
    @ViewBuilder
    func blackOutline(_ on: Bool, width: CGFloat = 0.75) -> some View {
        if on {
            self
                .shadow(color: .black, radius: 0, x: width, y: 0)
                .shadow(color: .black, radius: 0, x: -width, y: 0)
                .shadow(color: .black, radius: 0, x: 0, y: width)
                .shadow(color: .black, radius: 0, x: 0, y: -width)
        } else {
            self
        }
    }
}
