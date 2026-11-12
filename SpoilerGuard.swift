import Foundation
import Combine

/// Optional: hides the titles of episodes you haven't watched yet, because a title can give away a plot point.
/// Turn it on in Account > Playback. Episode numbers still show.
enum SpoilerGuard {
    static let key = "spoilerGuard"
    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

    /// "S1E2 · The Reveal" becomes "S1E2" when the guard is on.
    static func hide(_ label: String) -> String {
        guard isOn, let r = label.range(of: " · ") else { return label }
        return String(label[..<r.lowerBound])
    }
}
