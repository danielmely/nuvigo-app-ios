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
    case year(Int)

    var title: String {
        switch self {
        case .service(let s): return s.name
        case .genre(let g): return g.name
        case .year(let y): return String(y)
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
        ZStack(alignment: .leading) {
            LinearGradient(colors: [Theme.accent.opacity(0.35), Theme.accent.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 10) {
                Text(genre.emoji)
                    .font(.system(size: 26))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(genre.name)
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(.white)
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

/// One release year, drawn the same size and style as `GenreCard`.
struct YearCard: View {
    let year: Int

    var body: some View {
        ZStack(alignment: .leading) {
            LinearGradient(colors: [Color(red: 0.95, green: 0.45, blue: 0.25).opacity(0.8), Color(red: 0.75, green: 0.2, blue: 0.4).opacity(0.7)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 10) {
                Text("📅")
                    .font(.system(size: 26))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(String(year))
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 70)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: Search tab browse cards

/// Which full list a Search-tab card opens.
nonisolated enum BrowseKind: Hashable { case genres, services, years, ratings }

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
        var cells = Array(0..<12)   // a grid of 4 columns by 3 rows
        cells.shuffle(using: &rng)
        return chosen.enumerated().map { i, item in
            let c = cells[i % cells.count]
            let cx = (CGFloat(c % 4) + 0.5) / 4, cy = (CGFloat(c / 4) + 0.5) / 3
            let spot = Spot(x: (cx + CGFloat.random(in: -0.06...0.06, using: &rng)) * size.width,
                            y: (cy + CGFloat.random(in: -0.06...0.06, using: &rng)) * size.height,
                            rotation: Double.random(in: -20...20, using: &rng),
                            scale: CGFloat.random(in: 0.85...1.15, using: &rng))
            return (item, spot)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let base = min(geo.size.width, geo.size.height) * 0.25
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

    /// Newest first, back to 1920.
    static var years: [Int] { Array((1920...max(1920, Calendar.current.component(.year, from: Date()))).reversed()) }

    private var title: LocalizedStringKey {
        switch kind {
        case .services: return "Streaming services"
        case .genres: return "Genres"
        case .years, .ratings: return "Release years"
        }
    }

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
                case .years, .ratings:
                    ForEach(Self.years, id: \.self) { y in
                        NavigationLink(value: DiscoverSource.year(y)) { YearCard(year: y) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(title)
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
        case .year(let y):
            async let m = services.tmdb.discover(isTV: false, year: y)
            async let t = services.tmdb.discover(isTV: true, year: y)
            (movies, shows) = await (m, t)
            if movies.isEmpty && !shows.isEmpty { showShows = true }
        }
    }
}

// MARK: Ratings

/// Which score the Ratings page ranks by.
nonisolated enum RatingSource: String, CaseIterable, Identifiable {
    case combined = "Combined", imdb = "IMDb", tomatoes = "Rotten Tomatoes"
    var id: String { rawValue }
}

/// The highest or lowest rated movies and shows, by IMDb, Rotten Tomatoes, or both averaged together,
/// optionally within one genre.
///
/// Candidates come from TMDB's best (or worst) scored titles with plenty of votes; each one's IMDb and
/// Rotten Tomatoes scores are then looked up through OMDb and the list is ranked by the source you pick.
struct RatingsView: View {
    @EnvironmentObject var services: Services

    private struct Rated: Identifiable {
        let item: MetaItem
        let ratings: TitleRatings
        var id: String { item.id }
        var imdb: Double? { ratings.imdb.flatMap(Double.init).map { $0 * 10 } }          // 0...100
        var tomatoes: Double? { ratings.tomatoes.flatMap { Double($0.replacingOccurrences(of: "%", with: "")) } }
        func score(_ s: RatingSource) -> Double? {
            switch s {
            case .imdb: return imdb
            case .tomatoes: return tomatoes
            case .combined: if let a = imdb, let b = tomatoes { return (a + b) / 2 } else { return nil }
            }
        }
    }

    @State private var source: RatingSource = .combined
    @State private var lowest = false
    @State private var showShows = false
    @State private var genre: GenreOption?
    @State private var pool: [Rated] = []
    @State private var loading = false
    @State private var loaded = false

    private struct LoadKey: Hashable { let lowest: Bool; let shows: Bool; let genre: String? }

    private var ranked: [Rated] {
        let scored = pool.compactMap { r in r.score(source).map { (r, $0) } }
        return scored.sorted { lowest ? $0.1 < $1.1 : $0.1 > $1.1 }.prefix(50).map(\.0)
    }

    var body: some View {
        Group {
            if !services.tmdb.isConfigured {
                ContentUnavailableView("TMDB key needed", systemImage: "key.fill",
                    description: Text("Add your free TMDB API key in Account to browse by rating."))
            } else if !Ratings.isConfigured {
                ContentUnavailableView("OMDb key needed", systemImage: "key.fill",
                    description: Text("IMDb and Rotten Tomatoes scores come from OMDb. Add your free OMDb key in Account."))
            } else {
                content
            }
        }
        .navigationTitle("Ratings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if services.tmdb.isConfigured && Ratings.isConfigured {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Genre", selection: $genre) {
                            Text("All genres").tag(GenreOption?.none)
                            ForEach(GenreOption.all) { g in Text("\(g.emoji) \(g.name)").tag(GenreOption?.some(g)) }
                        }
                    } label: {
                        Label("Filter", systemImage: genre == nil ? "line.3.horizontal.decrease.circle"
                                                                  : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 12) {
                Picker("Source", selection: $source) {
                    ForEach(RatingSource.allCases) { Text($0 == .tomatoes ? "Rotten Tomatoes" : $0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Order", selection: $lowest) {
                    Text("Highest rated").tag(false)
                    Text("Lowest rated").tag(true)
                }
                .pickerStyle(.segmented)
                Picker("Type", selection: $showShows) {
                    Text("Movies").tag(false)
                    Text("Shows").tag(true)
                }
                .pickerStyle(.segmented)
                if let genre {
                    Button { self.genre = nil } label: {
                        Label("\(genre.emoji) \(genre.name)", systemImage: "xmark.circle.fill")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Theme.accent.opacity(0.2), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding([.horizontal, .top])

            if loading && ranked.isEmpty { ProgressView().padding(.top, 60) }
            else if loaded && ranked.isEmpty {
                ContentUnavailableView("Nothing found", systemImage: "star.slash",
                    description: Text(source == .combined ? "No titles here have both an IMDb and a Rotten Tomatoes score."
                                                          : "No scores found for these filters."))
                    .padding(.top, 40)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(ranked.enumerated()), id: \.element.id) { i, r in
                        NavigationLink(value: r.item) { row(i + 1, r) }.buttonStyle(.plain)
                        Divider().padding(.leading, 76)
                    }
                }
                .padding(.top, 8)
            }
        }
        .task(id: LoadKey(lowest: lowest, shows: showShows, genre: genre?.name)) { await load() }
    }

    private func row(_ rank: Int, _ r: Rated) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)").font(.footnote.weight(.bold)).foregroundStyle(.secondary).frame(width: 22)
            AsyncImage(url: r.item.poster.flatMap(URL.init(string:))) { $0.resizable().scaledToFill() }
                placeholder: { Rectangle().fill(.quaternary) }
                .frame(width: 44, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text(r.item.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                HStack(spacing: 10) {
                    if let y = r.item.releaseInfo { Text(y).foregroundStyle(.secondary) }
                    if let v = r.ratings.imdb { Text("⭐️ \(v)") }
                    if let t = r.ratings.tomatoes { Text("🍅 \(t)") }
                }
                .font(.caption)
            }
            Spacer(minLength: 0)
            if source == .combined, let c = r.score(.combined) {
                Text(String(format: "%.0f", c))
                    .font(.headline.weight(.heavy))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.2), in: Capsule())
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func load() async {
        loading = true
        defer { loading = false; loaded = true }
        let tv = showShows
        let gid = tv ? genre?.tvID : genre?.movieID
        let sort = lowest ? "vote_average.asc" : "vote_average.desc"
        let votes = lowest ? 500 : 1000
        if genre != nil && gid == nil { pool = []; return }

        var candidates: [MetaItem] = []
        for page in 1...3 {
            if Task.isCancelled { return }
            candidates += await services.tmdb.discover(isTV: tv, genreID: gid, sort: sort, minVotes: votes, page: page)
        }
        var seen = Set<String>()
        candidates = candidates.filter { seen.insert($0.id).inserted }

        var out: [Rated] = []
        for chunk in stride(from: 0, to: candidates.count, by: 12) {
            if Task.isCancelled { return }
            let batch = Array(candidates[chunk..<min(chunk + 12, candidates.count)])
            await withTaskGroup(of: (MetaItem, TitleRatings?).self) { group in
                for m in batch { group.addTask { (m, await Ratings.load(imdbID: m.id)) } }
                for await (m, r) in group { if let r { out.append(Rated(item: m, ratings: r)) } }
            }
        }
        Ratings.persist()
        if !Task.isCancelled { pool = out }
    }
}
