import SwiftUI
import Combine

/// The "Already watched" screen: three picks for you on top, then every title you've watched with your rating.
struct WatchedContent: View {
    @EnvironmentObject var watched: WatchedStore
    @EnvironmentObject var filter: ContentFilter
    @EnvironmentObject var trakt: TraktAuth
    @EnvironmentObject var store: AddonStore
    @EnvironmentObject var services: Services

    @State private var picks: [Recommendation] = []
    @State private var candidates: [MetaItem] = []
    @State private var editing: WatchedItem?
    @State private var infoItem: MetaItem?
    @State private var loadingPicks = false

    private let grid = [GridItem(.adaptive(minimum: 100), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            picksSection
            watchedSection
        }
        .padding(.vertical)
        .task(id: trakt.watchedKeys.count) { await importFromTrakt() }
        .task { await loadCandidates() }
        .onChange(of: watched.items) { _, _ in refreshPicks() }
        .onChange(of: candidates.count) { _, _ in refreshPicks() }
        .sheet(item: $editing) { item in
            RatingSheet(item: item, onInfo: { infoItem = item.metaItem })
                .presentationDetents([.medium])
        }
        .navigationDestination(item: $infoItem) { DetailView(item: $0) }
    }

    // MARK: Picks

    @ViewBuilder
    private var picksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Picked for you").font(.title3.bold()).padding(.horizontal)
            if !picks.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(picks.filter { !filter.isHidden($0.item) }) { RecommendationCard(rec: $0) }
                    if picks.count < 3 { ForEach(0..<(3 - picks.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) } }
                }
                .padding(.horizontal)
            } else if loadingPicks {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
            } else {
                Text(watched.items.isEmpty ? "Mark a few titles as watched and rate them. Your picks show up here."
                                           : "Rate some of your titles below to get picks that fit your taste.")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
            }
        }
    }

    // MARK: Watched grid

    @ViewBuilder
    private var watchedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Already watched" + (watched.items.isEmpty ? "" : " (\(watched.items.count))"))
                .font(.title3.bold()).padding(.horizontal)
            if watched.items.isEmpty {
                Text("Nothing here yet. Use Mark watched on a title's page, finish a movie, or sign in to Trakt to bring in your history.")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
            } else {
                LazyVGrid(columns: grid, spacing: 16) {
                    ForEach(watched.items.filter { !filter.isHidden(id: $0.id) }) { w in
                        Button { editing = w } label: { WatchedTile(item: w) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: Data

    private func importFromTrakt() async {
        guard trakt.isSignedIn else { return }
        var ids: [String] = []
        var types: [String: String] = [:]
        for key in trakt.watchedKeys {
            let base = key.split(separator: ":").first.map(String.init) ?? key
            if types[base] == nil { types[base] = key.contains(":") ? "series" : "movie"; ids.append(base) }
        }
        let fresh = ids.filter { !watched.contains($0) && !watched.isHidden($0) }
        guard !fresh.isEmpty else { return }
        let entries = fresh.prefix(40).map { TraktListEntry(type: types[$0] ?? "movie", id: $0) }
        watched.addImported(await WatchlistLoader.load(Array(entries), addons: store.addons))
    }

    /// Titles to choose from: your addons' catalogs, plus TMDB's popular titles in your favorite genres.
    private func loadCandidates() async {
        loadingPicks = true
        defer { loadingPicks = false }
        var pool = await HomeRows.load(store.addons, limit: 8).flatMap(\.items)

        if services.tmdb.isConfigured {
            let favorites = topGenres()
            for name in favorites {
                guard let g = GenreOption.all.first(where: { $0.name.lowercased() == name.lowercased() }) else { continue }
                async let movies = g.movieID != nil ? services.tmdb.discover(isTV: false, genreID: g.movieID) : []
                async let shows = g.tvID != nil ? services.tmdb.discover(isTV: true, genreID: g.tvID) : []
                for m in (await movies) + (await shows) {
                    pool.append(MetaItem(id: m.id, type: m.type, name: m.name, poster: m.poster, background: m.background,
                                         description: m.description, releaseInfo: m.releaseInfo, runtime: nil,
                                         genres: [g.name], videos: nil))
                }
            }
        }
        candidates = pool
        filter.note(pool)
        filter.note(ids: watched.items.map(\.id))
        refreshPicks()
    }

    private func topGenres() -> [String] {
        var weight: [String: Double] = [:]
        for w in watched.items { for g in w.genres { weight[g, default: 0] += Double((w.rating ?? 7) - 5) } }
        return weight.filter { $0.value > 0 }.sorted { $0.value > $1.value }.prefix(2).map(\.key)
    }

    private func refreshPicks() {
        picks = Recommender.recommend(from: watched.items, candidates: candidates)
    }
}

// MARK: Pieces

struct RecommendationCard: View {
    let rec: Recommendation

    var body: some View {
        NavigationLink(value: rec.item) {
            VStack(alignment: .leading, spacing: 5) {
                AsyncImage(url: rec.item.poster.flatMap(URL.init(string:))) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { Rectangle().fill(.quaternary) }
                }
                .aspectRatio(2 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(rec.item.name).font(.caption.weight(.semibold)).lineLimit(1).foregroundStyle(.primary)
                HStack(spacing: 4) {
                    Image(systemName: "hand.thumbsup.fill").font(.caption2)
                    Text("\(rec.percent)% likely to like").font(.caption2.weight(.bold))
                }
                .foregroundStyle(Theme.accent)
                ProgressView(value: Double(rec.percent), total: 100).tint(Theme.accent)
                Text(rec.reason).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

struct WatchedTile: View {
    let item: WatchedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AsyncImage(url: item.poster.flatMap(URL.init(string:))) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else {
                    ZStack {
                        Rectangle().fill(.quaternary)
                        Text(item.name).font(.caption.weight(.semibold)).multilineTextAlignment(.center).padding(6)
                    }
                }
            }
            .aspectRatio(2 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 3) {
                    Image(systemName: item.rating == nil ? "star" : "star.fill")
                    Text(item.rating.map(String.init) ?? "Rate")
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(item.rating == nil ? .white : .black)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(item.rating == nil ? AnyShapeStyle(.black.opacity(0.6)) : AnyShapeStyle(Color.yellow), in: Capsule())
                .padding(6)
            }
            Text(item.name).font(.caption).lineLimit(1).foregroundStyle(.primary)
        }
    }
}

/// Tap a watched poster: rate it 1 to 10, open its page, or take it off the list.
struct RatingSheet: View {
    let item: WatchedItem
    let onInfo: () -> Void

    @EnvironmentObject var watched: WatchedStore
    @Environment(\.dismiss) private var dismiss

    private var current: Int? { watched.items.first { $0.id == item.id }?.rating }

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                AsyncImage(url: item.poster.flatMap(URL.init(string:))) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { Rectangle().fill(.quaternary) }
                }
                .frame(width: 60, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.headline).lineLimit(2)
                    Text([item.year, item.type == "series" ? "Show" : "Movie"].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Your rating").font(.subheadline.weight(.semibold))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                    ForEach(1...10, id: \.self) { n in
                        Button { watched.rate(item.id, current == n ? nil : n) } label: {
                            Text("\(n)")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(current == n ? Theme.accent : Color.secondary.opacity(0.15),
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .foregroundStyle(current == n ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Rate \(n) out of 10")
                    }
                }
            }

            HStack(spacing: 10) {
                Button { dismiss(); onInfo() } label: { Label("View full info", systemImage: "info.circle").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                Button(role: .destructive) { watched.remove(item.id); dismiss() } label: {
                    Label("Remove", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            Spacer(minLength: 0)
        }
        .padding()
    }
}
