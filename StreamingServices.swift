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
