import SwiftUI
import GroupActivities
import AVFoundation

/// Watch together over FaceTime (SharePlay). Everyone opens the same title in their own NuviGo and plays their own stream,
/// while play, pause and seeking stay in step. No video or links are shared between people.
/// Needs the "Group Activities" capability on the app target.
struct WatchTogetherActivity: GroupActivity {
    var type: String
    var id: String
    var name: String
    var label: String?

    var metadata: GroupActivityMetadata {
        var m = GroupActivityMetadata()
        m.title = label.map { "\(name) · \($0)" } ?? name
        m.type = .watchTogether
        return m
    }
}

@MainActor
final class WatchTogether: ObservableObject {
    static let shared = WatchTogether()

    @Published private(set) var session: GroupSession<WatchTogetherActivity>?
    private var startedHere = false
    private var listening = false

    var isActive: Bool { session != nil }

    /// Call once at launch. Starts listening for sessions that someone else (or you) starts.
    func listen() {
        guard !listening else { return }
        listening = true
        Task {
            for await s in WatchTogetherActivity.sessions() { join(s) }
        }
    }

    private func join(_ s: GroupSession<WatchTogetherActivity>) {
        session = s
        s.join()
        if startedHere {
            startedHere = false      // you're already in the player
        } else {
            let a = s.activity
            DeepLink.shared.open(type: a.type, id: a.id, name: a.name)   // others land on the title's page
        }
        Task {
            for await state in s.$state.values {
                if case .invalidated = state { if session === s { session = nil }; break }
            }
        }
    }

    /// Asks iOS to start a SharePlay session for what you're watching.
    func start(_ ctx: PlaybackContext) async {
        let activity = WatchTogetherActivity(type: ctx.item.type, id: ctx.item.id, name: ctx.item.name, label: ctx.episodeLabel)
        startedHere = true
        switch await activity.prepareForActivation() {
        case .activationPreferred:
            if (try? await activity.activate()) == nil { startedHere = false }
        default:
            startedHere = false
        }
    }

    /// Keeps a player in step with the group. Call each time a new AVPlayer is created.
    func attach(_ player: AVPlayer) {
        guard let session else { return }
        player.playbackCoordinator.coordinateWithSession(session)
    }

    func leave() {
        session?.leave()
        session = nil
    }
}

/// The player's SharePlay button.
struct WatchTogetherButton: View {
    let context: PlaybackContext
    @ObservedObject private var group = WatchTogether.shared

    var body: some View {
        Button {
            Task { await WatchTogether.shared.start(context) }
        } label: {
            Image(systemName: "shareplay")
                .font(.title2)
                .foregroundStyle(group.isActive ? Theme.accent : .white.opacity(0.9))
        }
        .accessibilityLabel(group.isActive ? "Watching together" : "Watch together with SharePlay")
    }
}
