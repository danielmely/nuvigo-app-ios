import SwiftUI
import Combine

/// The extra player for mkv, avi, webm and other files AVPlayer can't open.
///
/// To turn it on: Xcode → File → Add Package Dependencies → https://github.com/kingslay/KSPlayer
/// Once the package is added, `canImport(KSPlayer)` becomes true and these files switch over by themselves.
/// Without it the app still works; those files just show an "unsupported format" message.
#if canImport(KSPlayer)
import KSPlayer
#endif

enum AltEngine {
    static let extensions: Set<String> = ["mkv", "avi", "webm", "flv", "wmv", "ts", "m2ts", "divx", "ogv"]

    static var isAvailable: Bool {
        #if canImport(KSPlayer)
        return true
        #else
        return false
        #endif
    }

    /// Call once at launch. Lets KSPlayer's FFmpeg player take over when the built-in player can't open a file.
    static func configure() {
        #if canImport(KSPlayer)
        KSOptions.secondPlayerType = KSMEPlayer.self
        #endif
    }

    static func needs(_ url: URL) -> Bool { extensions.contains(url.pathExtension.lowercased()) }
}

#if canImport(KSPlayer)
import KSPlayer

/// KSPlayer brings its own controls. Position saving, scrobbling and the Up Next card don't run here.
struct AltPlayerView: View {
    let url: URL
    var body: some View {
        KSVideoPlayerView(url: url, options: KSOptions())
    }
}
#else
struct AltPlayerView: View {
    let url: URL
    var body: some View { EmptyView() }
}
#endif
