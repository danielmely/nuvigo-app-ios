import SwiftUI
import Combine
import UserNotifications

/// Local notifications for new episodes of the shows you follow on Trakt. Nothing is sent from a server:
/// the app reads your Trakt calendar and schedules the alerts on the device each time it opens.
@MainActor
final class EpisodeAlerts: NSObject, UNUserNotificationCenterDelegate {
    static let shared = EpisodeAlerts()
    static let key = "episodeAlerts"
    static var enabled: Bool { UserDefaults.standard.bool(forKey: key) }

    private let prefix = "nuvigo.episode."
    private var center: UNUserNotificationCenter { .current() }

    /// Call once at launch so taps on a notification are handled.
    func start() { center.delegate = self }

    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Replaces every scheduled episode alert with the current Trakt calendar.
    func refresh(trakt: TraktAuth) async {
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard Self.enabled, !PrivateMode.isOn, trakt.isSignedIn else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let now = Date()
        let upcoming = await trakt.upcoming(days: 14).filter { $0.airs > now }.prefix(50)   // iOS keeps at most 64 pending
        for u in upcoming {
            let content = UNMutableNotificationContent()
            content.title = u.showTitle
            content.body = "\(SpoilerGuard.hide(u.label)) is out now."
            content.sound = .default
            content.userInfo = ["imdb": u.imdb, "name": u.showTitle]
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: u.airs)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: prefix + u.id, content: content, trigger: trigger))
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let imdb = info["imdb"] as? String else { return }
        let name = info["name"] as? String
        await MainActor.run { DeepLink.shared.open(type: "series", id: imdb, name: name) }
    }
}

/// The switch in Account.
struct EpisodeAlertsSection: View {
    @EnvironmentObject var trakt: TraktAuth
    @AppStorage(EpisodeAlerts.key) private var on = false
    @State private var denied = false

    var body: some View {
        CollapsibleSection("Notifications") {
            Toggle("New episode alerts", isOn: Binding(
                get: { on },
                set: { want in
                    if want {
                        Task {
                            let ok = await EpisodeAlerts.shared.requestPermission()
                            denied = !ok
                            on = ok
                            await EpisodeAlerts.shared.refresh(trakt: trakt)
                        }
                    } else {
                        on = false
                        Task { await EpisodeAlerts.shared.refresh(trakt: trakt) }
                    }
                }))
            if !trakt.isSignedIn {
                Text("Connect Trakt below. Alerts come from the shows you follow there.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("You get a notification when a new episode of a show you follow airs. Alerts are set up each time you open NuviGo, for the next two weeks.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if denied {
                Text("Notifications are turned off for NuviGo. Allow them in the iPhone Settings app.")
                    .font(.footnote).foregroundStyle(.red)
            }
        }
    }
}
