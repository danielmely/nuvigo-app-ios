import Foundation
import Combine

// Shared between the NuviGo app and the NuviGoWidgets extension (tick both targets in the File inspector).
// Foundation only, so the widget never needs the rest of the app.

enum NuviGoShared {
    /// Create this App Group on both targets (Signing & Capabilities > App Groups).
    static let appGroup = "group.com.nuvigo.app"
    static let scheme = "nuvigo"

    static var containerURL: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) }
    static var snapshotURL: URL? { containerURL?.appendingPathComponent("widget.json") }
    static var postersDir: URL? { containerURL?.appendingPathComponent("posters", isDirectory: true) }

    /// nuvigo://title/series/tt1234567: opens that title's page.
    static func titleLink(type: String, id: String, name: String? = nil) -> URL {
        var c = URLComponents()
        c.scheme = scheme
        c.host = "title"
        c.path = "/" + type + "/" + id
        if let name { c.queryItems = [URLQueryItem(name: "n", value: name)] }
        return c.url ?? URL(string: "\(scheme)://")!
    }
}

struct WidgetContinueItem: Codable, Identifiable, Hashable {
    let id: String            // title id
    let type: String
    let name: String
    let episodeLabel: String?
    let fraction: Double
    let posterFile: String?   // file name inside NuviGoShared.postersDir
}

struct WidgetUpcomingItem: Codable, Identifiable, Hashable {
    let id: String
    let imdb: String
    let show: String
    let label: String         // "S2E5 · Title"
    let airs: Date
}

struct WidgetSnapshot: Codable {
    var continueWatching: [WidgetContinueItem] = []
    var upcoming: [WidgetUpcomingItem] = []
    var updated = Date()

    static func load() -> WidgetSnapshot {
        guard let url = NuviGoShared.snapshotURL, let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return WidgetSnapshot() }
        return snap
    }

    func save() {
        guard let url = NuviGoShared.snapshotURL, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Shown in the widget gallery and while the real data loads.
    static let sample = WidgetSnapshot(
        continueWatching: [
            WidgetContinueItem(id: "a", type: "movie", name: "Movie Night", episodeLabel: nil, fraction: 0.4, posterFile: nil),
            WidgetContinueItem(id: "b", type: "series", name: "Great Show", episodeLabel: "S1E3", fraction: 0.7, posterFile: nil),
            WidgetContinueItem(id: "c", type: "series", name: "Another Show", episodeLabel: "S2E1", fraction: 0.15, posterFile: nil),
        ],
        upcoming: [
            WidgetUpcomingItem(id: "1", imdb: "a", show: "Great Show", label: "S1E4", airs: Date().addingTimeInterval(86_400)),
            WidgetUpcomingItem(id: "2", imdb: "b", show: "Another Show", label: "S2E2", airs: Date().addingTimeInterval(3 * 86_400)),
        ])
}
