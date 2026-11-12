import Foundation
import Combine
import UIKit
import WidgetKit

/// Keeps the Home Screen widgets up to date: writes a small snapshot (plus tiny poster pictures) into the App Group.
@MainActor
enum WidgetBridge {
    /// Call when the app goes to the background or finishes launching.
    static func refresh(progress: ProgressStore, trakt: TraktAuth) async {
        guard NuviGoShared.containerURL != nil else { return }   // App Group not set up yet
        var snap = WidgetSnapshot()
        if !PrivateMode.isOn {
            let dir = NuviGoShared.postersDir
            if let dir { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
            var keep = Set<String>()
            for e in progress.continueWatching.prefix(4) {
                let file = await savePoster(e.poster, id: e.itemID, into: dir)
                if let file { keep.insert(file) }
                snap.continueWatching.append(WidgetContinueItem(id: e.itemID, type: e.itemType, name: e.name,
                                                                episodeLabel: e.episodeLabel.map(SpoilerGuard.hide), fraction: e.fraction, posterFile: file))
            }
            if let dir, let old = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
                for f in old where !keep.contains(f) { try? FileManager.default.removeItem(at: dir.appendingPathComponent(f)) }
            }
            if trakt.isSignedIn {
                snap.upcoming = await trakt.upcoming(days: 14).prefix(6).map {
                    WidgetUpcomingItem(id: $0.id, imdb: $0.imdb, show: $0.showTitle, label: SpoilerGuard.hide($0.label), airs: $0.airs)
                }
            }
        } else if let dir = NuviGoShared.postersDir {
            try? FileManager.default.removeItem(at: dir)
        }
        snap.updated = Date()
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Downloads a poster once and stores a small JPEG. Returns the file name.
    private static func savePoster(_ urlString: String?, id: String, into dir: URL?) async -> String? {
        guard let dir, let s = urlString, let url = URL(string: s) else { return nil }
        let name = id.replacingOccurrences(of: "/", with: "_") + ".jpg"
        let dest = dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: dest.path) { return name }
        guard let (data, _) = try? await URLSession.shared.data(from: url), let img = UIImage(data: data) else { return nil }
        let target: CGFloat = 360
        let scale = min(1, target / max(img.size.width, 1))
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let small = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = small.jpegData(compressionQuality: 0.7) else { return nil }
        try? jpeg.write(to: dest, options: .atomic)
        return name
    }
}
