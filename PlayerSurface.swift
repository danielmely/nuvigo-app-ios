import SwiftUI
import AVKit

/// What a touch gesture on the video asked for. PlayerView shows a small on-screen message for each.
enum PlayerGesture: Equatable {
    case seek(Int)             // seconds, negative = back
    case brightness(Float)     // 0...1
    case volume(Float)         // 0...1
    case boost(Bool)           // press and hold for 2x speed
}

/// The video itself, in a real AVPlayerViewController so Picture in Picture can hand you back to the full-screen player.
/// Also adds touch gestures on top of the normal controls: double-tap to skip, drag the sides for brightness and volume,
/// press and hold for 2x speed. They can be turned off in Account > Playback.
struct PlayerSurface: UIViewControllerRepresentable {
    let player: AVPlayer
    var onGesture: (PlayerGesture) -> Void = { _ in }

    static let gesturesKey = "playerGestures"

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.allowsPictureInPicturePlayback = true
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        vc.videoGravity = .resizeAspect
        vc.delegate = context.coordinator
        context.coordinator.install(on: vc.view)
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
        context.coordinator.player = player
        context.coordinator.onGesture = onGesture
    }

    static func dismantleUIViewController(_ vc: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.restoreBrightness()
    }

    func makeCoordinator() -> Coordinator {
        let c = Coordinator()
        c.player = player
        c.onGesture = onGesture
        return c
    }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate, UIGestureRecognizerDelegate {
        var player: AVPlayer?
        var onGesture: (PlayerGesture) -> Void = { _ in }

        private var originalBrightness: CGFloat?
        private var panStartValue: Float = 0
        private var panMode: PanMode?
        private var normalRate: Float = 1
        private enum PanMode { case brightness, volume }

        private var enabled: Bool {
            UserDefaults.standard.object(forKey: PlayerSurface.gesturesKey) as? Bool ?? true
        }

        func install(on view: UIView) {
            let double = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
            double.numberOfTapsRequired = 2
            let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(hold(_:)))
            hold.minimumPressDuration = 0.5
            for g in [double, pan, hold] as [UIGestureRecognizer] {
                g.delegate = self
                g.cancelsTouchesInView = false     // the normal player controls keep working
                view.addGestureRecognizer(g)
            }
        }

        // MARK: Gestures

        @objc private func doubleTap(_ g: UITapGestureRecognizer) {
            guard enabled, let view = g.view, let player else { return }
            let x = g.location(in: view).x
            let back = x < view.bounds.width / 2
            let delta = back ? -10.0 : 10.0
            let now = player.currentTime().seconds
            guard now.isFinite else { return }
            var target = max(0, now + delta)
            if let d = player.currentItem?.duration.seconds, d.isFinite { target = min(target, max(0, d - 1)) }
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            onGesture(.seek(Int(delta)))
        }

        @objc private func pan(_ g: UIPanGestureRecognizer) {
            guard enabled, let view = g.view else { return }
            switch g.state {
            case .began:
                let x = g.location(in: view).x
                panMode = x < view.bounds.width / 2 ? .brightness : .volume
                if originalBrightness == nil { originalBrightness = UIScreen.main.brightness }
                panStartValue = panMode == .brightness ? Float(UIScreen.main.brightness) : (player?.volume ?? 1)
            case .changed:
                // Dragging up raises the value; a full height drag moves it by about 1.2.
                let dy = Float(-g.translation(in: view).y / max(view.bounds.height, 1)) * 1.2
                let value = min(1, max(0, panStartValue + dy))
                if panMode == .brightness {
                    UIScreen.main.brightness = CGFloat(value)
                    onGesture(.brightness(value))
                } else {
                    player?.volume = value
                    onGesture(.volume(value))
                }
            default:
                panMode = nil
            }
        }

        @objc private func hold(_ g: UILongPressGestureRecognizer) {
            guard enabled, let player else { return }
            switch g.state {
            case .began:
                normalRate = player.defaultRate > 0 ? player.defaultRate : 1
                guard player.timeControlStatus == .playing else { return }
                player.rate = 2
                onGesture(.boost(true))
            case .ended, .cancelled, .failed:
                if player.timeControlStatus == .playing { player.rate = normalRate }
                onGesture(.boost(false))
            default: break
            }
        }

        func restoreBrightness() {
            if let b = originalBrightness { UIScreen.main.brightness = b }
            originalBrightness = nil
        }

        // MARK: UIGestureRecognizerDelegate

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        /// Side drags only start on the left and right edges of the picture, away from the scrubber at the bottom and the buttons at the top.
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard enabled, let view = g.view else { return false }
            let p = g.location(in: view)
            let safeMiddle = p.y > view.bounds.height * 0.15 && p.y < view.bounds.height * 0.72
            if let pan = g as? UIPanGestureRecognizer {
                let v = pan.velocity(in: view)
                let onSide = p.x < view.bounds.width * 0.28 || p.x > view.bounds.width * 0.72
                return onSide && safeMiddle && abs(v.y) > abs(v.x) * 1.5
            }
            return safeMiddle
        }

        // MARK: Picture in Picture

        /// Keep the player on screen when Picture in Picture starts, so tapping the PiP window returns to it.
        func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(_ vc: AVPlayerViewController) -> Bool {
            false
        }

        func playerViewController(_ vc: AVPlayerViewController,
                                  restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completion: @escaping (Bool) -> Void) {
            completion(true)
        }
    }
}
