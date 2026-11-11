import Foundation
import CryptoKit

/// A NuviGo account on your own server: sign up, sign in, and keep addons, watch progress, settings
/// and linked logins in step across devices. Local data stays on the device if you sign out.
@MainActor
final class NuviAccount: ObservableObject {
    @Published private(set) var email: String?
    @Published private(set) var busy = false
    @Published private(set) var lastSync: Date?
    @Published var error: String?
    /// Linked logins (Trakt, debrid...) were replaced by synced ones; they load the next time the app opens.
    @Published var needsRestart = false

    private let tokenKey = "nuvigo.account.token"
    private let emailKey = "nuvigo.account.email"
    private var token: String?
    /// Set by the app so ratings and the watched list can sync too.
    weak var watched: WatchedStore?
    private var syncing = false
    private var lastAttempt = Date.distantPast

    private let syncKeys = ["addons", "progress", "settings", "links", "watched"]
    private let settingKeys = ["appearance", "preferredQuality", "skipIntroSeconds", "defaultSpeed", "downloadWiFiOnly", "dashboardOrder", "hiddenRatings", "preferredAudioLang", "preferredSubLang", "autoPlayNext", "showSkipCredits"]
    private let linkKeys = ["trakt.token", "simkl.token", "anilist.token", "mal.tokens", "jellyfin.session",
                            "plex.session", "opensubtitles.session", "tmdb.session",
                            "debrid.realdebrid.token", "debrid.torbox.token", "debrid.alldebrid.token", "debrid.premiumize.token"]

    var isConfigured: Bool { Config.isSet(Config.serverURL) }
    var isSignedIn: Bool { token != nil }

    init() {
        token = Keychain.load(key: tokenKey).flatMap { String(data: $0, encoding: .utf8) }
        email = token == nil ? nil : UserDefaults.standard.string(forKey: emailKey)
    }

    // MARK: Sign in and out

    func signUp(email: String, password: String) async -> Bool { await authenticate("register", email, password) }
    func signIn(email: String, password: String) async -> Bool { await authenticate("login", email, password) }

    private func authenticate(_ action: String, _ email: String, _ password: String) async -> Bool {
        error = nil
        guard isConfigured else { error = "Add your server address in Config.swift first."; return false }
        busy = true
        defer { busy = false }
        guard let (status, obj) = await request("POST", "/api/auth/\(action)", body: ["email": email, "password": password], authorized: false) else {
            error = "Couldn't reach the NuviGo server."
            return false
        }
        guard (200...201).contains(status), let t = obj?["token"] as? String else {
            error = (obj?["error"] as? String) ?? "That didn't work. Try again."
            return false
        }
        token = t
        self.email = ((obj?["user"] as? [String: Any])?["email"] as? String) ?? email
        Keychain.save(Data(t.utf8), key: tokenKey)
        UserDefaults.standard.set(self.email, forKey: emailKey)
        return true
    }

    /// Signs out of this device. Your addons, progress and settings stay here; the server copy stays on the server.
    func signOut() {
        clearSession()
    }

    func deleteAccount(password: String) async -> Bool {
        error = nil
        busy = true
        defer { busy = false }
        guard let (status, obj) = await request("DELETE", "/api/me", body: ["password": password]) else {
            error = "Couldn't reach the NuviGo server."
            return false
        }
        guard status == 200 else { error = (obj?["error"] as? String) ?? "Couldn't delete the account."; return false }
        clearSession()
        return true
    }

    private func clearSession() {
        token = nil
        email = nil
        lastSync = nil
        needsRestart = false
        Keychain.delete(key: tokenKey)
        UserDefaults.standard.removeObject(forKey: emailKey)
        for k in syncKeys {
            UserDefaults.standard.removeObject(forKey: "nuvigo.sync.hash.\(k)")
            UserDefaults.standard.removeObject(forKey: "nuvigo.sync.ver.\(k)")
        }
    }

    // MARK: Sync

    /// Brings this device and the server into step. Safe to call often; it skips if one is already running
    /// or the last one was under 30 seconds ago (unless `force`).
    func sync(store: AddonStore, progress: ProgressStore, force: Bool = false) async {
        guard isSignedIn, isConfigured, !syncing, ProfileStore.suffix.isEmpty else { return }   // only the main profile syncs
        if !force, Date().timeIntervalSince(lastAttempt) < 30 { return }
        syncing = true
        lastAttempt = Date()
        if force { busy = true }
        defer { syncing = false; busy = false }

        guard let (status, obj) = await request("GET", "/api/sync") else {
            if force { error = "Couldn't reach the NuviGo server." }
            return
        }
        if status == 401 { error = "Please sign in again."; clearSession(); return }
        guard status == 200 else { return }
        let server = (obj?["keys"] as? [String: Any]) ?? [:]
        var reloadAddons = false

        for key in syncKeys {
            let local = snapshot(key)
            let localHash = hash(local)
            let lastHash = UserDefaults.standard.string(forKey: "nuvigo.sync.hash.\(key)")
            let lastVersion = UserDefaults.standard.integer(forKey: "nuvigo.sync.ver.\(key)")
            let remote = server[key] as? [String: Any]

            if let remote, let data = remote["data"], let version = remote["version"] as? Int {
                if let lastHash, localHash != lastHash {
                    await push(key, local)                       // changed on this device since the last sync
                } else if version != lastVersion {
                    if key == "addons", lastHash == nil, let mine = local as? [String], let theirs = data as? [String] {
                        // First sign-in on this device: keep both lists.
                        let merged = theirs + mine.filter { !theirs.contains($0) }
                        apply(key, merged, store: store, progress: progress)
                        reloadAddons = true
                        await push(key, snapshot(key))
                    } else {
                        apply(key, data, store: store, progress: progress)
                        if key == "addons" { reloadAddons = true }
                        remember(key, version: version)
                    }
                }
            } else if !isEmpty(local) {
                await push(key, local)                           // the server has nothing yet
            }
        }
        if reloadAddons { await store.load() }
        lastSync = Date()
        error = nil
    }

    private func push(_ key: String, _ data: Any) async {
        guard let (status, obj) = await request("PUT", "/api/sync/\(key)", body: ["data": data]), status == 200,
              let version = obj?["version"] as? Int else { return }
        remember(key, version: version)
    }

    private func remember(_ key: String, version: Int) {
        UserDefaults.standard.set(hash(snapshot(key)), forKey: "nuvigo.sync.hash.\(key)")
        UserDefaults.standard.set(version, forKey: "nuvigo.sync.ver.\(key)")
    }

    // MARK: What gets synced

    private func snapshot(_ key: String) -> Any {
        switch key {
        case "addons":
            return addonURLs()
        case "progress":
            return UserDefaults.standard.data(forKey: "watchProgress")?.base64EncodedString() ?? ""
        case "watched":
            return UserDefaults.standard.data(forKey: "watchedItems")?.base64EncodedString() ?? ""
        case "settings":
            var out: [String: Any] = [:]
            for k in settingKeys { if let v = UserDefaults.standard.object(forKey: k) { out[k] = v } }
            return out
        default:
            var out: [String: String] = [:]
            for k in linkKeys { if let d = Keychain.load(key: k) { out[k] = d.base64EncodedString() } }
            return out
        }
    }

    /// The addon list comes from UserDefaults, which AddonStore keeps as a local mirror.
    private func addonURLs() -> [String] { UserDefaults.standard.stringArray(forKey: "addonURLs") ?? [] }

    private func apply(_ key: String, _ data: Any, store: AddonStore, progress: ProgressStore) {
        switch key {
        case "addons":
            if let list = data as? [String] { store.setURLs(list) }
        case "progress":
            if let b64 = data as? String, !b64.isEmpty, let d = Data(base64Encoded: b64) {
                UserDefaults.standard.set(d, forKey: "watchProgress")
                progress.reload()
            }
        case "watched":
            if let b64 = data as? String, !b64.isEmpty, let d = Data(base64Encoded: b64) {
                UserDefaults.standard.set(d, forKey: "watchedItems")
                watched?.reload()
            }
        case "settings":
            if let dict = data as? [String: Any] {
                for k in settingKeys { if let v = dict[k] { UserDefaults.standard.set(v, forKey: k) } }
            }
        default:
            if let dict = data as? [String: String] {
                for k in linkKeys {
                    guard let b64 = dict[k], let d = Data(base64Encoded: b64) else { continue }
                    if Keychain.load(key: k) != d { Keychain.save(d, key: k); needsRestart = true }
                }
            }
        }
    }

    private func isEmpty(_ v: Any) -> Bool {
        if let a = v as? [Any] { return a.isEmpty }
        if let d = v as? [String: Any] { return d.isEmpty }
        if let s = v as? String { return s.isEmpty }
        return false
    }

    private func hash(_ v: Any) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: v, options: [.sortedKeys, .fragmentsAllowed])) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Network

    private func request(_ method: String, _ path: String, body: [String: Any]? = nil,
                         authorized: Bool = true) async -> (Int, [String: Any]?)? {
        guard let url = URL(string: Config.serverURL + path) else { return nil }
        var headers = ["Content-Type": "application/json"]
        if authorized, let token { headers["Authorization"] = "Bearer \(token)" }
        guard let (status, data) = try? await HTTP.send(url, method: method, headers: headers,
                                                        body: body.flatMap(HTTP.json), timeout: 30) else { return nil }
        return (status, HTTP.object(data))
    }
}
