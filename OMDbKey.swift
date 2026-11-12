import SwiftUI
import Combine

/// Each person adds their own free OMDb key, so the daily limit (1,000 lookups) belongs to them alone.
/// Saved in the Keychain. Nothing is built in.
nonisolated enum OMDbKey {
    private static let account = "omdbAPIKey"

    static var value: String {
        if let d = Keychain.load(key: account), let s = String(data: d, encoding: .utf8), !s.isEmpty { return s }
        return ""
    }
    static var isSet: Bool { !value.isEmpty }
    static var hasOwn: Bool { Keychain.load(key: account) != nil }

    static func save(_ key: String) { Keychain.save(Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8), key: account) }
    static func remove() { Keychain.delete(key: account) }
}

struct OMDbSection: View {
    @EnvironmentObject var filter: ContentFilter
    @State private var text = ""
    @State private var has = OMDbKey.hasOwn
    @Environment(\.openURL) private var openURL

    var body: some View {
        CollapsibleSection("OMDb ratings") {
            if has {
                ConnectedRow(text: "Key saved")
                Button("Remove key", role: .destructive) {
                    OMDbKey.remove(); has = false; Ratings.clearCache(); filter.clearCache()
                }
            } else {
                SecureField("Your OMDb API key", text: $text)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Save key") {
                    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    OMDbKey.save(text); text = ""; has = true
                    filter.clearCache()
                }
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Get a free key at omdbapi.com") {
                    if let u = URL(string: "https://www.omdbapi.com/apikey.aspx") { openURL(u) }
                }
            }
        } footer: {
            Text("Used for IMDb and Rotten Tomatoes scores and the Hide by rating filter. A free key allows 1,000 lookups a day, and it's yours alone. Without a key, ratings and hiding by rating are off.")
        }
    }
}
