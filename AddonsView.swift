import SwiftUI
import Combine

/// Where an addon sits in the list, most important first.
enum AddonTier: Int, CaseIterable, Identifiable {
    case essential, subtitles, servers, other
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .essential: return "Titles and streams"
        case .servers: return "Your servers"
        case .subtitles: return "Subtitles"
        case .other: return "Other"
        }
    }
    var level: String {
        switch self {
        case .essential: return "Essential"
        case .subtitles: return "Recommended"
        case .servers, .other: return "Optional"
        }
    }
    var blurb: String {
        switch self {
        case .essential: return "These provide the movies and shows, and the links to watch them. You need at least one."
        case .servers: return "Your own Jellyfin and Plex libraries."
        case .subtitles: return "Captions in your language."
        case .other: return "Anything else you've installed."
        }
    }
    var icon: String {
        switch self {
        case .essential: return "play.rectangle.fill"
        case .servers: return "server.rack"
        case .subtitles: return "captions.bubble.fill"
        case .other: return "puzzlepiece.extension"
        }
    }

    static func of(_ a: Addon) -> AddonTier {
        let names = Set(a.manifest.resources.map(\.name))
        if !a.manifest.catalogs.isEmpty || names.contains("stream") || names.contains("meta") { return .essential }
        if names.contains("subtitles") { return .subtitles }
        return .other
    }
}

struct AddonsView: View {
    @EnvironmentObject var store: AddonStore
    @EnvironmentObject var trakt: TraktAuth
    @EnvironmentObject var progress: ProgressStore
    @EnvironmentObject var services: Services
    @EnvironmentObject var preload: Preloader
    @EnvironmentObject var account: NuviAccount
    @State private var input = ""
    @State private var error: String?
    @State private var adding = false
    @State private var installing: Set<String> = []

    private func addons(in tier: AddonTier) -> [Addon] { store.addons.filter { AddonTier.of($0) == tier } }

    /// Things worth connecting that the person hasn't yet. A row with an address installs that official add-on in one tap;
    /// any other row opens the Account tab, where the service is set up.
    private struct Suggestion: Identifiable {
        let name: String
        let icon: String
        let blurb: LocalizedStringKey
        var installURL: String? = nil
        var id: String { name }
    }

    /// Stremio's own add-ons. Matched by their manifest id, so one already installed from anywhere is not suggested again.
    private func officialSuggestion(id: String, name: String, icon: String, blurb: LocalizedStringKey, url: String) -> Suggestion? {
        store.addons.contains(where: { $0.manifest.id == id }) ? nil
            : Suggestion(name: name, icon: icon, blurb: blurb, installURL: url)
    }

    private func suggestions(for tier: AddonTier) -> [Suggestion] {
        switch tier {
        case .essential:
            var out: [Suggestion] = []
            if let s = officialSuggestion(id: "com.linvo.cinemeta", name: "Cinemeta", icon: "film.stack",
                                          blurb: "Official catalogs, posters and descriptions for movies and shows.",
                                          url: "https://v3-cinemeta.strem.io/manifest.json") { out.append(s) }
            if let s = officialSuggestion(id: "org.stremio.watchhub", name: "WatchHub", icon: "play.tv",
                                          blurb: "Shows which services stream a title, like Netflix or Hulu.",
                                          url: "https://watchhub.strem.io/manifest.json") { out.append(s) }
            if !OMDbKey.hasOwn {
                out.append(Suggestion(name: "OMDb", icon: "star.bubble", blurb: "IMDb and Rotten Tomatoes ratings. Add a free key."))
            }
            if !services.tmdb.hasKey {
                out.append(Suggestion(name: "TMDB", icon: "photo.on.rectangle", blurb: "Better posters and descriptions, and rate titles."))
            }
            return out
        case .servers:
            var out: [Suggestion] = []
            if !services.plex.isConnected {
                out.append(Suggestion(name: "Plex", icon: "server.rack", blurb: "Watch your own Plex libraries here."))
            }
            if !services.jellyfin.isConnected {
                out.append(Suggestion(name: "Jellyfin", icon: "server.rack", blurb: "Watch your own Jellyfin libraries here."))
            }
            return out
        case .subtitles:
            if let s = officialSuggestion(id: "org.stremio.opensubtitlesv3", name: "OpenSubtitles", icon: "captions.bubble",
                                          blurb: "Official subtitles in many languages.",
                                          url: "https://opensubtitles-v3.strem.io/manifest.json") { return [s] }
            return []
        default:
            return []
        }
    }

    @ViewBuilder
    private func suggestionRow(_ s: Suggestion) -> some View {
        if let url = s.installURL {
            HStack(spacing: 12) {
                suggestionLabel(s)
                Spacer(minLength: 0)
                if installing.contains(url) {
                    ProgressView()
                } else {
                    Button("Install") { Task { await install(url) } }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        } else {
            Button { DeepLink.shared.openTab(3) } label: {
                HStack(spacing: 12) {
                    suggestionLabel(s)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .accessibilityHint("Opens Account to set it up")
        }
    }

    private func suggestionLabel(_ s: Suggestion) -> some View {
        Group {
            HStack(spacing: 12) {
                Image(systemName: s.icon)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 32)
                    .background(Theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(s.name).font(.headline).foregroundStyle(.primary)
                        Text("Suggested").font(.caption2.weight(.semibold)).foregroundStyle(Theme.accent)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Theme.accent.opacity(0.15), in: Capsule())
                    }
                    Text(s.blurb).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func install(_ url: String) async {
        installing.insert(url); error = nil
        defer { installing.remove(url) }
        do { try await store.add(url) } catch {
            self.error = error.localizedDescription
            ErrorReporter.report("Suggested add-on install failed: \(error.localizedDescription)", kind: "addon")
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if store.addons.isEmpty && services.folders.isEmpty {
                    Section("Installed") {
                        Text("No addons yet. Paste a manifest URL below.").foregroundStyle(.secondary)
                    }
                }

                ForEach(AddonTier.allCases) { tier in
                    let list = addons(in: tier)
                    let servers = tier == .servers ? services.folders : []
                    let suggested = suggestions(for: tier)
                    if !list.isEmpty || !servers.isEmpty || !suggested.isEmpty {
                        Section {
                            ForEach(list) { addon in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(addon.manifest.name).font(.headline)
                                    if let d = addon.manifest.description {
                                        Text(d).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                }
                            }
                            .onDelete { offsets in
                                let ids = offsets.map { list[$0].id }
                                store.remove(at: IndexSet(store.addons.indices.filter { ids.contains(store.addons[$0].id) }))
                            }
                            ForEach(servers) { f in
                                Label(f.title, systemImage: "server.rack")
                            }
                            ForEach(suggested) { suggestionRow($0) }
                        } header: {
                            HStack(spacing: 8) {
                                Image(systemName: tier.icon).font(.title3).foregroundStyle(Theme.accent)
                                Text(tier.title).font(.title3.weight(.bold))
                                Spacer()
                                Text(tier.level).font(.footnote.weight(.semibold))
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(tier == .essential ? Theme.accent.opacity(0.2) : Color.secondary.opacity(0.15), in: Capsule())
                            }
                            .textCase(nil)
                        } footer: {
                            Text(tier.blurb)
                        }
                    }
                }

                Section {
                    TextField("Paste addon URL", text: $input)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button {
                        Task { await add() }
                    } label: {
                        if adding { ProgressView() } else { Text("Install") }
                    }
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || adding)
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    NavigationLink { HowToInstallAddonsView() } label: {
                        Label("How to install add-ons", systemImage: "questionmark.circle")
                    }
                    NavigationLink { AddonDisclosuresView() } label: {
                        Label("Add-on Disclosures", systemImage: "exclamationmark.shield")
                    }
                } header: {
                    Text("Add an addon").font(.title3.weight(.bold)).textCase(nil)
                }

                Section {
                    ForEach(RecommendedVPN.picks) { vpn in
                        Link(destination: vpn.url) {
                            BottomRowLabel(icon: vpn.icon, title: LocalizedStringKey(vpn.name),
                                           caption: "\(vpn.tag). \(vpn.blurb)", external: true)
                        }
                    }
                } header: {
                    Text("Recommended VPNs").font(.title3.weight(.bold)).textCase(nil)
                } footer: {
                    Text("NuviGo doesn't include a VPN. These are independent services, so check each site for current prices. A VPN protects your connection. It isn't a way to do anything illegal, and the Add-on Disclosures still apply.")
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            // Pull down to reload everything, the same as the Dashboard. The page moves with your finger.
            .refreshable {
                await preload.refresh(store: store, trakt: trakt, services: services, account: account, progress: progress)
            }
        }
    }

    private func add() async {
        adding = true; error = nil
        defer { adding = false }
        do {
            try await store.add(input)
            input = ""
        } catch {
            self.error = error.localizedDescription
            ErrorReporter.report("Add-on install failed: \(error.localizedDescription)", kind: "addon")
        }
    }
}

struct HowToInstallAddonsView: View {
    private let steps: [(String, String)] = [
        ("Find the install link", "Open the website of the addon you want. Look for an Install, Configure or Manifest link. The address usually ends in manifest.json, or starts with stremio://."),
        ("Copy the link", "Press and hold the link, then choose Copy. If the site only has an Install button, long-press it and copy the link instead of opening it."),
        ("Paste it into NuviGo", "Come back to the Add-Ons tab, tap the address box under Add an addon and paste the link."),
        ("Tap Install", "NuviGo checks the addon and adds it to your Installed list. Its catalogs show up on the Dashboard and in Search."),
        ("Remove one later", "Swipe left on an addon in the Installed list to remove it.")
    ]

    var body: some View {
        List {
            Section {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(i + 1)")
                            .font(.footnote.weight(.bold))
                            .frame(width: 24, height: 24)
                            .background(Theme.accent.opacity(0.18), in: Circle())
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.0).font(.headline)
                            Text(s.1).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } footer: {
                Text("Only install addons from sources you trust. NuviGo doesn't provide any addons itself.")
            }
        }
        .navigationTitle("Installing add-ons")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AddonDisclosuresView: View {
    private let sections: [(String, String)] = [
        ("Our purpose", "NuviGo is a media organizer and player. It was built as an additional way for you to store, organize and watch media that you legally own or have the legal right to access. NuviGo does not provide, host, sell, license or distribute any movies, shows, music or other video content, and it does not provide any add-ons."),
        ("Add-ons are third party", "Add-ons are created and run by independent third parties. NuviGo is not affiliated with, and does not review, endorse, verify or control, any add-on or the content it points to. You decide what to install, and you are solely responsible for it. Installing an add-on does not mean NuviGo approves of it or of anything it offers."),
        ("We do not condone illegal use", "We do not condone, encourage or support the use of NuviGo to view, download, copy, share or distribute any material without the permission of its copyright owner. That includes piracy, torrenting or peer-to-peer sharing of copyrighted works, streaming from unlicensed sources, bypassing paywalls, digital rights management or regional restrictions, and any other activity that infringes copyright or other laws."),
        ("Your responsibility", "You are responsible for making sure that everything you add, stream, download or store with NuviGo is legal where you live. Laws differ between countries and regions. If you are unsure whether you have the right to access something, do not access it. You agree to use NuviGo only with content you own, content you are licensed to use, or content that is in the public domain or freely and lawfully available."),
        ("Enforcement", "If we become aware of, or reasonably suspect, that anyone is using NuviGo for illegal activity, including piracy, torrenting or any other unauthorized use of video material, we will immediately revoke their access, including any NuviGo account, and permanently ban them from NuviGo. We may do this without prior notice and at our sole discretion. Tips are voluntary one-time payments handled by Apple, and any refund request is subject to Apple's own policies."),
        ("Cooperation with rights holders", "We respond to valid notices from copyright owners and will cooperate with law enforcement and courts where we are legally required to. If you are a rights holder and believe NuviGo is being used to infringe your work, contact us at support@nuvigo.app and include enough information for us to look into it."),
        ("No warranty and no liability", "NuviGo is provided \"as is\" and \"as available\". We make no promises about any add-on, the availability, accuracy, quality or legality of any content, or that using NuviGo will be uninterrupted or error free. To the fullest extent the law allows, NuviGo and its owner are not liable for any loss, claim or legal consequence that results from your use of add-ons or content, or from your breach of this disclosure or the law."),
        ("Privacy", "NuviGo has no ads and no third-party trackers. If error reports are turned on in the Account tab, the app sends short anonymous messages about what failed, along with the app and iOS version, to help us fix bugs. They never include your account, watch history or links. Your watch history, settings and downloads stay on your device and, if you choose, in your own NuviGo account. We do not monitor what you watch. You can clear your data at any time from the Account tab."),
        ("Contact", "Questions about this disclosure, reports of misuse, and copyright notices can be sent to support@nuvigo.app. Please include enough detail for us to review your message."),
        ("Changes to this disclosure", "We may update this disclosure from time to time. Continuing to use NuviGo after a change means you accept the updated version. This disclosure is general information and is not legal advice. It is meant to be read together with our Terms of Use and Privacy Policy.")
    ]

    var body: some View {
        List {
            Section {
                Text("Last updated November 9, 2026").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(Array(sections.enumerated()), id: \.offset) { _, s in
                Section {
                    Text(s.1).font(.subheadline)
                } header: {
                    Text(s.0).font(.headline).textCase(nil)
                }
            }
            Section {
                Text("By installing an add-on or using NuviGo, you confirm that you have read and agree to this disclosure.").font(.footnote.weight(.semibold))
            }
        }
        .navigationTitle("Add-on Disclosures")
        .navigationBarTitleDisplayMode(.inline)
    }
}
