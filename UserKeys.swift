import Foundation
import Combine

/// API keys that belong to the person using the app. Nothing is built in: each person adds their own free key
/// in Account, and it is stored only in their Keychain.
nonisolated enum UserKey: String {
    case tmdb = "userKey.tmdb"
    case openSubtitles = "userKey.opensubtitles"

    var value: String {
        Keychain.load(key: rawValue).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
    var isSet: Bool { !value.isEmpty }

    func save(_ key: String) {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        Keychain.save(Data(k.utf8), key: rawValue)
    }
    func remove() { Keychain.delete(key: rawValue) }
}
