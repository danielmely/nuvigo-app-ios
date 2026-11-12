import Foundation
import Combine

@MainActor
final class AddonStore: ObservableObject {
    @Published private(set) var addons: [Addon] = []
    @Published var isLoading = false

    private let key = "addonURLs"
    private let cloud = NSUbiquitousKeyValueStore.default
    private var observer: NSObjectProtocol?

    /// Source of truth is iCloud when it has a list; UserDefaults is the local mirror/fallback.
    private var urls: [String] {
        get { (cloud.array(forKey: key) as? [String]) ?? UserDefaults.standard.stringArray(forKey: key) ?? [] }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            cloud.set(newValue, forKey: key)
            cloud.synchronize()
        }
    }

    /// The saved addon URLs, for account sync.
    var savedURLs: [String] { urls }

    /// Replaces the saved list (used when an account sync brings in a different one). Call `load()` after.
    func setURLs(_ list: [String]) { urls = list }

    init() {
        // First launch with iCloud on: push any existing local list up so it isn't lost.
        if cloud.array(forKey: key) == nil, let local = UserDefaults.standard.stringArray(forKey: key) {
            cloud.set(local, forKey: key)
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.cloudDidChange() }
        }
        cloud.synchronize()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func cloudDidChange() async {
        if let remote = cloud.array(forKey: key) as? [String] {
            UserDefaults.standard.set(remote, forKey: key)
        }
        await load()
    }

    /// Re-fetch every saved manifest (keeps catalogs fresh, drops dead addons from view).
    func load() async {
        isLoading = true
        defer { isLoading = false }
        let bases = urls.compactMap { URL(string: $0) }
        var loaded: [Int: Addon] = [:]
        await withTaskGroup(of: (Int, Addon?).self) { group in
            for (i, base) in bases.enumerated() {
                group.addTask { (i, try? await AddonClient.fetchAddon(base)) }
            }
            for await (i, addon) in group { if let addon { loaded[i] = addon } }
        }
        addons = loaded.keys.sorted().compactMap { loaded[$0] }
    }

    func add(_ input: String) async throws {
        guard let base = AddonClient.normalize(input) else { throw AddonError.invalidURL }
        let addon = try await AddonClient.fetchAddon(base)   // validates before saving
        guard !addons.contains(where: { $0.id == addon.id }) else { return }
        urls.append(base.absoluteString)
        addons.append(addon)
    }

    func remove(at offsets: IndexSet) {
        let removed = offsets.map { addons[$0].id }
        urls.removeAll { removed.contains($0) }
        addons.remove(atOffsets: offsets)
    }
}
