import Foundation
import Combine

/// Which title a playback key points at, in the terms the trackers understand.
/// Keys look like "tt0111161" (movie) or "tt0944947:1:2" (series, season 1 episode 2).
struct TitleRef {
    let imdb: String
    let season: Int?
    let episode: Int?

    init?(id: String) {
        let parts = id.split(separator: ":").map(String.init)
        guard let first = parts.first, first.hasPrefix("tt") else { return nil }
        imdb = first
        if parts.count >= 3, let s = Int(parts[1]), let e = Int(parts[2]) {
            season = s; episode = e
        } else {
            season = nil; episode = nil
        }
    }

    init?(_ ctx: PlaybackContext) { self.init(id: ctx.key) }
}

/// One place that holds every optional service, so views need a single environment object.
/// It re-publishes whenever any service changes.
@MainActor
final class Services: ObservableObject {
    let simkl = SimklAuth()
    let anilist = AniListAuth()
    let mal = MALAuth()
    let jellyfin = JellyfinSource()
    let plex = PlexSource()
    let openSubtitles = OpenSubtitlesAuth()
    let tmdb = TMDBAuth()

    /// Every folder (Movies, TV Shows…) of every connected media server.
    @Published private(set) var folders: [LibraryFolderRef] = []

    private var bag = Set<AnyCancellable>()

    init() {
        forward(simkl); forward(anilist); forward(mal)
        forward(jellyfin); forward(plex)
        forward(openSubtitles); forward(tmdb)

        // Reload the folder list when a server is connected or disconnected.
        jellyfin.$session.dropFirst().sink { [weak self] _ in
            Task { @MainActor in await self?.refreshLibraries() }
        }.store(in: &bag)
        plex.$session.dropFirst().sink { [weak self] _ in
            Task { @MainActor in await self?.refreshLibraries() }
        }.store(in: &bag)
    }

    private func forward<O: ObservableObject>(_ object: O) where O.ObjectWillChangePublisher == ObservableObjectPublisher {
        object.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
    }

    // MARK: Media servers

    var librarySources: [any LibrarySource] {
        let all: [any LibrarySource] = [jellyfin, plex]
        return all.filter { $0.isConnected }
    }

    /// The connected server that owns an id like "jf:abc" or "plex:123", if any.
    func source(for itemID: String) -> (any LibrarySource)? {
        librarySources.first { itemID.hasPrefix($0.idPrefix) }
    }

    func refreshLibraries() async {
        var out: [LibraryFolderRef] = []
        for src in librarySources {
            for folder in await src.libraries() {
                out.append(LibraryFolderRef(prefix: src.idPrefix, sourceName: src.sourceName, folder: folder))
            }
        }
        folders = out
    }

    // MARK: Trackers

    /// Called when playback stops. Anything watched to 80% or more is recorded on Simkl, AniList and MyAnimeList.
    func trackFinished(_ ctx: PlaybackContext, percent: Double) {
        guard percent >= 80, !PrivateMode.isOn else { return }
        Task {
            if simkl.isSignedIn { await simkl.markWatched(ctx) }
            if anilist.isSignedIn { await anilist.update(ctx) }
            if mal.isSignedIn { await mal.update(ctx) }
        }
    }
}
