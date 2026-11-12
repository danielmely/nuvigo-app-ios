import Foundation
import Combine
import CryptoKit
import Network

/// Saves addon responses (manifests, catalogs, details) to disk so Browse still works with no connection.
nonisolated enum ResponseCache {
    private static let dir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("addon-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private static func file(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return dir.appendingPathComponent(digest.map { String(format: "%02x", $0) }.joined())
    }

    static func save(_ data: Data, for url: URL) {
        try? data.write(to: file(for: url), options: .atomic)
    }

    static func load(_ url: URL) -> Data? {
        try? Data(contentsOf: file(for: url))
    }

    static func clear() {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for f in files { try? FileManager.default.removeItem(at: f) }
    }

    /// Deletes saved responses older than 30 days. Called once at launch.
    static func prune() {
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for f in files {
            let date = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let date, date < cutoff { try? FileManager.default.removeItem(at: f) }
        }
    }
}

/// Tells the UI whether the phone is online, so Browse can say it's showing saved titles.
@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    init() { begin() }

    private func begin() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "nuvigo.network"))
    }
}
