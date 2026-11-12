import SwiftUI
import Combine
import CoreSpotlight
import AVFoundation

@main
struct NuviGoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AddonStore()
    @StateObject private var trakt = TraktAuth()
    @StateObject private var progress = ProgressStore()
    @StateObject private var debrid = DebridAuth()
    @StateObject private var services = Services()
    @StateObject private var network = NetworkMonitor()
    @StateObject private var downloads = DownloadManager()
    @StateObject private var preloader = Preloader()
    @StateObject private var account = NuviAccount()
    @StateObject private var watched = WatchedStore()
    @StateObject private var subs = SubscriptionStore()
    @StateObject private var lock = AppLockManager()
    @State private var tab = 0
    /// True once a swipe has been judged sideways. Up and down scrolling is switched off until the finger lifts.
    @State private var swipeLocked = false
    /// How far the current horizontal swipe has moved; the whole page follows it.
    @State private var swipeDX: CGFloat = 0
    /// The page sliding in beside the current one during a swipe.
    @State private var dragTarget: Int? = nil
    /// Tabs that have been shown at least once. They stay alive afterwards, like a TabView keeps them.
    @State private var visited: Set<Int> = [0]
    /// True while a finished swipe is still animating, so a second swipe can't start on top of it.
    @State private var sliding = false
    /// Width of the page area, so swipes work in iPad split view too.
    @State private var pageWidth = UIScreen.main.bounds.width
    @StateObject private var profiles = ProfileStore()
    @ObservedObject private var deepLink = DeepLink.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = AppearanceMode.system.rawValue

    init() {
        // Bigger image cache, so posters you've seen still show offline.
        URLCache.shared = URLCache(memoryCapacity: 50_000_000, diskCapacity: 500_000_000)
        ResponseCache.prune()
        AltEngine.configure()
        SwitcherShield.shared.start()
        CrashListener.shared.start()
        EpisodeAlerts.shared.start()
        WatchTogether.shared.listen()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    /// Brings the widgets, Spotlight and episode alerts up to date with what's on the device now.
    private func refreshSystemSurfaces() {
        Task {
            await WidgetBridge.refresh(progress: progress, trakt: trakt)
            await EpisodeAlerts.shared.refresh(trakt: trakt)
        }
        SpotlightIndexer.reindex(progress: progress, watched: watched)
    }

    /// Opens a tab (respecting the subscription gate).
    private func openTab(_ new: Int) {
        guard new != tab else { return }
        guard new == 0 || new == 1 || subs.allow() else { return }
        tab = new
        visited.insert(new)
    }

    private static let tabInfo: [(title: LocalizedStringKey, icon: String)] = [
        ("Dashboard", "square.grid.2x2"), ("Search", "magnifyingglass"),
        ("Addons", "puzzlepiece.extension"), ("Account", "person.crop.circle"), ("Tips", "heart.fill"),
    ]

    @ViewBuilder private func page(_ i: Int) -> some View {
        switch i {
        case 0: BrowseView()
        case 1: SearchView()
        case 2: AddonsView()
        case 3: AccountView()
        default: TipsView()
        }
    }

    /// Where a page sits during a swipe: the current one follows the finger, the next one slides in beside it.
    private func pageOffset(_ i: Int, width: CGFloat) -> CGFloat {
        if i == tab { return dragTarget == nil ? swipeDX * 0.2 : swipeDX }
        if i == dragTarget { return swipeDX > 0 ? swipeDX - width : swipeDX + width }
        return 0
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.tabInfo.enumerated()), id: \.offset) { i, info in
                Button { openTab(i) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: info.icon).font(.system(size: 21))
                        Text(info.title).font(.caption2)
                    }
                    .foregroundStyle(tab == i ? Theme.accent : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(info.title)
                .accessibilityAddTraits(tab == i ? .isSelected : [])
            }
        }
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    /// The tab a swipe in this direction would land on: the neighbour in the tab bar, or nil at either end.
    private func neighbour(_ dx: CGFloat) -> Int? {
        let n = tab + (dx > 0 ? -1 : 1)
        return (0..<Self.tabInfo.count).contains(n) ? n : nil
    }

    /// Swipe right = the tab to the left in the bar, swipe left = the tab to its right.
    /// The page moves with your finger, and up/down scrolling is locked once the swipe is sideways.
    private var tabSwipe: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { v in
                guard !sliding else { return }
                let dx = v.translation.width, dy = v.translation.height
                if !swipeLocked {
                    guard abs(dx) > abs(dy) * 1.5 else { return }   // still looks like a vertical scroll
                    swipeLocked = true
                }
                let next = neighbour(dx)
                if dragTarget != next {
                    dragTarget = next
                    if let next { visited.insert(next) }
                }
                swipeDX = dx
            }
            .onEnded { v in
                guard !sliding else { return }
                defer { swipeLocked = false }
                guard swipeLocked else { return }
                let dx = v.translation.width
                let width = pageWidth
                guard abs(dx) > max(80, width * 0.25), let target = neighbour(dx) else {
                    withAnimation(.easeOut(duration: 0.2)) { swipeDX = 0 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { if swipeDX == 0 { dragTarget = nil } }
                    return
                }
                // Finish the slide, then make the new page the real current one.
                sliding = true
                withAnimation(.easeOut(duration: 0.2)) { swipeDX = dx > 0 ? width : -width }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    var t = Transaction(); t.disablesAnimations = true
                    withTransaction(t) {
                        openTab(target)
                        swipeDX = 0
                        dragTarget = nil
                        sliding = false
                    }
                }
            }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
            ZStack {
                ForEach(0..<Self.tabInfo.count, id: \.self) { i in
                    if visited.contains(i) {
                        let showing = i == tab || i == dragTarget
                        page(i)
                            .offset(x: pageOffset(i, width: pageWidth))
                            .opacity(showing ? 1 : 0)
                            .allowsHitTesting(i == tab && dragTarget == nil)
                            .accessibilityHidden(i != tab)
                            .zIndex(i == tab ? 1 : 0)
                    }
                }
            }
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { pageWidth = g.size.width }
                    .onChange(of: g.size.width) { _, w in pageWidth = w }
            })
            .scrollDisabled(swipeLocked)
            .simultaneousGesture(tabSwipe)
            .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
            .environmentObject(store)
            .environmentObject(trakt)
            .environmentObject(progress)
            .environmentObject(debrid)
            .environmentObject(services)
            .environmentObject(network)
            .environmentObject(downloads)
            .tint(Theme.accent)
            .preferredColorScheme((AppearanceMode(rawValue: appearance) ?? .system).scheme)
            .environmentObject(preloader)
            .environmentObject(account)
            .environmentObject(watched)
            .environmentObject(ContentFilter.shared)
            .environmentObject(subs)
            .environmentObject(lock)
            .environmentObject(profiles)
            .task {
                account.watched = watched
                profiles.progress = progress
                profiles.watched = watched
                progress.onFinished = { watched.mark($0) }
                await preloader.run(store: store, trakt: trakt, services: services, account: account, progress: progress)
                refreshSystemSurfaces()
            }
            .onOpenURL { deepLink.handle(url: $0) }
            .onContinueUserActivity(CSSearchableItemActionType) { deepLink.handle(spotlight: $0) }
            .onReceive(downloads.$entries) { DownloadLiveActivity.shared.sync($0) }
            .onChange(of: deepLink.tabRequest) { _, r in if let r { openTab(r.tab) } }
            .onChange(of: deepLink.searchRequest) { _, r in if r != nil { openTab(1) } }
            .fullScreenCover(item: $deepLink.item) { item in
                NavigationStack {
                    DetailView(item: item)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Close") { deepLink.item = nil }
                            }
                        }
                }
                .environmentObject(store).environmentObject(trakt).environmentObject(progress)
                .environmentObject(debrid).environmentObject(services).environmentObject(network)
                .environmentObject(downloads).environmentObject(watched).environmentObject(ContentFilter.shared)
                .environmentObject(subs).environmentObject(profiles).environmentObject(account)
                .tint(Theme.accent)
            }
            .onChange(of: scenePhase) { _, phase in
                // Push changes when leaving the app, and pick up changes from other devices when coming back.
                guard phase == .background || phase == .active, preloader.done else { return }
                Task { await account.sync(store: store, progress: progress) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { lock.lockIfNeeded() }
                if phase == .background || phase == .active, preloader.done { refreshSystemSurfaces() }
            }
            if preloader.done && subs.locked && subs.showPaywall {
                PaywallView()
                    .environmentObject(subs)
                    .preferredColorScheme((AppearanceMode(rawValue: appearance) ?? .system).scheme)
                    .transition(.opacity)
                    .zIndex(0.5)
            }
            if lock.locked {
                LockView()
                    .environmentObject(lock)
                    .preferredColorScheme((AppearanceMode(rawValue: appearance) ?? .system).scheme)
                    .zIndex(3)
            }
            if !preloader.done || preloader.refreshing {
                LaunchView(preloader: preloader)
                    .preferredColorScheme((AppearanceMode(rawValue: appearance) ?? .system).scheme)
                    .transition(.opacity)
                    .zIndex(1)
            }
            }
        }
    }
}
