import SwiftUI

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
    @State private var logos: [Int: URL] = [:]
    @State private var recents: [String] = RecentSearches.load()

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
                    .simultaneousGesture(TapGesture().onEnded { recents = RecentSearches.add(query) })
                }
            }
          }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: MetaItem.self) { DetailView(item: $0) }
            .navigationDestination(for: DiscoverSource.self) { DiscoverView(source: $0) }
            .task { logos = await services.tmdb.providerLogos() }
            .task(id: query) { await runSearch() }
            .onAppear { recents = RecentSearches.load(); takeSharedQuery() }
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

    /// Shown when the search box is empty: streaming services, then genres.
    private var browseCards: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                recentSection
                Text("Streaming services").font(.title3.bold()).padding(.horizontal)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                    ForEach(StreamingService.all) { svc in
                        NavigationLink(value: DiscoverSource.service(svc)) { ServiceCard(service: svc, logo: logos[svc.provider]) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                Text("Genres").font(.title3.bold()).padding(.horizontal)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                    ForEach(GenreOption.all) { g in
                        NavigationLink(value: DiscoverSource.genre(g)) { GenreCard(genre: g) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
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
