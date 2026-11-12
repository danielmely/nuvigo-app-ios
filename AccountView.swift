import SwiftUI
import Combine

struct AccountView: View {
    @EnvironmentObject var account: NuviAccount

    /// Linking other accounts requires a NuviGo account. Until a server
    /// address is configured (Config.serverURL) nothing can be created, so
    /// the gate stays open to keep local testing possible.
    @EnvironmentObject var subs: SubscriptionStore
    private var canLink: Bool { account.email != nil || !account.isConfigured || subs.demoActive }

    var body: some View {
        NavigationStack {
            List {
                NuviAccountSection()

                if SubscriptionConfig.required { SubscriptionSection() }

                if !canLink { AccountPerksSection() }

                // Blurred and untouchable until a NuviGo account exists.
                Group {
                    AppearanceSection()
                    AppIconSection()
                    StatsLinkSection()
                    PlaybackSettingsSection()
                    SubtitleStyleSection()
                    EpisodeAlertsSection()
                    DownloadsSection()
                    ContentRatingsSection()
                    ProfilesSection()
                    PrivacySection()

                    // Watch history
                    TraktSection()
                    SimklSection()
                    AniListSection()
                    MALSection()

                    // Your own media servers
                    JellyfinSection()
                    PlexSection()

                    // Streaming and subtitles
                    if FeatureFlags.debridEnabled { DebridSection() }
                    OpenSubtitlesSection()
                    TMDBSection()
                    OMDbSection()
                }
                .blur(radius: canLink ? 0 : 9)
                .allowsHitTesting(canLink)
                .accessibilityHidden(!canLink)

                AccountBottomSection()
            }
            .scrollDisabled(!canLink)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
