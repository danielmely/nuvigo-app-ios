import SwiftUI
import Combine

/// A major streaming service shown as a card on the Search tab.
/// `provider` is the TMDB watch-provider ID used to list what's on it.
nonisolated struct StreamingService: Identifiable, Hashable {
    let name: String
    let provider: Int
    let colors: [Color]
    var id: Int { provider }

    static let all: [StreamingService] = [
        .init(name: "Netflix", provider: 8, colors: [Color(red: 0.90, green: 0.04, blue: 0.08), Color(red: 0.45, green: 0.0, blue: 0.03)]),
        .init(name: "Apple TV+", provider: 350, colors: [Color(white: 0.25), Color(white: 0.04)]),
        .init(name: "Prime Video", provider: 9, colors: [Color(red: 0.0, green: 0.66, blue: 0.88), Color(red: 0.0, green: 0.28, blue: 0.55)]),
        .init(name: "Disney+", provider: 337, colors: [Color(red: 0.07, green: 0.20, blue: 0.62), Color(red: 0.02, green: 0.07, blue: 0.30)]),
        .init(name: "Max", provider: 1899, colors: [Color(red: 0.35, green: 0.16, blue: 0.85), Color(red: 0.12, green: 0.05, blue: 0.45)]),
        .init(name: "Hulu", provider: 15, colors: [Color(red: 0.11, green: 0.91, blue: 0.51), Color(red: 0.02, green: 0.45, blue: 0.25)]),
        .init(name: "Paramount+", provider: 531, colors: [Color(red: 0.0, green: 0.39, blue: 1.0), Color(red: 0.0, green: 0.16, blue: 0.55)]),
        .init(name: "Peacock", provider: 386, colors: [Color(red: 0.95, green: 0.75, blue: 0.0), Color(red: 0.60, green: 0.30, blue: 0.0)]),
        .init(name: "Crunchyroll", provider: 283, colors: [Color(red: 0.96, green: 0.46, blue: 0.13), Color(red: 0.62, green: 0.22, blue: 0.02)]),
        .init(name: "Starz", provider: 43, colors: [Color(white: 0.16), Color(red: 0.0, green: 0.0, blue: 0.0)]),
        .init(name: "AMC+", provider: 526, colors: [Color(red: 0.0, green: 0.0, blue: 0.0), Color(red: 0.25, green: 0.25, blue: 0.30)]),
        .init(name: "MGM+", provider: 583, colors: [Color(red: 0.80, green: 0.62, blue: 0.10), Color(red: 0.35, green: 0.25, blue: 0.0)]),
        .init(name: "Discovery+", provider: 520, colors: [Color(red: 0.0, green: 0.35, blue: 0.95), Color(red: 0.0, green: 0.12, blue: 0.45)]),
        .init(name: "Shudder", provider: 99, colors: [Color(red: 0.75, green: 0.0, blue: 0.0), Color(red: 0.18, green: 0.0, blue: 0.0)]),
        .init(name: "Tubi", provider: 73, colors: [Color(red: 0.98, green: 0.35, blue: 0.20), Color(red: 0.45, green: 0.10, blue: 0.40)]),
        .init(name: "Pluto TV", provider: 300, colors: [Color(red: 0.95, green: 0.85, blue: 0.0), Color(red: 0.25, green: 0.18, blue: 0.55)]),
    ]
}

/// A genre users can browse, with its TMDB IDs for movies and for shows.
nonisolated struct GenreOption: Identifiable, Hashable {
    let name: String
    let emoji: String
    let movieID: Int?
    let tvID: Int?
    var id: String { name }

    static let all: [GenreOption] = [
        .init(name: "Action", emoji: "💥", movieID: 28, tvID: 10759),
        .init(name: "Adventure", emoji: "🧭", movieID: 12, tvID: 10759),
        .init(name: "Animation", emoji: "🎨", movieID: 16, tvID: 16),
        .init(name: "Comedy", emoji: "😂", movieID: 35, tvID: 35),
        .init(name: "Crime", emoji: "🕵️", movieID: 80, tvID: 80),
        .init(name: "Documentary", emoji: "🎥", movieID: 99, tvID: 99),
        .init(name: "Drama", emoji: "🎭", movieID: 18, tvID: 18),
        .init(name: "Family", emoji: "👨‍👩‍👧", movieID: 10751, tvID: 10751),
        .init(name: "Fantasy", emoji: "🧙", movieID: 14, tvID: 10765),
        .init(name: "History", emoji: "🏛️", movieID: 36, tvID: nil),
        .init(name: "Horror", emoji: "👻", movieID: 27, tvID: nil),
        .init(name: "Kids", emoji: "🧸", movieID: nil, tvID: 10762),
        .init(name: "Music", emoji: "🎵", movieID: 10402, tvID: nil),
        .init(name: "Mystery", emoji: "🔍", movieID: 9648, tvID: 9648),
        .init(name: "News", emoji: "📰", movieID: nil, tvID: 10763),
        .init(name: "Reality", emoji: "📸", movieID: nil, tvID: 10764),
        .init(name: "Romance", emoji: "💕", movieID: 10749, tvID: nil),
        .init(name: "Sci-Fi", emoji: "🚀", movieID: 878, tvID: 10765),
        .init(name: "Talk Show", emoji: "🎙️", movieID: nil, tvID: 10767),
        .init(name: "Thriller", emoji: "😱", movieID: 53, tvID: nil),
        .init(name: "War", emoji: "🪖", movieID: 10752, tvID: 10768),
        .init(name: "Western", emoji: "🤠", movieID: 37, tvID: 37),
    ]
}

/// What a Search-tab card opens.
nonisolated enum DiscoverSource: Hashable {
    case service(StreamingService)
    case genre(GenreOption)

    var title: String {
        switch self {
        case .service(let s): return s.name
        case .genre(let g): return g.name
        }
    }
}

// MARK: Cards

struct ServiceCard: View {
    let service: StreamingService
    var logo: URL? = nil

    var body: some View {
        ZStack(alignment: .leading) {
            LinearGradient(colors: service.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 10) {
                if let logo {
                    AsyncImage(url: logo) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { Color.white.opacity(0.15) }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.25), lineWidth: 0.5))
                }
                Text(service.name)
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 70)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct GenreCard: View {
    let genre: GenreOption

    var body: some View {
        HStack(spacing: 10) {
            Text(genre.emoji).font(.title3)
            Text(genre.name).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: Search tab browse cards

/// Which full list a Search-tab card opens.
nonisolated enum BrowseKind: Hashable { case genres, services }

/// A large card under the search bar that opens the full list of genres or streaming services.
/// The card is filled with a scatter of pictures (`art`) with a dark fade at the bottom behind the title.
struct BrowseCard<Art: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let colors: [Color]
    @ViewBuilder var art: () -> Art

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            art()
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.largeTitle.weight(.heavy)).foregroundStyle(.white)
                        .minimumScaleFactor(0.7).lineLimit(1)
                    Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.title2.weight(.bold)).foregroundStyle(.white.opacity(0.9))
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// A repeatable random number generator, so the scatter holds still while the screen is open and
/// changes only when the seed changes.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Scatters a random handful of `items` over the card, each tilted a little, drawn with `tile`.
struct ScatterArt<Item: Hashable, Tile: View>: View {
    let items: [Item]
    let seed: UInt64
    var count = 7
    @ViewBuilder var tile: (Item, CGFloat) -> Tile

    private struct Spot { let x: CGFloat; let y: CGFloat; let rotation: Double; let scale: CGFloat }

    private func layout(in size: CGSize) -> [(Item, Spot)] {
        var rng = SeededRandom(state: seed)
        let chosen = Array(items.shuffled(using: &rng).prefix(count))
        var cells = Array(0..<9)
        cells.shuffle(using: &rng)
        return chosen.enumerated().map { i, item in
            let c = cells[i % cells.count]
            let cx = (CGFloat(c % 3) + 0.5) / 3, cy = (CGFloat(c / 3) + 0.5) / 3
            let spot = Spot(x: (cx + CGFloat.random(in: -0.06...0.06, using: &rng)) * size.width,
                            y: (cy + CGFloat.random(in: -0.06...0.06, using: &rng)) * size.height,
                            rotation: Double.random(in: -20...20, using: &rng),
                            scale: CGFloat.random(in: 0.85...1.15, using: &rng))
            return (item, spot)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let base = min(geo.size.width, geo.size.height) * 0.3
            ForEach(Array(layout(in: geo.size).enumerated()), id: \.offset) { _, pair in
                tile(pair.0, base)
                    .scaleEffect(pair.1.scale)
                    .rotationEffect(.degrees(pair.1.rotation))
                    .position(x: pair.1.x, y: pair.1.y)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A plain colored tile with the service's name, used when a logo isn't available.
struct ServiceChip: View {
    let service: StreamingService
    let size: CGFloat

    var body: some View {
        Text(service.name)
            .font(.system(size: size * 0.2, weight: .heavy)).foregroundStyle(.white)
            .multilineTextAlignment(.center).minimumScaleFactor(0.5).lineLimit(2).padding(6)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: service.colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

/// The full grid of genres or streaming services.
struct BrowseListView: View {
    let kind: BrowseKind
    @EnvironmentObject var services: Services
    @State private var logos: [Int: URL] = [:]

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                switch kind {
                case .services:
                    ForEach(StreamingService.all) { svc in
                        NavigationLink(value: DiscoverSource.service(svc)) { ServiceCard(service: svc, logo: logos[svc.provider]) }
                            .buttonStyle(.plain)
                    }
                case .genres:
                    ForEach(GenreOption.all) { g in
                        NavigationLink(value: DiscoverSource.genre(g)) { GenreCard(genre: g) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(kind == .services ? "Streaming services" : "Genres")
        .navigationBarTitleDisplayMode(.inline)
        .task { if kind == .services { logos = await services.tmdb.providerLogos() } }
    }
}

// MARK: Destination

/// Lists movies and shows for a streaming service or genre.
struct DiscoverView: View {
    let source: DiscoverSource

    @EnvironmentObject var services: Services
    @EnvironmentObject var store: AddonStore

    @State private var showShows = false
    @State private var movies: [MetaItem] = []
    @State private var shows: [MetaItem] = []
    @State private var loading = false
    @State private var loaded = false

    private let grid = [GridItem(.adaptive(minimum: 100), spacing: 12)]

    private var tmdbReady: Bool { services.tmdb.isConfigured }

    var body: some View {
        Group {
            if !tmdbReady {
                if case .genre(let g) = source {
                    // No TMDB key: fall back to genres exposed by the installed addons.
                    CategoryView(category: .init(kind: .genre(g.name), title: g.name,
                                                 symbol: "tag.fill", tint: Theme.accent))
                } else {
                    ContentUnavailableView("TMDB key needed", systemImage: "key.fill",
                        description: Text("Add your free TMDB API key in Account to see what's on \(source.title)."))
                }
            } else {
                ScrollView {
                    Picker("Type", selection: $showShows) {
                        Text("Movies").tag(false)
                        Text("Shows").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding([.horizontal, .top])

                    let list = showShows ? shows : movies
                    if loading && list.isEmpty { ProgressView().padding(.top, 60) }
                    else if loaded && list.isEmpty {
                        ContentUnavailableView("Nothing found", systemImage: "film",
                            description: Text("No \(showShows ? "shows" : "movies") for \(source.title) in your region."))
                            .padding(.top, 40)
                    } else {
                        LazyVGrid(columns: grid, spacing: 16) { ForEach(list) { PosterLink(item: $0) } }
                            .padding()
                    }
                }
                .task(id: source) { await load() }
                .refreshable { await load() }
            }
        }
        .navigationTitle(source.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load() async {
        loading = true
        defer { loading = false; loaded = true }
        switch source {
        case .service(let s):
            async let m = services.tmdb.discover(isTV: false, provider: s.provider)
            async let t = services.tmdb.discover(isTV: true, provider: s.provider)
            (movies, shows) = await (m, t)
        case .genre(let g):
            async let m = g.movieID != nil ? services.tmdb.discover(isTV: false, genreID: g.movieID) : []
            async let t = g.tvID != nil ? services.tmdb.discover(isTV: true, genreID: g.tvID) : []
            (movies, shows) = await (m, t)
            if movies.isEmpty && !shows.isEmpty { showShows = true }
        }
    }
}
