import AppIntents
import Combine
import Foundation

// Siri and Shortcuts: "Continue watching in NuviGo" and "Search NuviGo for ...".
// They only open the app on the right screen. Nothing is played or sent anywhere automatically.

struct ContinueWatchingIntent: AppIntent {
    static var title: LocalizedStringResource = "Continue Watching"
    static var description = IntentDescription("Opens the title you watched most recently.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard !PrivateMode.isOn else { return .result() }
        let key = "watchProgress" + ProfileStore.suffix
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([WatchProgress].self, from: data) else { return .result() }
        let latest = list.filter { $0.fraction >= 0.02 && $0.fraction < 0.9 }.max { $0.updated < $1.updated }
        if let e = latest { DeepLink.shared.open(type: e.itemType, id: e.itemID, name: e.name) }
        return .result()
    }
}

struct SearchTitleIntent: AppIntent {
    static var title: LocalizedStringResource = "Search NuviGo"
    static var description = IntentDescription("Opens Search with your words filled in.")
    static var openAppWhenRun = true

    @Parameter(title: "Title")
    var query: String

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLink.shared.search(query)
        return .result()
    }
}

struct NuviGoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ContinueWatchingIntent(),
                    phrases: ["Continue watching in \(.applicationName)", "Resume \(.applicationName)"],
                    shortTitle: "Continue Watching", systemImageName: "play.circle")
        AppShortcut(intent: SearchTitleIntent(),
                    phrases: ["Search \(.applicationName)"],
                    shortTitle: "Search", systemImageName: "magnifyingglass")
    }
}
