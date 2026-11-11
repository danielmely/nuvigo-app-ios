import SwiftUI

/// Sort and filter choices for a category screen.
struct ListOptions: Equatable {
    enum Sort: String, CaseIterable {
        case standard = "Default"
        case name = "A to Z"
        case newest = "Newest first"
        case oldest = "Oldest first"
    }

    var sort: Sort = .standard
    var hideWatched = false
    var type: String? = nil     // nil = movies and series

    var isActive: Bool { sort != .standard || hideWatched || type != nil }
}

/// What opens when you tap a category card on Browse.
struct CategoryView: View {
    let category: BrowseCategory

    @EnvironmentObject var store: AddonStore
    @EnvironmentObject var trakt: TraktAuth
    @EnvironmentObject var progress: ProgressStore
    @EnvironmentObject var subs: SubscriptionStore
    @EnvironmentObject var services: Services
    @EnvironmentObject var downloads: DownloadManager
    @EnvironmentObject var filter: ContentFilter

    @State private var rows: [CatalogRow] = []
    @State private var watchlistItems: [MetaItem] = []
    @State private var libraryItems: [MetaItem] = []
    @State private var upcoming: [TraktUpcoming] = []
    @State private var upcomingItems: [String: MetaItem] = [:]
    @State private var loading = false
    @State private var options = ListOptions()
    @State private var playing: PlayItem?
    @State private var tappedDownload: DownloadEntry?
    @State private var pendingDelete: DownloadEntry?
    @State private var infoItem: MetaItem?
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastLoad = Date()

    private let grid = [GridItem(.adaptive(minimum: 100), spacing: 12)]

    private var reloadKey: String {
        "\(store.addons.map(\.id).joined(separator: ","))|\(trakt.watchlist.map(\.id).joined(separator: ","))|\(services.folders.map(\.id).joined(separator: ","))"
    }

    var body: some View {
        ScrollView {
            switch category.kind {
            case .continueWatching:
                let list = progress.continueWatching.filter { !filter.isHidden(id: $0.itemID) }
                if list.isEmpty { empty("Nothing in progress. Start something and it shows up here.") }
                else {
                    LazyVGrid(columns: grid, spacing: 16) { ForEach(list) { ContinueCard(entry: $0) } }
                        .padding()
                }
            case .watchlist:
                let list = apply(watchlistItems)
                if loading && watchlistItems.isEmpty { ProgressView().padding(.top, 60) }
                else if !trakt.isSignedIn { empty("Sign in to Trakt in the Account tab to use your watchlist.") }
                else if watchlistItems.isEmpty { empty("Your Trakt watchlist is empty. Use the bookmark on a title to add it.") }
                else if list.isEmpty { empty("Nothing matches these filters.") }
                else {
                    LazyVGrid(columns: grid, spacing: 16) { ForEach(list) { PosterLink(item: $0) } }
                        .padding()
                }
            case .upcoming:
                upcomingList
            case .downloads:
                downloadsList
            case .watched:
                WatchedContent()
            case .library:
                let list = apply(libraryItems)
                if loading && libraryItems.isEmpty { ProgressView().padding(.top, 60) }
                else if libraryItems.isEmpty { empty("Nothing found in this library, or the server couldn't be reached.") }
                else if list.isEmpty { empty("Nothing matches these filters.") }
                else {
                    LazyVGrid(columns: grid, spacing: 16) { ForEach(list) { PosterLink(item: $0) } }
                        .padding()
                }
            case .type, .genre, .keyword, .newReleases:
                if loading && rows.isEmpty { ProgressView().padding(.top, 60) }
                else if rows.isEmpty { empty("No titles found in this category.") }
                else {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(rows) { row in
                            let items = apply(row.items)
                            if !items.isEmpty {
                                PosterRow(title: row.title) {
                                    ForEach(items) { PosterLink(item: $0).frame(width: 120) }
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
        .navigationTitle(category.kind == .downloads ? "" : category.title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(tappedDownload?.title ?? "", isPresented: Binding(get: { tappedDownload != nil },
                                                                              set: { if !$0 { tappedDownload = nil } }),
                            titleVisibility: .visible, presenting: tappedDownload) { d in
            if d.state == .done { Button("Watch now") { playDownload(d) } }
            Button("View full info") { infoItem = d.metaItem }
            Button("Cancel", role: .cancel) {}
        }
        .navigationDestination(item: $infoItem) { DetailView(item: $0) }
        .alert(pendingDelete?.state == .downloading ? "Cancel this download?" : "Delete this download?",
               isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
               presenting: pendingDelete) { d in
            Button(d.state == .downloading ? "Cancel download" : "Delete", role: .destructive) { downloads.remove(d.id) }
            Button("Keep", role: .cancel) {}
        } message: { d in
            Text(d.state == .downloading ? "\(d.title) will stop downloading."
                                         : "\(d.title) will be removed from this device. You can download it again later.")
        }
        .toolbar { optionsMenu }
        .task(id: reloadKey) { await load() }
        .refreshable { await load() }
        .onChange(of: scenePhase) { _, phase in
            // Coming back to the app after 5+ minutes: reload this list quietly.
            guard phase == .active, Date().timeIntervalSince(lastLoad) > 300 else { return }
            Task { await load() }
        }
        .fullScreenCover(item: $playing) { p in
            PlayerView(item: p)
                .environmentObject(trakt)
                .environmentObject(progress)
                .environmentObject(services)
        }
    }

    // MARK: Downloads

    @ViewBuilder
    private var downloadsList: some View {
        let list = downloads.entries.sorted { $0.added > $1.added }.filter { !filter.isHidden(id: $0.itemID) }
        if list.isEmpty {
            Text("Nothing downloaded yet. Tap the download button next to a stream to save it for offline.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity)
                .containerRelativeFrame(.vertical, alignment: .center)
        }
        else {
            LazyVGrid(columns: grid, spacing: 16) {
                ForEach(list) { d in
                    DownloadTile(entry: d, onTap: { tappedDownload = d }, onDelete: { pendingDelete = d })
                }
            }
            .padding()
        }
    }

    private func playDownload(_ d: DownloadEntry) {
        guard subs.allow() else { return }
        guard let url = downloads.localURL(for: d.id) else { return }
        let ctx = PlaybackContext(key: d.id, item: d.metaItem, episodeLabel: d.episodeLabel, nextEpisode: nil)
        playing = PlayItem(url: url, context: ctx, subtitles: [], streamName: "Downloaded",
                           startAt: progress.resumePosition(for: d.id))
    }

    // MARK: Sort and filter

    private var showsOptions: Bool {
        switch category.kind {
        case .continueWatching, .upcoming, .downloads, .watched: return false
        default: return true
        }
    }

    private var showsTypeFilter: Bool {
        switch category.kind {
        case .watchlist, .library: return true
        default: return false
        }
    }

    @ToolbarContentBuilder
    private var optionsMenu: some ToolbarContent {
        if showsOptions {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $options.sort) {
                        ForEach(ListOptions.Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    if trakt.isSignedIn {
                        Toggle("Hide watched movies", isOn: $options.hideWatched)
                    }
                    if showsTypeFilter {
                        Picker("Show", selection: $options.type) {
                            Text("Movies and series").tag(String?.none)
                            Text("Movies only").tag(String?.some("movie"))
                            Text("Series only").tag(String?.some("series"))
                        }
                    }
                } label: {
                    Image(systemName: options.isActive ? "line.3.horizontal.decrease.circle.fill"
                                                       : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Sort and filter")
            }
        }
    }

    private func year(_ item: MetaItem) -> Int? {
        item.releaseInfo.flatMap { Int($0.prefix(4)) }
    }

    private func apply(_ items: [MetaItem]) -> [MetaItem] {
        var list = filter.visible(items)
        if options.hideWatched { list = list.filter { !($0.type == "movie" && trakt.isWatched($0.id)) } }
        if let t = options.type { list = list.filter { $0.type == t } }
        switch options.sort {
        case .standard: break
        case .name: list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .newest: list.sort { (year($0) ?? 0) > (year($1) ?? 0) }
        case .oldest: list.sort { (year($0) ?? 9999) < (year($1) ?? 9999) }
        }
        return list
    }

    // MARK: Coming up

    private var upcomingGroups: [(day: Date, items: [TraktUpcoming])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: upcoming) { cal.startOfDay(for: $0.airs) }
        return grouped.keys.sorted().map { (day: $0, items: grouped[$0] ?? []) }
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInTomorrow(day) { return "Tomorrow" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month().day())
    }

    @ViewBuilder
    private var upcomingList: some View {
        if loading && upcoming.isEmpty { ProgressView().padding(.top, 60) }
        else if upcoming.isEmpty { empty("No new episodes coming up for the shows you follow on Trakt.") }
        else {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(upcomingGroups, id: \.day) { group in
                    Text(dayTitle(group.day)).font(.headline).padding(.top, 10).padding(.horizontal)
                    ForEach(group.items) { u in
                        NavigationLink(value: upcomingItem(u)) {
                            HStack(spacing: 12) {
                                AsyncImage(url: upcomingItem(u).poster.flatMap(URL.init(string:))) { $0.resizable().scaledToFill() }
                                    placeholder: { Rectangle().fill(.quaternary) }
                                    .frame(width: 44, height: 66)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(u.showTitle).foregroundStyle(.primary)
                                    Text(SpoilerGuard.hide(u.label)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom)
        }
    }

    private func upcomingItem(_ u: TraktUpcoming) -> MetaItem {
        upcomingItems[u.imdb] ?? MetaItem(id: u.imdb, type: "series", name: u.showTitle, poster: nil, background: nil,
                                          description: nil, releaseInfo: nil, runtime: nil, genres: nil, videos: nil)
    }

    // MARK: Loading

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 60)
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity)
    }

    private func load() async {
        loading = true
        lastLoad = Date()
        defer { loading = false }
        switch category.kind {
        case .continueWatching, .downloads, .watched:
            break
        case .watchlist:
            watchlistItems = await WatchlistLoader.load(trakt.watchlist, addons: store.addons)
            filter.note(watchlistItems)
        case .upcoming:
            upcoming = await trakt.upcoming()
            var seen = Set<String>()
            let entries = upcoming.filter { seen.insert($0.imdb).inserted }
                .map { TraktListEntry(type: "series", id: $0.imdb) }
            let metas = await WatchlistLoader.load(entries, addons: store.addons)
            upcomingItems = Dictionary(metas.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        case .library(let refID):
            if let ref = services.folders.first(where: { $0.id == refID }),
               let src = services.librarySources.first(where: { $0.idPrefix == ref.prefix }) {
                libraryItems = await src.items(in: ref.folder)
                filter.note(libraryItems)
            }
        case .type(let t):
            rows = await fetchRows { cat in cat.type == t && cat.isBrowsable ? [:] : nil }
            if rows.isEmpty && t == "anime" {   // no anime-type catalog: fall back to an "Anime" genre
                rows = await fetchRows { cat in cat.supportsGenre("Anime") ? ["genre": "Anime"] : nil }
            }
        case .genre(let g):
            rows = await fetchRows { cat in cat.supportsGenre(g) ? ["genre": g] : nil }
        case .newReleases:
            func fresh(_ cat: CatalogDecl) -> Bool {
                let hay = (cat.id + " " + (cat.name ?? "")).lowercased()
                return ["new", "latest", "recent", "release"].contains { hay.contains($0) }
            }
            var found = await fetchRows { cat in cat.type == "movie" && cat.isBrowsable && fresh(cat) ? [:] : nil }
            if found.isEmpty {   // no "new" catalog: take any movie catalog, newest titles first
                found = await fetchRows { cat in cat.type == "movie" && cat.isBrowsable ? [:] : nil }
            }
            let thisYear = Calendar.current.component(.year, from: Date())
            rows = found.map { row in
                let recent = row.items.filter { (year($0) ?? 0) >= thisYear - 1 }
                let items = (recent.isEmpty ? row.items : recent).sorted { (year($0) ?? 0) > (year($1) ?? 0) }
                return CatalogRow(id: row.id, title: row.title, type: row.type, items: items)
            }
        case .keyword(let words):
            func hit(_ cat: CatalogDecl) -> Bool {
                let hay = (cat.id + " " + (cat.name ?? "")).lowercased()
                return words.contains { hay.contains($0) }
            }
            rows = await fetchRows { cat in cat.isBrowsable && hit(cat) ? [:] : nil }
            if rows.isEmpty {   // no catalog is named that way; fall back to whatever can be browsed
                rows = await fetchRows { cat in cat.isBrowsable ? [:] : nil }
            }
        }
    }

    /// `extra` returns the catalog parameters to use, or nil to skip that catalog.
    private func fetchRows(extra: (CatalogDecl) -> [String: String]?) async -> [CatalogRow] {
        var built: [CatalogRow] = []
        for addon in store.addons {
            for cat in addon.manifest.catalogs {
                guard let params = extra(cat) else { continue }
                if let items = try? await AddonClient.catalog(addon, type: cat.type, id: cat.id, extra: params), !items.isEmpty {
                    built.append(CatalogRow(id: "\(addon.id)/\(cat.uid)",
                                            title: "\(cat.displayName) · \(cat.type.capitalized)",
                                            type: cat.type, items: items))
                    rows = built   // show rows progressively
                }
            }
        }
        return built
    }
}
