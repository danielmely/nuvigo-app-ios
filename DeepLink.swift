import SwiftUI
import Combine
import CoreSpotlight

/// One place that turns "open this title" requests (widgets, notifications, Spotlight, Siri) into screens.
@MainActor
final class DeepLink: ObservableObject {
    static let shared = DeepLink()

    /// Set this and the app shows that title's page on top of whatever is open.
    @Published var item: MetaItem?
    /// Set by Siri or a link: the app jumps to Search and fills these words in. Each request has its own id so it's applied once.
    struct SearchRequest: Equatable { let id = UUID(); let text: String }
    @Published var searchRequest: SearchRequest?

    /// Set by a screen that wants to send you to another tab (for example "connect Plex" in Addons opens Account).
    struct TabRequest: Equatable { let id = UUID(); let tab: Int }
    @Published var tabRequest: TabRequest?

    func openTab(_ tab: Int) { tabRequest = TabRequest(tab: tab) }

    func search(_ text: String) { searchRequest = SearchRequest(text: text) }

    func open(type: String, id: String, name: String?) {
        item = MetaItem(id: id, type: type, name: name ?? "", poster: nil, background: nil,
                        description: nil, releaseInfo: nil, runtime: nil, genres: nil, videos: nil)
    }

    /// nuvigo://title/<type>/<id>?n=<name>  or  nuvigo://search?q=<words>
    func handle(url: URL) {
        guard url.scheme == NuviGoShared.scheme else { return }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        switch url.host {
        case "title":
            let parts = url.path.split(separator: "/").map(String.init)
            guard parts.count >= 2 else { return }
            open(type: parts[0], id: parts[1], name: comps?.queryItems?.first(where: { $0.name == "n" })?.value)
        case "search":
            search(comps?.queryItems?.first(where: { $0.name == "q" })?.value ?? "")
        default: break
        }
    }

    /// A Spotlight result was tapped. Identifiers look like "nuvigo.title.<type>.<id>".
    func handle(spotlight activity: NSUserActivity) {
        guard let raw = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              raw.hasPrefix(SpotlightIndexer.prefix) else { return }
        let rest = raw.dropFirst(SpotlightIndexer.prefix.count)
        guard let dot = rest.firstIndex(of: ".") else { return }
        let type = String(rest[rest.startIndex..<dot])
        let id = String(rest[rest.index(after: dot)...])
        open(type: type, id: id, name: nil)
    }
}
