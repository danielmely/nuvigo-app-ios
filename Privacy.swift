import SwiftUI
import LocalAuthentication
import CryptoKit

// MARK: - Settings keys

enum PrivacyKeys {
    static let appLock = "appLockEnabled"
    static let hideInSwitcher = "hideInSwitcher"
    static let privateMode = "privateMode"
    static let profiles = "profilesJSON"
    static let activeProfile = "activeProfileID"
}

/// Private mode: nothing you watch is remembered. No progress, no Watched list, no Trakt/Simkl/AniList/MAL updates.
enum PrivateMode {
    static var isOn: Bool { UserDefaults.standard.bool(forKey: PrivacyKeys.privateMode) }
}

// MARK: - Profiles

struct Profile: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var kids: Bool
    var pinHash: String?            // SHA-256 of "id:PIN", never the PIN itself

    var hasPIN: Bool { pinHash != nil }
    static func hash(_ pin: String, id: String) -> String {
        SHA256.hash(data: Data("\(id):\(pin)".utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func check(_ pin: String) -> Bool { pinHash == nil || pinHash == Profile.hash(pin, id: id) }
}

/// Separate watch history per person. The first profile ("main") keeps the data the app already had;
/// others get their own copies of Continue watching and Already watched. A kids profile always hides
/// PG-13, R, NC-17 and Unrated titles on top of the Hide by rating switches.
@MainActor
final class ProfileStore: ObservableObject {
    static let mainID = "main"
    static let kidsHidden: Set<String> = ["PG-13", "R", "NC-17", "Unrated"]

    @Published private(set) var profiles: [Profile] = []
    @Published private(set) var activeID: String = ProfileStore.mainID

    var progress: ProgressStore?
    var watched: WatchedStore?

    init() {
        profiles = Self.stored()
        activeID = UserDefaults.standard.string(forKey: PrivacyKeys.activeProfile) ?? Self.mainID
        if !profiles.contains(where: { $0.id == activeID }) { activeID = Self.mainID }
    }

    var active: Profile { profiles.first { $0.id == activeID } ?? profiles[0] }

    // Read straight from UserDefaults so the stores can use these before this object exists.
    nonisolated static func stored() -> [Profile] {
        if let data = UserDefaults.standard.data(forKey: PrivacyKeys.profiles),
           let list = try? JSONDecoder().decode([Profile].self, from: data), !list.isEmpty { return list }
        return [Profile(id: mainID, name: "Main", kids: false, pinHash: nil)]
    }

    /// "" for the main profile, ".id" for the others. Added to the storage keys of per-person data.
    nonisolated static var suffix: String {
        let id = UserDefaults.standard.string(forKey: PrivacyKeys.activeProfile) ?? mainID
        return id == mainID ? "" : "." + id
    }

    nonisolated static var activeIsKids: Bool {
        let id = UserDefaults.standard.string(forKey: PrivacyKeys.activeProfile) ?? mainID
        return stored().first { $0.id == id }?.kids ?? false
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) { UserDefaults.standard.set(data, forKey: PrivacyKeys.profiles) }
    }

    func add(name: String, kids: Bool, pin: String?) {
        let id = UUID().uuidString.prefix(8).lowercased()
        profiles.append(Profile(id: String(id), name: name, kids: kids, pinHash: pin.map { Profile.hash($0, id: String(id)) }))
        save()
    }

    func setPIN(_ pin: String?, for id: String) {
        guard let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[i].pinHash = pin.map { Profile.hash($0, id: id) }
        save()
    }

    func delete(_ id: String) {
        guard id != Self.mainID else { return }
        if activeID == id { switchTo(Self.mainID) }
        profiles.removeAll { $0.id == id }
        UserDefaults.standard.removeObject(forKey: "watchProgress." + id)
        UserDefaults.standard.removeObject(forKey: "watchedItems." + id)
        UserDefaults.standard.removeObject(forKey: "watchedHidden." + id)
        save()
    }

    /// The caller has already checked the PIN.
    func switchTo(_ id: String) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeID = id
        UserDefaults.standard.set(id, forKey: PrivacyKeys.activeProfile)
        progress?.reload()
        watched?.reload()
        ContentFilter.shared.profileChanged()
    }
}

// MARK: - App lock

@MainActor
final class AppLockManager: ObservableObject {
    @Published var locked: Bool
    @Published var failed = false
    private var asking = false

    init() { locked = UserDefaults.standard.bool(forKey: PrivacyKeys.appLock) }

    var enabled: Bool { UserDefaults.standard.bool(forKey: PrivacyKeys.appLock) }

    func lockIfNeeded() { if enabled { locked = true } }

    /// Face ID, Touch ID or the device passcode.
    func unlock() async {
        guard locked, !asking else { return }
        asking = true; failed = false
        defer { asking = false }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { locked = false; return }  // no passcode set: nothing to ask
        do {
            if try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock NuviGo") { locked = false }
        } catch { failed = true }
    }

    /// Asks once before switching the lock on, so you can't lock yourself out.
    func canEnable() async -> Bool {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return false }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Turn on NuviGo lock")) ?? false
    }
}

struct LockView: View {
    @EnvironmentObject var lock: AppLockManager
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            (scheme == .dark ? Color(red: 54/255, green: 58/255, blue: 67/255) : Color.white).ignoresSafeArea()
            VStack(spacing: 18) {
                if let mark = LogoData.mark { Image(uiImage: mark).resizable().scaledToFit().frame(width: 84, height: 84) }
                Text("NuviGo is locked").font(.title2.bold())
                Button { Task { await lock.unlock() } } label: {
                    Label("Unlock", systemImage: "faceid").frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                if lock.failed { Text("Couldn't unlock. Try again.").font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .task { await lock.unlock() }
    }
}

/// Blurs the app the moment it stops being active, so the app switcher snapshot shows a blur instead of
/// your screen. Done in UIKit on the notification itself because a SwiftUI overlay can arrive too late
/// for the snapshot.
@MainActor
final class SwitcherShield {
    static let shared = SwitcherShield()
    private let tag = 9911
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.show() }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private var windows: [UIWindow] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
    }

    private func show() {
        guard (UserDefaults.standard.object(forKey: PrivacyKeys.hideInSwitcher) as? Bool) ?? true else { return }
        for w in windows where w.viewWithTag(tag) == nil {
            let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
            blur.tag = tag
            blur.frame = w.bounds
            blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            if let mark = LogoData.mark {
                let iv = UIImageView(image: mark)
                iv.contentMode = .scaleAspectFit
                iv.frame = CGRect(x: 0, y: 0, width: 84, height: 84)
                iv.center = CGPoint(x: blur.bounds.midX, y: blur.bounds.midY)
                iv.autoresizingMask = [.flexibleTopMargin, .flexibleBottomMargin, .flexibleLeftMargin, .flexibleRightMargin]
                blur.contentView.addSubview(iv)
            }
            w.addSubview(blur)
        }
    }

    private func hide() {
        for w in windows { w.viewWithTag(tag)?.removeFromSuperview() }
    }
}

// MARK: - Account sections

struct PrivacySection: View {
    @EnvironmentObject var lock: AppLockManager
    @AppStorage(PrivacyKeys.appLock) private var appLock = false
    @AppStorage(PrivacyKeys.hideInSwitcher) private var hideInSwitcher = true
    @AppStorage(PrivacyKeys.privateMode) private var privateMode = false
    @AppStorage(ErrorReporter.enabledKey) private var sendReports = true
    @State private var note: String?

    var body: some View {
        CollapsibleSection("Privacy") {
            Toggle("Lock NuviGo", isOn: Binding(
                get: { appLock },
                set: { on in
                    if on { Task { if await lock.canEnable() { appLock = true; note = nil } else { note = "Set a passcode or Face ID on this iPhone first." } } }
                    else { appLock = false }
                }))
            Toggle("Hide in app switcher", isOn: $hideInSwitcher)
            Toggle("Private mode", isOn: $privateMode)
            Toggle("Send anonymous error reports", isOn: $sendReports)
            if let note { Text(note).font(.footnote).foregroundStyle(.red) }
        } footer: {
            Text("Lock asks for Face ID or your passcode every time you open NuviGo. Private mode doesn't save progress or watch history and doesn't update Trakt, Simkl, AniList or MyAnimeList. Error reports are short, anonymous messages (what failed, app and iOS version) that help us fix bugs. They never include your account, watch history or links. NuviGo has no ads and no third-party trackers. Downloads are stored protected on this iPhone and left out of backups.")
        }
    }
}

struct ProfilesSection: View {
    @EnvironmentObject var profiles: ProfileStore

    var body: some View {
        CollapsibleSection("Profiles") {
            NavigationLink {
                ProfilesView()
            } label: {
                LabeledContent("Profile") {
                    HStack(spacing: 6) {
                        Text(profiles.active.name)
                        if profiles.active.kids { Image(systemName: "face.smiling").foregroundStyle(.secondary) }
                        if profiles.active.hasPIN { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        } footer: {
            Text("Each profile keeps its own Continue watching and Already watched. Kids profiles always hide PG-13, R, NC-17 and unrated titles. Set a PIN on the Main profile so kids can't switch back to it.")
        }
    }
}

struct ProfilesView: View {
    @EnvironmentObject var profiles: ProfileStore
    @State private var asking: Profile?
    @State private var pin = ""
    @State private var wrong = false
    @State private var adding = false
    @State private var settingPIN: Profile?

    var body: some View {
        List {
            Section {
                ForEach(profiles.profiles) { p in
                    Button {
                        if p.id == profiles.activeID { return }
                        if p.hasPIN { pin = ""; wrong = false; asking = p } else { profiles.switchTo(p.id) }
                    } label: {
                        HStack {
                            Image(systemName: p.kids ? "face.smiling" : "person.circle").frame(width: 28)
                            Text(p.name)
                            if p.hasPIN { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if p.id == profiles.activeID { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                        }
                    }
                    .foregroundStyle(.primary)
                    .swipeActions {
                        if p.id != ProfileStore.mainID {
                            Button("Delete", role: .destructive) { profiles.delete(p.id) }
                        }
                        Button(p.hasPIN ? "Remove PIN" : "Set PIN") {
                            if p.hasPIN { profiles.setPIN(nil, for: p.id) } else { pin = ""; settingPIN = p }
                        }.tint(.indigo)
                    }
                }
            } footer: {
                Text("Swipe a profile to set or remove its PIN" + (profiles.profiles.count > 1 ? " or delete it." : "."))
            }
            Section { Button("Add profile") { adding = true } }
        }
        .navigationTitle("Profiles")
        .sheet(isPresented: $adding) { AddProfileView() }
        .alert("Enter PIN", isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } })) {
            SecureField("PIN", text: $pin).keyboardType(.numberPad)
            Button("Switch") {
                if let p = asking, p.check(pin) { profiles.switchTo(p.id) }
                else { wrong = true }
                asking = nil
            }
            Button("Cancel", role: .cancel) { asking = nil }
        } message: { Text(asking.map { "\($0.name) is protected." } ?? "") }
        .alert("Wrong PIN", isPresented: $wrong) { Button("OK", role: .cancel) {} }
        .alert("Set a PIN", isPresented: Binding(get: { settingPIN != nil }, set: { if !$0 { settingPIN = nil } })) {
            SecureField("4 to 8 digits", text: $pin).keyboardType(.numberPad)
            Button("Save") {
                if let p = settingPIN, (4...8).contains(pin.count), pin.allSatisfy(\.isNumber) { profiles.setPIN(pin, for: p.id) }
                settingPIN = nil
            }
            Button("Cancel", role: .cancel) { settingPIN = nil }
        } message: { Text(settingPIN.map { "People will need this to switch to \($0.name)." } ?? "") }
    }
}

struct AddProfileView: View {
    @EnvironmentObject var profiles: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kids = false
    @State private var usePIN = false
    @State private var pin = ""

    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (!usePIN || ((4...8).contains(pin.count) && pin.allSatisfy(\.isNumber)))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Toggle("Kids profile", isOn: $kids)
                Toggle("Protect with a PIN", isOn: $usePIN)
                if usePIN { SecureField("4 to 8 digits", text: $pin).keyboardType(.numberPad) }
            }
            .navigationTitle("New profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        profiles.add(name: name.trimmingCharacters(in: .whitespaces), kids: kids, pin: usePIN ? pin : nil)
                        dismiss()
                    }.disabled(!valid)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct ClearCacheSection: View {
    @State private var confirm = false

    var body: some View {
        Button { confirm = true } label: {
            BottomRowLabel(icon: "arrow.triangle.2.circlepath", title: "Clear cache",
                           caption: "Removes saved pictures, pages, ratings and stream lists. They download again next time.")
        }
        .confirmationDialog("Clear the cache?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Clear cache", role: .destructive) {
                URLCache.shared.removeAllCachedResponses()
                ResponseCache.clear()
                Ratings.clearCache()
                AddonClient.clearStreamCache()
                ContentFilter.shared.clearCache()
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Everything is fetched again the next time it's needed.") }
    }
}

struct ClearDataSection: View {
    @EnvironmentObject var progress: ProgressStore
    @EnvironmentObject var watched: WatchedStore
    @EnvironmentObject var downloads: DownloadManager
    @State private var confirm = false

    var body: some View {
        Button { confirm = true } label: {
            BottomRowLabel(icon: "trash", title: "Clear my data", tint: .red,
                           caption: "Removes this profile's watch history, progress and downloads. Your account, addons and settings stay.")
        }
        .confirmationDialog("Clear your data?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Clear my data", role: .destructive) {
                progress.clearAll()
                watched.clearAll()
                downloads.removeAll()
                StatsStore.shared.clearAll()
                RecentSearches.clear()
                SpotlightIndexer.removeAll()
                URLCache.shared.removeAllCachedResponses()
                ResponseCache.clear()
                ContentFilter.shared.clearCache()
                Ratings.clearCache()
                AddonClient.clearStreamCache()
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This can't be undone.") }
    }
}
