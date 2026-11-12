import SwiftUI
import Combine
import SafariServices

nonisolated struct StreamEntry: Identifiable {
    let id = UUID()
    let addon: String
    let stream: Stream
}

struct DetailView: View {
    @EnvironmentObject var store: AddonStore
    @EnvironmentObject var trakt: TraktAuth
    @EnvironmentObject var progress: ProgressStore
    @EnvironmentObject var debrid: DebridAuth
    @EnvironmentObject var services: Services
    @EnvironmentObject var downloads: DownloadManager
    @EnvironmentObject var network: NetworkMonitor
    let item: MetaItem

    @AppStorage("downloadWiFiOnly") private var wifiOnly = true
    @AppStorage("preferredQuality") private var preferredQuality = 1080   // 0 = best available

    @State private var meta: MetaItem?
    @State private var selectedVideo: Video?
    @State private var streams: [StreamEntry] = []
    @State private var loadingStreams = false
    @State private var playing: PlayItem?
    @State private var resolving = false
    @State private var alertMessage: String?
    @State private var ratings: TitleRatings?
    @EnvironmentObject var watchedStore: WatchedStore
    @EnvironmentObject var subs: SubscriptionStore
    @State private var descriptionExpanded = false
    @State private var showCover = false
    @AppStorage(SpoilerGuard.key) private var spoilerGuard = false
    @State private var trailerKey: String?
    @State private var showTrailer = false

    private var shown: MetaItem { meta ?? item }

    /// Spoiler guard: an episode counts as seen when it's watched on Trakt, started here, or open right now.
    private func episodeSeen(_ v: Video) -> Bool {
        trakt.isWatched(v.id) || progress.progress(for: v.id) != nil || selectedVideo?.id == v.id
    }
    private var isSeries: Bool { shown.type == "series" && !(shown.videos ?? []).isEmpty }

    /// Stream id: the item id for movies, the episode's video id for series.
    private var streamID: String? { isSeries ? selectedVideo?.id : shown.id }

    // MARK: Buttons and ratings

    private var actionButtons: some View {
        HStack(spacing: 10) {
            let saved = trakt.isInWatchlist(shown.id)
            Button {
                guard subs.allow() else { return }
                guard trakt.isSignedIn else { alertMessage = "Sign in to Trakt in the Account tab to use your watchlist."; return }
                Task { await trakt.toggleWatchlist(type: shown.type, id: shown.id) }
            } label: {
                Label(saved ? "On watchlist" : "Watch later", systemImage: saved ? "bookmark.fill" : "bookmark")
                    .frame(maxWidth: .infinity)
            }
            let seen = trakt.isWatched(shown.id) || watchedStore.contains(shown.id)
            Button {
                guard subs.allow() else { return }
                watchedStore.mark(shown, watched: !seen)       // always saved on this device
                if trakt.isSignedIn { Task { await trakt.setWatched(!seen, type: shown.type, id: shown.id) } }
            } label: {
                Label(seen ? "Watched" : "Mark watched", systemImage: seen ? "eye.fill" : "eye")
                    .frame(maxWidth: .infinity)
            }
            if trailerKey != nil {
                Button { showTrailer = true } label: {
                    Label("Trailer", systemImage: "play.rectangle")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    /// Opens this title on IMDb (the ids are IMDb ids), or a search if the id isn't one.
    private var imdbURL: URL {
        if shown.id.hasPrefix("tt"), let u = URL(string: "https://www.imdb.com/title/\(shown.id.prefix(while: { $0 != ":" }))/") { return u }
        let q = shown.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.imdb.com/find/?q=\(q)")!
    }

    private var tomatoesURL: URL {
        let q = shown.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.rottentomatoes.com/search?search=\(q)")!
    }

    @ViewBuilder
    private var ratingsRow: some View {
        if let r = ratings, r.imdb != nil || r.tomatoes != nil {
            HStack(spacing: 16) {
                if let imdb = r.imdb {
                    Link(destination: imdbURL) {
                    HStack(spacing: 6) {
                        Text("IMDb")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(red: 0.96, green: 0.77, blue: 0.09), in: RoundedRectangle(cornerRadius: 4))
                        Text("\(imdb)/10").font(.subheadline.weight(.semibold))
                        if let v = r.votes { Text(v).font(.caption).foregroundStyle(.secondary) }
                    }
                    }
                    .buttonStyle(.plain)
                }
                if let rt = r.tomatoes {
                    Link(destination: tomatoesURL) {
                        HStack(spacing: 6) {
                            Text("🍅")
                            Text(rt).font(.subheadline.weight(.semibold))
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        if let art = (shown.poster ?? shown.background).flatMap(URL.init(string:)) {
                            Button { showCover = true } label: {
                                AsyncImage(url: CoverArt.hiRes(art)) { $0.resizable().scaledToFit() } placeholder: { Color.gray.opacity(0.2) }
                                    .frame(width: 110)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("View cover art")
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(shown.name).font(.title3.weight(.semibold))
                            let info = [shown.releaseInfo, shown.genres?.first, shown.runtime].compactMap { $0 }.joined(separator: " · ")
                            if !info.isEmpty { Text(info).font(.subheadline).foregroundStyle(.secondary) }
                            if let d = ratings?.director {
                                Text("Directed by \(d)").font(.subheadline)
                            }
                            if let c = ratings?.cast, !c.isEmpty {
                                Text(c.joined(separator: ", ")).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    actionButtons
                    let blurb = shown.description.flatMap { $0.isEmpty ? nil : $0 } ?? ratings?.plot
                    if let d = blurb {
                        Text(d)
                            .font(.body)
                            .lineSpacing(3)
                            .lineLimit(descriptionExpanded ? nil : 8)
                            .onTapGesture { withAnimation { descriptionExpanded.toggle() } }
                    }
                    ratingsRow
                }
            }

            if isSeries, let videos = shown.videos {
                Section("Episodes") {
                    ForEach(videos) { v in
                        Button { selectedVideo = v } label: {
                            HStack {
                                Text(spoilerGuard && !episodeSeen(v) ? v.episodeNumberOnly : v.episodeTitle)
                                Spacer()
                                if trakt.isWatched(v.id) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                }
                                if selectedVideo?.id == v.id { Image(systemName: "play.fill").foregroundStyle(.tint) }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }

            Section("Streams") {
                if let id = streamID, progress.resumePosition(for: id) > 0 {
                    HStack {
                        Label("Resumes at \(Self.format(progress.resumePosition(for: id)))", systemImage: "clock.arrow.circlepath")
                            .font(.subheadline)
                        Spacer()
                        Button("Start over") { progress.clear(id) }.font(.subheadline)
                    }
                }
                if let id = streamID, let d = downloads.entry(id) { downloadRow(d, id: id) }
                if let best = streams.first(where: { canPlay($0.stream) }), streams.count > 1 {
                    Button { Task { await play(best) } } label: {
                        Label("Play best stream", systemImage: "sparkles")
                    }
                }
                if loadingStreams { ProgressView() }
                else if streamID == nil { Text("Pick an episode.").foregroundStyle(.secondary) }
                else if streams.isEmpty { Text("No streams found.").foregroundStyle(.secondary) }

                ForEach(streams) { entry in
                    HStack(spacing: 12) {
                        Button { Task { await play(entry) } } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.stream.displayTitle).font(.subheadline)
                                StreamBadges(entry: entry)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.primary)
                        Button { Task { await download(entry) } } label: {
                            Image(systemName: "arrow.down.circle").font(.title3)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Download for offline")
                    }
                    .disabled(!canPlay(entry.stream))
                }
            }
        }
        .overlay {
            if resolving {
                ProgressView("Preparing stream…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .allowsHitTesting(!resolving)
        .navigationTitle(shown.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if services.tmdb.isSignedIn, shown.id.hasPrefix("tt") {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach((1...10).reversed(), id: \.self) { n in
                            Button("\(n) ★") { Task { await services.tmdb.rate(shown, value: n) } }
                        }
                    } label: {
                        Image(systemName: "star")
                    }
                    .accessibilityLabel("Rate on TMDB")
                }
            }
            if trakt.isSignedIn, shown.id.hasPrefix("tt") {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        guard subs.allow() else { return }
                        Task { await trakt.toggleWatchlist(type: shown.type, id: shown.id) }
                    } label: {
                        Image(systemName: trakt.isInWatchlist(shown.id) ? "bookmark.fill" : "bookmark")
                    }
                    .accessibilityLabel(trakt.isInWatchlist(shown.id) ? "Remove from watchlist" : "Add to watchlist")
                }
            }
        }
        .task { await loadMeta() }
        .task { ratings = await Ratings.load(imdbID: shown.id) }
        .task(id: shown.id) { trailerKey = await services.tmdb.trailerKey(for: shown) }
        .sheet(isPresented: $showTrailer) {
            if let key = trailerKey, let url = URL(string: "https://www.youtube.com/watch?v=\(key)") {
                SafariView(url: url).ignoresSafeArea()
            }
        }
        .task(id: streamID) { await loadStreams() }
        .fullScreenCover(isPresented: $showCover) {
            CoverViewer(url: (shown.poster ?? shown.background).flatMap(URL.init(string:)).map(CoverArt.ultra), title: shown.name)
        }
        .fullScreenCover(item: $playing) { p in
            PlayerView(item: p, resolveNext: { await resolveNext(from: $0) })
                .environmentObject(trakt)
                .environmentObject(progress)
                .environmentObject(services)
        }
        .alert("Heads up", isPresented: Binding(get: { alertMessage != nil },
                                                           set: { if !$0 { alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    // MARK: Downloads

    @ViewBuilder
    private func downloadRow(_ d: DownloadEntry, id: String) -> some View {
        switch d.state {
        case .done:
            HStack {
                Button { Task { await playDownloaded(id) } } label: {
                    Label("Play downloaded copy", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderless)
                Spacer()
                Text(DownloadManager.sizeText(d.bytes)).font(.caption).foregroundStyle(.secondary)
                Button(role: .destructive) { downloads.remove(id) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Delete download")
            }
        case .downloading:
            HStack(spacing: 12) {
                ProgressView(value: d.progress)
                Text("\(Int(d.progress * 100))%").font(.caption).foregroundStyle(.secondary)
                Button { downloads.remove(id) } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Cancel download")
            }
        case .failed:
            HStack {
                Text(d.error ?? "Download failed").font(.footnote).foregroundStyle(.red)
                Spacer()
                Button("Dismiss") { downloads.remove(id) }.buttonStyle(.borderless).font(.footnote)
            }
        }
    }

    private func download(_ entry: StreamEntry) async {
        guard subs.allow(), let id = streamID else { return }
        resolving = true
        defer { resolving = false }
        do {
            guard let url = try await playableURL(for: entry.stream) else { return }
            downloads.start(url: url, context: context(for: id), wifiOnly: wifiOnly)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func playDownloaded(_ id: String) async {
        guard subs.allow() else { return }
        guard let url = downloads.localURL(for: id) else { return }
        let subs = network.isOnline ? await loadSubtitles(id: id) : []
        playing = PlayItem(url: url, context: context(for: id), subtitles: subs,
                           streamName: "Downloaded", startAt: progress.resumePosition(for: id))
    }

    // MARK: Stream rules

    private func canPlay(_ s: Stream) -> Bool {
        s.hasDirectURL || (FeatureFlags.debridEnabled && s.infoHash != nil && debrid.isConnected)
    }

    private func note(for e: StreamEntry) -> String {
        if StreamRanker.info(e.stream).likelyUnplayable { return "\(e.addon) · may not play (format needs the extra player)" }
        if e.stream.hasDirectURL { return e.addon }
        if e.stream.infoHash != nil, FeatureFlags.debridEnabled {
            return debrid.isConnected
                ? "\(e.addon) · torrent via \(debrid.connectedNames)"
                : "\(e.addon) · torrent · connect a debrid account in Account"
        }
        return "\(e.addon) · not supported on-device"
    }

    /// Direct URL, or a debrid-resolved URL for torrent streams.
    private func playableURL(for s: Stream) async throws -> URL? {
        if let u = s.url { return URL(string: u) }
        if let hash = s.infoHash { return try await debrid.resolve(infoHash: hash, fileIdx: s.fileIdx) }
        return nil
    }

    // MARK: Playing

    private func play(_ entry: StreamEntry) async {
        guard subs.allow(), let id = streamID else { return }
        resolving = true
        defer { resolving = false }
        do {
            guard let url = try await playableURL(for: entry.stream) else { return }
            let subs = await loadSubtitles(id: id)
            playing = PlayItem(url: url, context: context(for: id), subtitles: subs,
                               streamName: entry.stream.name ?? entry.addon,
                               startAt: progress.resumePosition(for: id))
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    /// Finds a stream for the episode after `item`, preferring the same source the viewer picked.
    @MainActor
    private func resolveNext(from item: PlayItem) async -> PlayItem? {
        guard let next = item.context.nextEpisode else { return nil }
        // A downloaded copy of the next episode wins, and works offline.
        if let local = downloads.localURL(for: next.id) {
            selectedVideo = next
            return PlayItem(url: local, context: context(for: next.id), subtitles: [],
                            streamName: "Downloaded", startAt: progress.resumePosition(for: next.id))
        }
        let candidates = await fetchStreams(id: next.id).filter { canPlay($0.stream) }
        let pick = candidates.first { ($0.stream.name ?? $0.addon) == item.streamName } ?? candidates.first
        guard let pick, let url = try? await playableURL(for: pick.stream) else { return nil }
        let subs = await loadSubtitles(id: next.id)
        selectedVideo = next
        return PlayItem(url: url, context: context(for: next.id), subtitles: subs,
                        streamName: pick.stream.name ?? pick.addon,
                        startAt: progress.resumePosition(for: next.id))
    }

    private func context(for id: String) -> PlaybackContext {
        let ep = isSeries ? shown.videos?.first { $0.id == id } : nil
        return PlaybackContext(key: id, item: shown, episodeLabel: ep?.episodeTitle,
                               nextEpisode: ep.flatMap(nextVideo(after:)))
    }

    private func nextVideo(after v: Video) -> Video? {
        let list = (shown.videos ?? [])
            .filter { ($0.season ?? 0) > 0 || ($0.season ?? 0) == (v.season ?? 0) }
            .sorted { (($0.season ?? 0), ($0.episode ?? 0)) < (($1.season ?? 0), ($1.episode ?? 0)) }
        guard let i = list.firstIndex(where: { $0.id == v.id }), i + 1 < list.count else { return nil }
        return list[i + 1]
    }

    // MARK: Loading

    private func loadMeta() async {
        // Titles from your own server come from that server, never from addons.
        if let src = services.source(for: item.id) {
            if let m = await src.meta(id: item.id) { meta = m }
            return
        }
        for addon in store.addons where addon.supports("meta", type: item.type, id: item.id) {
            if let m = try? await AddonClient.meta(addon, type: item.type, id: item.id) {
                meta = m
                break
            }
        }
        // Fill in a missing poster, background or description from TMDB.
        let enriched = await services.tmdb.enrich(meta ?? item)
        if enriched.poster != (meta ?? item).poster || enriched.background != (meta ?? item).background
            || enriched.description != (meta ?? item).description {
            meta = enriched
        }
    }

    private func loadStreams() async {
        streams = []
        guard let id = streamID else { return }
        loadingStreams = true
        defer { loadingStreams = false }
        streams = await fetchStreams(id: id)
    }

    private func fetchStreams(id: String) async -> [StreamEntry] {
        if let src = services.source(for: id) {
            guard let url = src.streamURL(id: id) else { return [] }
            let stream = Stream(url: url.absoluteString, infoHash: nil, fileIdx: nil, name: src.sourceName,
                                title: "Plays from your server", description: nil, externalUrl: nil)
            return [StreamEntry(addon: src.sourceName, stream: stream)]
        }
        let type = item.type
        let addons = store.addons.filter { $0.supports("stream", type: type, id: id) }
        var out: [(Int, [StreamEntry])] = []
        await withTaskGroup(of: (Int, [StreamEntry]).self) { group in
            for (i, addon) in addons.enumerated() {
                group.addTask {
                    let list = (try? await AddonClient.streams(addon, type: type, id: id)) ?? []
                    return (i, list.map { StreamEntry(addon: addon.manifest.name, stream: $0) })
                }
            }
            for await r in group { out.append(r) }
        }
        let flat = out.sorted { $0.0 < $1.0 }.flatMap { $0.1 }
        return StreamRanker.sorted(flat, maxResolution: preferredQuality == 0 ? 9999 : preferredQuality) { canPlay($0.stream) }
    }

    private func loadSubtitles(id: String) async -> [SubtitleTrack] {
        if services.source(for: id) != nil { return [] }   // the server's own subtitles are not loaded
        let type = item.type
        let addons = store.addons.filter { $0.supports("subtitles", type: type, id: id) }
        var out: [(Int, [SubtitleTrack])] = []
        await withTaskGroup(of: (Int, [SubtitleTrack]).self) { group in
            for (i, addon) in addons.enumerated() {
                group.addTask { (i, (try? await AddonClient.subtitles(addon, type: type, id: id)) ?? []) }
            }
            for await r in group { out.append(r) }
        }
        var tracks = out.sorted { $0.0 < $1.0 }.flatMap { $0.1 }
        if services.openSubtitles.isSignedIn, let ref = TitleRef(id: id) {
            tracks += await services.openSubtitles.search(ref, isSeries: isSeries)
        }
        return tracks
    }

    private static func format(_ seconds: Double) -> String {
        let s = Int(seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}


/// Nearly full-screen, highest-resolution cover. Tap anywhere or Close to dismiss; pinch to zoom.
struct CoverViewer: View {
    let url: URL?
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.96).ignoresSafeArea()
                .onTapGesture { dismiss() }
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .scaleEffect(scale)
                        .gesture(MagnificationGesture()
                            .onChanged { scale = max(1, min($0, 4)) }
                            .onEnded { _ in withAnimation { scale = 1 } })
                case .failure:
                    Text(title).foregroundStyle(.white)
                default:
                    ProgressView().tint(.white)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 50)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(true)
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.title).symbolRenderingMode(.hierarchical).foregroundStyle(.white)
            }
            .padding()
            .accessibilityLabel("Close")
        }
    }
}


/// Opens a web page inside the app (used for trailers).
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
