import SwiftUI
import Combine

/// The last words you searched for, kept on this device for each profile. Nothing is saved in Private mode.
enum RecentSearches {
    private static var key: String { "recentSearches" + ProfileStore.suffix }
    static let limit = 10

    static func load() -> [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }

    @discardableResult
    static func add(_ text: String) -> [String] {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2, !PrivateMode.isOn else { return load() }
        var list = load().filter { $0.caseInsensitiveCompare(t) != .orderedSame }
        list.insert(t, at: 0)
        list = Array(list.prefix(limit))
        UserDefaults.standard.set(list, forKey: key)
        return list
    }

    @discardableResult
    static func remove(_ text: String) -> [String] {
        let list = load().filter { $0 != text }
        UserDefaults.standard.set(list, forKey: key)
        return list
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

struct SearchView: View {
    @EnvironmentObject var store: AddonStore
    @EnvironmentObject var services: Services
    @EnvironmentObject var filter: ContentFilter

    @State private var query = ""
    @ObservedObject private var deepLink = DeepLink.shared
    @State private var handledSearch: UUID?
    @State private var results: [MetaItem] = []
    @State private var searching = false
    @State private var searched = false
    @State private var recents: [String] = RecentSearches.load()
    @State private var logos: [Int: URL] = [:]
    /// Picks which pictures fill the two cards. A new one each time the Search tab opens.
    @State private var artSeed = UInt64.random(in: 1...UInt64.max)

    var body: some View {
        NavigationStack {
          VStack(spacing: 0) {
            searchBar
            Group {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    browseCards
                } else if store.addons.isEmpty && services.librarySources.isEmpty && !store.isLoading {
                    ContentUnavailableView("No addons installed",
                                           systemImage: "puzzlepiece.extension",
                                           description: Text("Add one in the Addons tab, or connect Jellyfin or Plex in Account."))
                } else if searching && results.isEmpty {
                    ProgressView()
                } else if searched && results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(filter.visible(results)) { item in
                        NavigationLink(value: item) {
                            HStack(spacing: 12) {
                                AsyncImage(url: item.poster.flatMap(URL.init(string:))) { $0.resizable().scaledToFill() }
                                    placeholder: { Rectangle().fill(.quaternary) }
                                    .frame(width: 44, height: 66)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                    Text(item.type.capitalized).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .contentMargins(.bottom, 110, for: .scrollContent)
                    .simultaneousGesture(TapGesture().onEnded { recents = RecentSearches.add(query) })
                }
            }
          }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: MetaItem.self) { DetailView(item: $0) }
            .navigationDestination(for: DiscoverSource.self) { DiscoverView(source: $0) }
            .navigationDestination(for: BrowseKind.self) { kind in
                if kind == .ratings { RatingsView() } else { BrowseListView(kind: kind) }
            }
            .task(id: query) { await runSearch() }
            .task { logos = await services.tmdb.providerLogos() }
            .onAppear { recents = RecentSearches.load(); artSeed = UInt64.random(in: 1...UInt64.max); takeSharedQuery() }
            .onChange(of: deepLink.searchRequest) { _, _ in takeSharedQuery() }
        }
    }

    /// A Siri shortcut or link asked for a search: fill it in once.
    private func takeSharedQuery() {
        if let r = deepLink.searchRequest, r.id != handledSearch { handledSearch = r.id; query = r.text }
    }

    /// Large search field that fills the space the old title used. Placeholder is centered.
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.title3).foregroundStyle(.secondary)
            TextField("", text: $query, prompt: Text("Search for anything.").foregroundStyle(.secondary))
                .font(.title3)
                .multilineTextAlignment(query.isEmpty ? .center : .leading)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit { recents = RecentSearches.add(query) }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// Recent searches, with the clear button above every entry.
    @ViewBuilder
    private var recentSection: some View {
        if !recents.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent searches").font(.title3.bold())
                Button(role: .destructive) {
                    RecentSearches.clear()
                    recents = []
                } label: {
                    Label("Clear search history", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                ForEach(recents, id: \.self) { text in
                    HStack(spacing: 12) {
                        Button { query = text } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                                Text(text).foregroundStyle(.primary)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button { recents = RecentSearches.remove(text) } label: {
                            Image(systemName: "xmark").font(.footnote).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(text) from recent searches")
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
            }
            .padding(.horizontal)
        }
    }

    private static let yearArt = ["1925", "1939", "1946", "1955", "1962", "1972", "1980", "1994", "1999", "2004", "2010", "2016", "2021", "2025"]
    private static let ratingArt = ["⭐️ 9.3", "🍅 98%", "⭐️ 8.8", "🍅 100%", "⭐️ 9.0", "🍅 94%", "⭐️ 1.9", "🍅 4%", "⭐️ 2.4", "🍅 12%"]

    /// Shown when the search box is empty: recent searches, then four cards: genres, streaming services, release years and ratings.
    private var browseCards: some View {
        GeometryReader { geo in
            let gap: CGFloat = 16
            // Recent searches take some room above the cards; what is left is split between the two cards,
            // with the same gap above, between and below them.
            let recentsHeight: CGFloat = recents.isEmpty ? 0 : 100 + CGFloat(recents.count) * 36
            let cardHeight = max(150, (geo.size.height - recentsHeight - gap * 5) / 4)
            ScrollView {
                VStack(alignment: .leading, spacing: gap) {
                    recentSection
                    NavigationLink(value: BrowseKind.genres) {
                        BrowseCard(title: "Genres", subtitle: "Action, Comedy, Sci-Fi and more",
                                   colors: [Theme.accent, Theme.accent.opacity(0.55)]) {
                            ScatterArt(items: GenreOption.all, seed: artSeed, count: 12) { g, size in
                                Text(g.emoji).font(.system(size: size * 0.9))
                            }
                        }
                        .frame(height: cardHeight)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    NavigationLink(value: BrowseKind.services) {
                        BrowseCard(title: "Streaming services", subtitle: "Netflix, Hulu, Disney+ and more",
                                   colors: [Color(red: 0.0, green: 0.45, blue: 0.85), Color(red: 0.05, green: 0.15, blue: 0.5)]) {
                            ScatterArt(items: StreamingService.all, seed: artSeed &+ 1, count: 11) { svc, size in
                                if let logo = logos[svc.provider] {
                                    AsyncImage(url: logo) { phase in
                                        if let image = phase.image { image.resizable().scaledToFill() }
                                        else { Color.white.opacity(0.15) }
                                    }
                                    .frame(width: size * 0.8, height: size * 0.8)
                                    .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
                                    .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                                } else {
                                    ServiceChip(service: svc, size: size * 0.8)
                                        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                                }
                            }
                        }
                        .frame(height: cardHeight)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    NavigationLink(value: BrowseKind.years) {
                        BrowseCard(title: "Release years", subtitle: "Every year from 1920 to today",
                                   colors: [Color(red: 0.95, green: 0.45, blue: 0.25), Color(red: 0.6, green: 0.12, blue: 0.35)]) {
                            ScatterArt(items: Self.yearArt, seed: artSeed &+ 2, count: 9) { y, size in
                                Text(y).font(.system(size: size * 0.42, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                                    .frame(width: size * 0.95, height: size * 0.62)
                                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: size * 0.14, style: .continuous))
                            }
                        }
                        .frame(height: cardHeight)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    NavigationLink(value: BrowseKind.ratings) {
                        BrowseCard(title: "Ratings", subtitle: "Top and bottom rated by IMDb and Rotten Tomatoes",
                                   colors: [Color(red: 0.95, green: 0.75, blue: 0.15), Color(red: 0.8, green: 0.2, blue: 0.15)]) {
                            ScatterArt(items: Self.ratingArt, seed: artSeed &+ 3, count: 9) { r, size in
                                Text(r).font(.system(size: size * 0.32, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                                    .minimumScaleFactor(0.6).lineLimit(1)
                                    .frame(width: size * 0.95, height: size * 0.62)
                                    .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: size * 0.14, style: .continuous))
                            }
                        }
                        .frame(height: cardHeight)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }
                .padding(.top, gap)
                .padding(.bottom, 110)   // room to scroll the last card clear of the tab bar
            }
        }
    }

    /// Searches as you type, waiting for a short pause. Changing the query cancels the previous run.
    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { results = []; searched = false; return }
        try? await Task.sleep(for: .milliseconds(400))
        if Task.isCancelled { return }
        searching = true
        defer { searching = false }

        var found: [MetaItem] = []
        for src in services.librarySources {
            found += await src.search(q)
        }
        for addon in store.addons {
            for cat in addon.manifest.catalogs where cat.supportsSearch {
                if let items = try? await AddonClient.catalog(addon, type: cat.type, id: cat.id, extra: ["search": q]) {
                    for i in items where !found.contains(i) { found.append(i) }
                }
            }
        }
        if Task.isCancelled { return }
        results = found
        searched = true
    }
}
