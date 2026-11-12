import SwiftUI
import Combine
import AVKit

typealias ResolveNext = @MainActor (PlayItem) async -> PlayItem?

struct PlayItem: Identifiable {
    let id = UUID()
    let url: URL
    let context: PlaybackContext
    var subtitles: [SubtitleTrack] = []
    var streamName: String? = nil
    var startAt: Double = 0
}

/// AirPlay route picker (the player's own controls also offer AirPlay and Picture in Picture).
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = UIColor.white.withAlphaComponent(0.9)
        v.activeTintColor = Theme.accentUI
        v.prioritizesVideoDevices = true
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

struct PlayerView: View {
    @EnvironmentObject var trakt: TraktAuth
    @EnvironmentObject var progress: ProgressStore
    @EnvironmentObject var services: Services
    @EnvironmentObject var downloads: DownloadManager
    @Environment(\.dismiss) private var dismiss

    @AppStorage("skipIntroSeconds") private var skipIntro = 85
    @AppStorage("defaultSpeed") private var defaultSpeed = 1.0
    @AppStorage("preferredAudioLang") private var audioLang = "auto"
    @AppStorage("preferredSubLang") private var subLang = "off"
    @AppStorage("autoPlayNext") private var autoPlayNext = true
    @AppStorage("showSkipCredits") private var showSkipCreditsSetting = true

    private let resolveNext: ResolveNext
    private static let speeds: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    @State private var current: PlayItem
    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    @State private var endObserver: NSObjectProtocol?
    @State private var statusObserver: NSKeyValueObservation?
    @State private var finished = false
    @State private var lastSave: TimeInterval = 0
    @State private var pos: Double = 0
    @State private var dur: Double = 0
    @State private var speed = 1.0
    @State private var useAlt = false
    @State private var failure: String?

    @State private var cues: [SubtitleCue] = []
    @State private var selectedSub: SubtitleTrack?
    @State private var subText = ""

    @State private var audioGroup: AVMediaSelectionGroup?
    @State private var legibleGroup: AVMediaSelectionGroup?
    @State private var selectedAudio: AVMediaSelectionOption?
    @State private var selectedEmbedded: AVMediaSelectionOption?

    @AppStorage(SpoilerGuard.key) private var spoilerGuard = false
    @State private var hud: PlayerGesture?
    @State private var hudTask: Task<Void, Never>?

    @State private var showUpNext = false
    @State private var findingNext = false
    @State private var upNext: PlayItem?
    @State private var countdown = 6
    @State private var nextTask: Task<Void, Never>?

    // Sleep timer
    @State private var sleepTask: Task<Void, Never>?
    @State private var sleepEndsAt: Date?
    @State private var sleepAtEnd = false

    init(item: PlayItem, resolveNext: @escaping ResolveNext = { _ in nil }) {
        self.resolveNext = resolveNext
        _current = State(initialValue: item)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if useAlt {
                AltPlayerView(url: current.url).ignoresSafeArea()
            } else if let player {
                PlayerSurface(player: player, onGesture: showHUD).ignoresSafeArea()
                subtitleOverlay
                gestureHUD
            }
            VStack(spacing: 0) {
                topBar
                Spacer()
                if let failure { failureCard(failure) }
                skipRow
                if showUpNext { upNextCard }
            }
        }
        .onAppear { speed = defaultSpeed; start(current) }
        .onDisappear {
            finish()
            WatchTogether.shared.leave()
            // Optional clean-up: remove downloads of things you've finished, now that the file isn't in use.
            let finishedKeys = progress.takeFinishedKeys()
            if UserDefaults.standard.bool(forKey: DownloadManager.autoDeleteKey) {
                for k in finishedKeys { downloads.remove(k) }
            }
        }
    }

    // MARK: Views

    private var topBar: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .accessibilityLabel("Close player")
            Spacer()
            if !useAlt {
                if let g = audioGroup, g.options.count > 1 { audioMenu(g) }
                if hasSubtitleChoices { subtitleMenu }
                speedMenu
                sleepMenu
                WatchTogetherButton(context: current.context)
                AirPlayButton().frame(width: 36, height: 36)
            }
        }
        .padding()
    }

    private var hasSubtitleChoices: Bool {
        !current.subtitles.isEmpty || !(legibleGroup?.options.isEmpty ?? true)
    }

    @ViewBuilder
    private func checked(_ text: String, _ on: Bool) -> some View {
        if on { Label(text, systemImage: "checkmark") } else { Text(text) }
    }

    private func audioMenu(_ group: AVMediaSelectionGroup) -> some View {
        Menu {
            ForEach(group.options, id: \.self) { option in
                Button {
                    player?.currentItem?.select(option, in: group)
                    selectedAudio = option
                    if let code = LanguagePref.code(option.locale?.language.languageCode?.identifier) { audioLang = code }
                } label: { checked(option.displayName, selectedAudio == option) }
            }
        } label: {
            Image(systemName: "speaker.wave.2.fill").font(.title2).foregroundStyle(.white.opacity(0.9))
        }
        .accessibilityLabel("Audio language")
    }

    private var subtitleMenu: some View {
        let labels = subtitleLabels
        return Menu {
            Button { selectSubtitle(nil) } label: {
                checked("Off", selectedSub == nil && selectedEmbedded == nil)
            }
            ForEach(Array(current.subtitles.enumerated()), id: \.offset) { i, track in
                Button { selectSubtitle(track) } label: { checked(labels[i], selectedSub == track) }
            }
            if let g = legibleGroup, !g.options.isEmpty {
                Divider()
                ForEach(g.options, id: \.self) { option in
                    Button { selectEmbedded(option, in: g) } label: {
                        checked("\(option.displayName) (in file)", selectedEmbedded == option)
                    }
                }
            }
        } label: {
            Image(systemName: "captions.bubble.fill").font(.title2).foregroundStyle(.white.opacity(0.9))
        }
        .accessibilityLabel("Subtitles")
    }

    private var speedMenu: some View {
        Menu {
            ForEach(Self.speeds, id: \.self) { s in
                Button { setSpeed(s) } label: { checked(Self.speedLabel(s), speed == s) }
            }
        } label: {
            Text(Self.speedLabel(speed))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.white.opacity(0.2), in: Capsule())
        }
        .accessibilityLabel("Playback speed")
        .accessibilityValue(Self.speedLabel(speed))
    }

    private var sleepActive: Bool { sleepEndsAt != nil || sleepAtEnd }

    private var sleepMenu: some View {
        Menu {
            Button { cancelSleep() } label: { checked("Off", !sleepActive) }
            ForEach([15, 30, 45, 60], id: \.self) { m in
                Button { startSleep(minutes: m) } label: { Text("\(m) minutes") }
            }
            Button { cancelSleep(); sleepAtEnd = true } label: {
                checked(isEpisode ? "End of episode" : "End of movie", sleepAtEnd)
            }
        } label: {
            Image(systemName: sleepActive ? "moon.zzz.fill" : "moon.zzz")
                .font(.title2)
                .foregroundStyle(sleepActive ? Theme.accent : .white.opacity(0.9))
        }
        .accessibilityLabel("Sleep timer")
        .accessibilityValue(sleepActive ? "On" : "Off")
    }

    private func startSleep(minutes: Int) {
        cancelSleep()
        sleepEndsAt = Date().addingTimeInterval(Double(minutes) * 60)
        sleepTask = Task {
            try? await Task.sleep(for: .seconds(Double(minutes) * 60))
            guard !Task.isCancelled else { return }
            player?.pause()
            saveProgress()
            sleepEndsAt = nil
        }
    }

    private func cancelSleep() {
        sleepTask?.cancel()
        sleepTask = nil
        sleepEndsAt = nil
        sleepAtEnd = false
    }

    private static func speedLabel(_ s: Double) -> String {
        s == s.rounded() ? "\(Int(s))×" : String(format: "%g×", s)
    }

    @AppStorage(SubtitleStyle.positionKey) private var subPosition = "low"

    private var subtitleOverlay: some View {
        VStack {
            Spacer()
            if !subText.isEmpty {
                StyledSubtitleText(text: subText)
                    .padding(.horizontal, 24)
                    .padding(.bottom, SubtitleStyle.bottomPadding(subPosition))
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Gesture feedback

    private func showHUD(_ g: PlayerGesture) {
        hud = g
        hudTask?.cancel()
        if g == .boost(true) { return }                 // stays while you hold
        hudTask = Task {
            try? await Task.sleep(for: .milliseconds(g == .boost(false) ? 100 : 800))
            guard !Task.isCancelled else { return }
            hud = nil
        }
    }

    @ViewBuilder
    private var gestureHUD: some View {
        if let hud, hud != .boost(false) {
            VStack {
                HStack(spacing: 8) {
                    switch hud {
                    case .seek(let s):
                        Image(systemName: s < 0 ? "gobackward.10" : "goforward.10")
                        Text(s < 0 ? "Back 10 seconds" : "Forward 10 seconds")
                    case .brightness(let v):
                        Image(systemName: "sun.max.fill")
                        ProgressView(value: Double(v)).frame(width: 90).tint(.white)
                    case .volume(let v):
                        Image(systemName: v == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        ProgressView(value: Double(v)).frame(width: 90).tint(.white)
                    case .boost:
                        Image(systemName: "forward.fill")
                        Text("2× speed")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.black.opacity(0.6), in: Capsule())
                .padding(.top, 70)
                Spacer()
            }
            .allowsHitTesting(false)
            .transition(.opacity)
            .accessibilityHidden(true)
        }
    }

    private func failureCard(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
            .padding(.bottom, 24)
    }

    // Skip intro (first minutes of an episode) and skip to next (last 90 seconds).
    private var isEpisode: Bool { current.context.item.type == "series" && current.context.episodeLabel != nil }
    private var showSkipIntro: Bool { isEpisode && pos > 5 && pos < 360 && !finished && !useAlt }
    private var showSkipToNext: Bool {
        current.context.nextEpisode != nil && dur > 0 && dur - pos < 90 && dur - pos > 0 && !showUpNext && !finished
    }

    /// Movies and last episodes: a button over the closing credits that finishes the title.
    private var showSkipCredits: Bool {
        showSkipCreditsSetting && current.context.nextEpisode == nil && dur > 0 && dur - pos < 150 && dur - pos > 0
            && !finished && !useAlt
    }

    @ViewBuilder
    private var skipRow: some View {
        if showSkipIntro || showSkipToNext || showSkipCredits {
            HStack {
                Spacer()
                if showSkipToNext {
                    Button { player?.pause(); handleEnd() } label: { Label("Next episode", systemImage: "forward.end.fill") }
                        .buttonStyle(.borderedProminent)
                } else if showSkipCredits {
                    Button { player?.pause(); handleEnd(); dismiss() } label: { Label("Skip credits", systemImage: "forward.end.fill") }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        Task { await player?.seek(to: CMTime(seconds: pos + Double(skipIntro), preferredTimescale: 600)) }
                    } label: { Label("Skip intro", systemImage: "forward.fill") }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 100)
        }
    }

    private var upNextCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Up next").font(.caption).foregroundStyle(.secondary)
            if let ep = current.context.nextEpisode {
                Text(spoilerGuard ? ep.episodeNumberOnly : ep.episodeTitle).font(.headline).lineLimit(2)
            }
            if findingNext {
                HStack(spacing: 8) { ProgressView(); Text("Finding a stream…").font(.footnote) }
            } else if let next = upNext {
                if autoPlayNext { Text("Starting in \(countdown)s").font(.footnote).foregroundStyle(.secondary) }
                HStack {
                    Button("Play now") { play(next) }.buttonStyle(.borderedProminent)
                    Button("Cancel") { cancelUpNext() }.buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .padding(.bottom, 90)
    }

    /// "English", or "English 1", "English 2" when a language repeats.
    private var subtitleLabels: [String] {
        let names = current.subtitles.map(\.languageName)
        let totals = Dictionary(names.map { ($0, 1) }, uniquingKeysWith: +)
        var seen: [String: Int] = [:]
        return names.map { name in
            seen[name, default: 0] += 1
            return (totals[name] ?? 1) > 1 ? "\(name) \(seen[name]!)" : name
        }
    }

    // MARK: Playback

    private func start(_ item: PlayItem) {
        teardown()
        current = item
        finished = false
        lastSave = item.startAt
        pos = 0; dur = 0; failure = nil
        cues = []; selectedSub = nil; subText = ""
        audioGroup = nil; legibleGroup = nil; selectedAudio = nil; selectedEmbedded = nil
        showUpNext = false; upNext = nil; findingNext = false

        // Formats AVPlayer can't open go straight to the extra player when it's installed.
        if AltEngine.needs(item.url) && AltEngine.isAvailable {
            useAlt = true
            player = nil
            return
        }
        useAlt = false

        let p = AVPlayer(url: item.url)
        p.defaultRate = Float(speed)
        player = p
        SubtitleStyle.applyEmbedded(to: p.currentItem)
        WatchTogether.shared.attach(p)

        timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                                                 queue: .main) { time in
            let s = time.seconds
            pos = s
            if let d = p.currentItem?.duration.seconds, d.isFinite, d > 0 { dur = d }
            subText = cues.first { $0.start <= s && s < $0.end }?.text ?? ""
            if s - lastSave >= 5 { lastSave = s; saveProgress() }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                             object: p.currentItem, queue: .main) { _ in
            handleEnd()
        }
        statusObserver = p.currentItem?.observe(\.status, options: [.new]) { avItem, _ in
            Task { @MainActor in
                switch avItem.status {
                case .readyToPlay:
                    await loadEmbeddedTracks(avItem)
                case .failed:
                    ErrorReporter.report("Playback failed: \(avItem.error?.localizedDescription ?? "unknown")", kind: "playback")
                    if AltEngine.isAvailable {
                        player?.pause()
                        useAlt = true
                    } else {
                        failure = "This file's format can't play in the built-in player. Pick another stream, or add the KSPlayer package (see the README) to play mkv and similar files."
                    }
                default:
                    break
                }
            }
        }

        Task {
            if item.startAt > 5 { await p.seek(to: CMTime(seconds: item.startAt, preferredTimescale: 600)) }
            p.play()
        }
        scrobble("start", progress: 0)
    }

    private func teardown() {
        if let o = timeObserver { player?.removeTimeObserver(o) }
        timeObserver = nil
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        endObserver = nil
        statusObserver?.invalidate()
        statusObserver = nil
        player?.pause()
    }

    private func finish() {
        nextTask?.cancel()
        sleepTask?.cancel()
        if !finished, player != nil {
            let pct = currentProgress()
            saveProgress()
            scrobble("stop", progress: pct)
            services.trackFinished(current.context, percent: pct)
        }
        teardown()
    }

    private func handleEnd() {
        guard !finished else { return }
        finished = true
        progress.clear(current.context.key)
        scrobble("stop", progress: 100)
        services.trackFinished(current.context, percent: 100)
        if sleepAtEnd { cancelSleep(); return }          // sleep timer: stop after this one
        guard current.context.nextEpisode != nil else { return }

        showUpNext = true; findingNext = true; upNext = nil; countdown = 6
        nextTask?.cancel()
        nextTask = Task {
            let next = await resolveNext(current)
            findingNext = false
            guard let next, !Task.isCancelled else { showUpNext = false; return }
            upNext = next
            guard autoPlayNext else { return }                // wait for "Play now"
            while countdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                countdown -= 1
            }
            play(next)
        }
    }

    private func play(_ next: PlayItem) {
        nextTask?.cancel()
        start(next)
    }

    private func cancelUpNext() {
        nextTask?.cancel()
        showUpNext = false
        upNext = nil
    }

    private func setSpeed(_ s: Double) {
        speed = s
        player?.defaultRate = Float(s)
        if player?.timeControlStatus == .playing { player?.rate = Float(s) }
    }

    // MARK: Tracks

    /// Audio languages and subtitles that are inside the file itself.
    private func loadEmbeddedTracks(_ avItem: AVPlayerItem) async {
        let asset = avItem.asset
        let audio = try? await asset.loadMediaSelectionGroup(for: .audible)
        let legible = try? await asset.loadMediaSelectionGroup(for: .legible)
        audioGroup = audio
        legibleGroup = legible
        if let audio { selectedAudio = avItem.currentMediaSelection.selectedMediaOption(in: audio) }
        if let legible { selectedEmbedded = avItem.currentMediaSelection.selectedMediaOption(in: legible) }
        applyLanguagePreferences(avItem)
    }

    /// Picks the audio and subtitle language saved in Account (or remembered from the last choice).
    private func applyLanguagePreferences(_ avItem: AVPlayerItem) {
        if audioLang != "auto", let g = audioGroup,
           let match = g.options.first(where: { LanguagePref.code($0.locale?.language.languageCode?.identifier) == audioLang }) {
            avItem.select(match, in: g)
            selectedAudio = match
        }
        guard subLang != "off", selectedSub == nil else { return }
        if let track = current.subtitles.first(where: { LanguagePref.code($0.lang) == subLang }) {
            selectSubtitle(track, remember: false)
        } else if let g = legibleGroup,
                  let match = g.options.first(where: { LanguagePref.code($0.locale?.language.languageCode?.identifier) == subLang
                                                       && !$0.hasMediaCharacteristic(.containsOnlyForcedSubtitles) }) {
            avItem.select(match, in: g)
            selectedEmbedded = match
        }
    }

    private func selectEmbedded(_ option: AVMediaSelectionOption, in group: AVMediaSelectionGroup) {
        selectedSub = nil; cues = []; subText = ""        // only one subtitle source at a time
        player?.currentItem?.select(option, in: group)
        selectedEmbedded = option
        if let code = LanguagePref.code(option.locale?.language.languageCode?.identifier) { subLang = code }
    }

    private func selectSubtitle(_ track: SubtitleTrack?, remember: Bool = true) {
        if remember { subLang = LanguagePref.code(track?.lang) ?? "off" }
        selectedSub = track
        subText = ""
        if let g = legibleGroup {                          // turn off the file's own subtitles
            player?.currentItem?.select(nil, in: g)
            selectedEmbedded = nil
        }
        guard let track else { cues = []; return }
        Task {
            if track.url.isEmpty, let fileID = track.fileID {
                // OpenSubtitles tracks get their download link only when picked.
                guard let url = await services.openSubtitles.download(fileID: fileID) else { return }
                if selectedSub == track { cues = await SubtitleLoader.load(url: url) }
            } else {
                cues = await SubtitleLoader.load(track)
            }
        }
    }

    // MARK: Progress

    private func saveProgress() {
        guard let player, let item = player.currentItem else { return }
        let d = item.duration.seconds
        guard d.isFinite, d > 0 else { return }
        progress.update(current.context, position: player.currentTime().seconds, duration: d)
    }

    /// 0–100 based on the current position.
    private func currentProgress() -> Double {
        guard let player, let item = player.currentItem else { return 0 }
        let d = item.duration.seconds
        guard d.isFinite, d > 0 else { return 0 }
        return player.currentTime().seconds / d * 100
    }

    private func scrobble(_ action: String, progress pct: Double) {
        guard trakt.isSignedIn, !PrivateMode.isOn else { return }
        let target = ScrobbleTarget(type: current.context.item.type, id: current.context.key)
        Task { await trakt.scrobble(action, target: target, progress: pct) }
    }
}
