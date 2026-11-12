import SwiftUI
import Combine

// MARK: - Small shared pieces

struct ConnectedRow: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "checkmark.seal.fill").foregroundStyle(.green)
    }
}

struct ErrorText: View {
    let message: String?
    var body: some View {
        if let message { Text(message).font(.footnote).foregroundStyle(.red) }
    }
}

struct ConfigHint: View {
    let show: Bool
    let text: String
    var body: some View {
        if show { Text(text).font(.footnote).foregroundStyle(.secondary) }
    }
}

/// "Go to this link and enter this code" with a cancel button.
struct DeviceCodeRows: View {
    let code: String
    let urlString: String
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Go to the link below and enter this code:").font(.subheadline)
            Text(code)
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .textSelection(.enabled)
            if let url = URL(string: urlString) { Link(urlString, destination: url) }
            HStack(spacing: 8) {
                ProgressView()
                Text("Waiting for approval…").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        Button("Cancel", action: onCancel)
    }
}

// MARK: - Appearance

struct AppearanceSection: View {
    @AppStorage("appearance") private var appearance = AppearanceMode.system.rawValue

    var body: some View {
        CollapsibleSection("Appearance") {
            Picker("Theme", selection: $appearance) {
                ForEach(AppearanceMode.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            Text("System follows your phone's setting. Light and Dark override it.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Playback settings

struct PlaybackSettingsSection: View {
    @AppStorage("preferredQuality") private var preferredQuality = 1080
    @AppStorage("skipIntroSeconds") private var skipIntro = 85
    @AppStorage("defaultSpeed") private var defaultSpeed = 1.0
    @AppStorage("preferredAudioLang") private var audioLang = "auto"
    @AppStorage("preferredSubLang") private var subLang = "off"
    @AppStorage("autoPlayNext") private var autoPlayNext = true
    @AppStorage("showSkipCredits") private var showSkipCredits = true
    @AppStorage(PlayerSurface.gesturesKey) private var gestures = true
    @AppStorage(SpoilerGuard.key) private var spoilerGuard = false

    var body: some View {
        CollapsibleSection("Playback") {
            Picker("Preferred quality", selection: $preferredQuality) {
                Text("Best available").tag(0)
                Text("4K").tag(2160)
                Text("1080p").tag(1080)
                Text("720p").tag(720)
            }
            Picker("Skip intro jumps", selection: $skipIntro) {
                ForEach([60, 75, 85, 90, 120], id: \.self) { Text("\($0) seconds").tag($0) }
            }
            Picker("Default speed", selection: $defaultSpeed) {
                ForEach([0.75, 1.0, 1.25, 1.5], id: \.self) { Text(String(format: "%g×", $0)).tag($0) }
            }
            Picker("Audio language", selection: $audioLang) {
                Text("File default").tag("auto")
                ForEach(LanguagePref.choices, id: \.code) { Text($0.name).tag($0.code) }
            }
            Picker("Subtitles", selection: $subLang) {
                Text("Off").tag("off")
                ForEach(LanguagePref.choices, id: \.code) { Text($0.name).tag($0.code) }
            }
            Toggle("Auto-play next episode", isOn: $autoPlayNext)
            Toggle("Show Skip credits button", isOn: $showSkipCredits)
            Toggle("Spoiler guard", isOn: $spoilerGuard)
            if spoilerGuard {
                Text("Hides the titles of episodes you haven't watched yet. Episode numbers still show.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Toggle("Player gestures", isOn: $gestures)
            if gestures {
                Text("Double-tap the left or right side to skip 10 seconds. Drag up or down on the left edge for brightness and on the right edge for volume. Press and hold to play at 2×.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Text("Picking an audio or subtitle language in the player is remembered for next time. Streams are sorted by this quality, and \"Play best stream\" picks the top one.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Downloads

struct DownloadsSection: View {
    @EnvironmentObject var downloads: DownloadManager
    @AppStorage("downloadWiFiOnly") private var wifiOnly = true
    @AppStorage(DownloadManager.autoDeleteKey) private var autoDelete = false
    @State private var confirmDelete = false

    var body: some View {
        CollapsibleSection("Downloads") {
            Toggle("Download on Wi-Fi only", isOn: $wifiOnly)
            Toggle("Delete after I finish watching", isOn: $autoDelete)
            if autoDelete {
                Text("A download is removed when you watch past 90% of it and close the player. You can download it again any time.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if downloads.doneCount > 0 {
                Text("\(downloads.doneCount) saved · \(DownloadManager.sizeText(downloads.totalBytes))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !downloads.entries.isEmpty {
                Button("Delete all downloads", role: .destructive) { confirmDelete = true }
            }
            Text("Tap the download button next to a stream. Saved files stay on this device and aren't backed up.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .confirmationDialog("Delete every download?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) { downloads.removeAll() }
        }
    }
}

// MARK: - Trakt

struct TraktSection: View {
    @EnvironmentObject var trakt: TraktAuth
    @State private var task: Task<Void, Never>?

    var body: some View {
        CollapsibleSection("Trakt") {
            if trakt.isSignedIn {
                ConnectedRow(text: "Signed in")
                Text("Finished titles are marked watched on Trakt, and your watchlist shows on Browse.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Sign out", role: .destructive) { trakt.signOut() }
            } else if let code = trakt.deviceCode {
                DeviceCodeRows(code: code.user_code, urlString: code.verification_url) {
                    task?.cancel(); task = nil
                }
            } else {
                Button("Sign in with Trakt") {
                    task = Task { await trakt.signIn(); task = nil }
                }
                ConfigHint(show: !TraktConfig.isConfigured,
                           text: "Add your Trakt Client ID and Secret in TraktClient.swift to enable sign-in.")
            }
            ErrorText(message: trakt.error)
        }
    }
}

// MARK: - Simkl

struct SimklSection: View {
    @EnvironmentObject var services: Services
    @State private var task: Task<Void, Never>?

    var body: some View {
        let simkl = services.simkl
        CollapsibleSection("Simkl") {
            if simkl.isSignedIn {
                ConnectedRow(text: "Signed in")
                Text("Finished titles are added to your Simkl history.").font(.footnote).foregroundStyle(.secondary)
                Button("Sign out", role: .destructive) { simkl.signOut() }
            } else if let pin = simkl.pin {
                DeviceCodeRows(code: pin.user_code, urlString: pin.verification_url) {
                    task?.cancel(); task = nil
                }
            } else {
                Button("Sign in with Simkl") { task = Task { await simkl.signIn(); task = nil } }
                ConfigHint(show: !simkl.isConfigured, text: "Add your Simkl Client ID in Config.swift to enable sign-in.")
            }
            ErrorText(message: simkl.error)
        }
    }
}

// MARK: - AniList and MyAnimeList

struct AniListSection: View {
    @EnvironmentObject var services: Services

    var body: some View {
        let a = services.anilist
        CollapsibleSection("AniList") {
            if a.isSignedIn {
                ConnectedRow(text: "Signed in")
                Text("Anime you finish update your AniList progress.").font(.footnote).foregroundStyle(.secondary)
                Button("Sign out", role: .destructive) { a.signOut() }
            } else {
                Button { Task { await a.signIn() } } label: {
                    if a.busy { ProgressView() } else { Text("Sign in with AniList") }
                }
                .disabled(a.busy)
                ConfigHint(show: !a.isConfigured, text: "Add your AniList Client ID in Config.swift. Redirect URL: nuvigo://anilist")
            }
            ErrorText(message: a.error)
        }
    }
}

struct MALSection: View {
    @EnvironmentObject var services: Services

    var body: some View {
        let m = services.mal
        CollapsibleSection("MyAnimeList") {
            if m.isSignedIn {
                ConnectedRow(text: "Signed in")
                Text("Anime you finish update your MyAnimeList progress.").font(.footnote).foregroundStyle(.secondary)
                Button("Sign out", role: .destructive) { m.signOut() }
            } else {
                Button { Task { await m.signIn() } } label: {
                    if m.busy { ProgressView() } else { Text("Sign in with MyAnimeList") }
                }
                .disabled(m.busy)
                ConfigHint(show: !m.isConfigured, text: "Add your MyAnimeList Client ID in Config.swift. Redirect URL: nuvigo://mal")
            }
            ErrorText(message: m.error)
        }
    }
}

// MARK: - Jellyfin and Plex

struct JellyfinSection: View {
    @EnvironmentObject var services: Services
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        let jf = services.jellyfin
        CollapsibleSection("Jellyfin") {
            if let s = jf.session {
                ConnectedRow(text: "\(s.username) on \(s.server)")
                Text("Your libraries show up as cards on Browse and in Search.").font(.footnote).foregroundStyle(.secondary)
                Button("Disconnect", role: .destructive) { jf.signOut() }
            } else {
                TextField("Server address", text: $server)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Password", text: $password)
                Button {
                    Task {
                        await jf.signIn(server: server, username: username, password: password)
                        if jf.isConnected { password = "" }
                    }
                } label: {
                    if jf.busy { ProgressView() } else { Text("Connect") }
                }
                .disabled(server.isEmpty || username.isEmpty || jf.busy)
            }
            ErrorText(message: jf.error)
        }
    }
}

struct PlexSection: View {
    @EnvironmentObject var services: Services
    @State private var task: Task<Void, Never>?

    var body: some View {
        let plex = services.plex
        CollapsibleSection("Plex") {
            if let s = plex.session {
                ConnectedRow(text: "Connected to \(s.serverName)")
                Text("Your libraries show up as cards on Browse and in Search.").font(.footnote).foregroundStyle(.secondary)
                Button("Disconnect", role: .destructive) { plex.signOut() }
            } else if let pin = plex.pin {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Approve NuviGo on plex.tv, then come back here.").font(.subheadline)
                    Link("Open plex.tv to sign in", destination: pin.authURL)
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Waiting for approval…").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                Button("Cancel") { task?.cancel(); task = nil }
            } else {
                Button("Sign in with Plex") { task = Task { await plex.signIn(); task = nil } }
            }
            ErrorText(message: plex.error)
        }
    }
}

// MARK: - Debrid

struct DebridSection: View {
    var body: some View {
        ForEach(DebridService.allCases) { DebridServiceSection(service: $0) }
    }
}

struct DebridServiceSection: View {
    let service: DebridService
    @EnvironmentObject var debrid: DebridAuth
    @State private var token = ""

    var body: some View {
        CollapsibleSection(LocalizedStringKey(service.name)) {
            if debrid.isConnected(service) {
                let account = debrid.accounts[service]
                ConnectedRow(text: account?.username.map { "Connected as \($0)" } ?? "Connected")
                if let account, !account.isPremium {
                    Text("This account isn't premium, so torrents may not play.")
                        .font(.footnote).foregroundStyle(.orange)
                }
                Text("Torrent streams from your addons can play through this account.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Disconnect", role: .destructive) { debrid.disconnect(service) }
            } else {
                SecureField("API token", text: $token)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button {
                    Task {
                        await debrid.connect(service, token: token)
                        if debrid.isConnected(service) { token = "" }
                    }
                } label: {
                    if debrid.checking == service { ProgressView() } else { Text("Connect") }
                }
                .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || debrid.checking != nil)
                Text("\(service.tokenHelp) It stays in your Keychain.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - OpenSubtitles and TMDB

struct OpenSubtitlesSection: View {
    @EnvironmentObject var services: Services
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        let os = services.openSubtitles
        CollapsibleSection("OpenSubtitles") {
            if !os.hasKey {
                APIKeyEntry(placeholder: "Your OpenSubtitles API key", linkTitle: "Get a free key at opensubtitles.com",
                            link: "https://www.opensubtitles.com/consumers", onSave: { os.saveKey($0) })
            } else if let s = os.session {
                ConnectedRow(text: "Signed in as \(s.username)")
                Text("Subtitles in your phone's languages are added to the player's subtitle menu.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Sign out", role: .destructive) { os.signOut() }
            } else {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Password", text: $password)
                Button {
                    Task {
                        await os.signIn(username: username, password: password)
                        if os.isSignedIn { password = "" }
                    }
                } label: {
                    if os.busy { ProgressView() } else { Text("Sign in") }
                }
                .disabled(username.isEmpty || password.isEmpty || os.busy)
            }
            if os.hasKey { Button("Remove key", role: .destructive) { os.removeKey() } }
            ErrorText(message: os.error)
        }
    }
}

/// Field, save button and "get a key" link, shown until the person has added their own key.
struct APIKeyEntry: View {
    let placeholder: LocalizedStringKey
    let linkTitle: LocalizedStringKey
    let link: String
    let onSave: (String) -> Void
    @State private var text = ""
    @Environment(\.openURL) private var openURL

    var body: some View {
        SecureField(placeholder, text: $text)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
        Button("Save key") { onSave(text); text = "" }
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        Button(linkTitle) { if let u = URL(string: link) { openURL(u) } }
    }
}

struct TMDBSection: View {
    @EnvironmentObject var services: Services

    var body: some View {
        let t = services.tmdb
        CollapsibleSection("TMDB") {
            if !t.hasKey {
                APIKeyEntry(placeholder: "Your TMDB API key", linkTitle: "Get a free key at themoviedb.org",
                            link: "https://www.themoviedb.org/settings/api", onSave: { t.saveKey($0) })
            } else if t.isSignedIn {
                ConnectedRow(text: "Signed in")
                Text("Rate titles from their detail screen. Missing posters and descriptions fill in automatically.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Sign out", role: .destructive) { t.signOut() }
            } else {
                Button { Task { await t.signIn() } } label: {
                    if t.busy { ProgressView() } else { Text("Sign in with TMDB") }
                }
                .disabled(t.busy)
                Text("Missing posters and descriptions already fill in from TMDB. Sign in to rate titles too.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if t.hasKey { Button("Remove key", role: .destructive) { t.removeKey() } }
            ErrorText(message: t.error)
        }
    }
}

// MARK: Reset to default

/// Puts every customizable option back to its factory value. Signing in, linked accounts,
/// addons, watch history and the watched list are not touched.
struct ResetDefaultsSection: View {
    @State private var confirm = false

    var body: some View {
        Button { confirm = true } label: {
            BottomRowLabel(icon: "arrow.counterclockwise", title: "Reset to default",
                           caption: "Resets appearance, playback, download options, hidden ratings and card order. Your account, addons and watch history stay.",
                           tint: .red)
        }
        .confirmationDialog("Reset all settings to default?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Reset to default", role: .destructive) { Self.resetAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This puts every customized option back to its original value.")
        }
    }

    /// Defaults are written out rather than removed, so the change also syncs to other devices.
    static func resetAll() {
        let d = UserDefaults.standard
        d.set(AppearanceMode.system.rawValue, forKey: "appearance")
        d.set(1080, forKey: "preferredQuality")
        d.set(85, forKey: "skipIntroSeconds")
        d.set(1.0, forKey: "defaultSpeed")
        d.set(true, forKey: "downloadWiFiOnly")
        d.set("", forKey: "dashboardOrder")
        d.set("", forKey: "hiddenRatings")
        d.set("auto", forKey: "preferredAudioLang")
        d.set("off", forKey: "preferredSubLang")
        d.set(true, forKey: "autoPlayNext")
        d.set(true, forKey: "showSkipCredits")
        d.set(true, forKey: PrivacyKeys.hideInSwitcher)
    }
}

// MARK: Hide by rating

struct ContentRatingsSection: View {
    @EnvironmentObject var filter: ContentFilter

    var body: some View {
        CollapsibleSection("Hide by rating") {
            ForEach(RatingClass.allCases) { c in
                Toggle("Hide \(c.rawValue)", isOn: Binding(get: { filter.isHiddenClass(c) },
                                                           set: { filter.setHidden(c, $0) }))
            }
        } footer: {
            Text(Ratings.isConfigured
                 ? "Titles with a hidden rating disappear from every screen. TV ratings count as the nearest movie rating: TV-Y/TV-G as G, TV-PG as PG, TV-14 as PG-13, TV-MA as R."
                 : "Add your free OMDb key in the OMDb ratings section below so NuviGo can look up ratings. Until then nothing can be hidden.")
        }
    }
}
