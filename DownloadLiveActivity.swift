import Foundation
import Combine
import ActivityKit

/// Shows download progress on the Lock Screen and in the Dynamic Island while files are downloading.
/// Needs "Supports Live Activities" = YES in Info.plist. The card is drawn by the widget extension.
@MainActor
final class DownloadLiveActivity {
    static let shared = DownloadLiveActivity()
    private var activity: Activity<DownloadActivityAttributes>?
    private var batchTotal = 0
    private var lastPush = Date.distantPast

    func sync(_ entries: [DownloadEntry]) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let active = entries.filter { $0.state == .downloading }
        guard let current = active.first else { end(); return }

        batchTotal = max(batchTotal, active.count)
        let total = batchTotal
        let state = DownloadActivityAttributes.ContentState(
            title: current.title, progress: current.progress,
            finished: max(0, total - active.count), total: total)

        if let activity {
            // Updates are rate limited by iOS, so send at most about once a second.
            guard Date().timeIntervalSince(lastPush) > 1 else { return }
            lastPush = Date()
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
        } else {
            activity = try? Activity.request(attributes: DownloadActivityAttributes(),
                                             content: ActivityContent(state: state, staleDate: nil))
            lastPush = Date()
        }
    }

    private func end() {
        batchTotal = 0
        guard let a = activity else { return }
        activity = nil
        Task { await a.end(nil, dismissalPolicy: .after(Date().addingTimeInterval(8))) }
    }
}
