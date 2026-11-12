import SwiftUI
import Combine
import AVFoundation
import UIKit

// MARK: - Model

struct DownloadEntry: Codable, Identifiable, Hashable {
    enum State: String, Codable { case downloading, done, failed }
    enum Kind: String, Codable { case file, hls }

    let id: String             // the stream key: movie id, or episode id like "tt123:1:2"
    let itemID: String
    let itemType: String
    let name: String
    let poster: String?
    let episodeLabel: String?
    let kind: Kind
    var state: State
    var progress: Double
    var fileName: String?      // .file: name inside the Downloads folder
    var relativePath: String?  // .hls: path relative to the app's home folder
    var bytes: Int64
    var error: String?
    var added: Date

    var title: String { episodeLabel.map { "\(name) · \($0)" } ?? name }

    var metaItem: MetaItem {
        MetaItem(id: itemID, type: itemType, name: name, poster: poster, background: nil,
                 description: nil, releaseInfo: nil, runtime: nil, genres: nil, videos: nil)
    }
}

/// Where downloaded files live. Marked "do not back up", since they can be downloaded again.
enum DownloadPaths {
    static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var dir = base.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: dir.path)
        return dir
    }()

    static func fileName(_ id: String, ext: String) -> String {
        let safe = id.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
        return "\(safe).\(ext)"
    }

    static func size(of url: URL) -> Int64 {
        var total: Int64 = 0
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        if let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) {
            for case let f as URL in walker {
                let v = try? f.resourceValues(forKeys: Set(keys))
                if v?.isRegularFile == true { total += Int64(v?.fileSize ?? 0) }
            }
        }
        if total == 0, let n = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber {
            total = n.int64Value
        }
        return total
    }
}

/// Lets the system wake the app when a background download finishes.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var backgroundCompletions: [String: () -> Void] = [:]

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        Self.backgroundCompletions[identifier] = completionHandler
    }
}

// MARK: - Manager

/// Downloads movies and episodes for offline watching. Plain files use a background URLSession;
/// HLS streams (such as Jellyfin and Plex transcodes) use AVAssetDownloadURLSession.
/// Downloads keep going when the app is in the background.
@MainActor
final class DownloadManager: NSObject, ObservableObject {
    @Published private(set) var entries: [DownloadEntry] = []

    /// Account > Downloads: delete a download once you've finished watching it.
    static let autoDeleteKey = "autoDeleteWatchedDownloads"
    private let defaultsKey = "downloads.entries"
    private let fileID = "com.nuvigo.downloads.files"
    private let hlsID = "com.nuvigo.downloads.hls"
    private var fileSession: URLSession!
    private var hlsSession: AVAssetDownloadURLSession!

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let list = try? JSONDecoder().decode([DownloadEntry].self, from: data) {
            entries = list
        }
        let fileConfig = URLSessionConfiguration.background(withIdentifier: fileID)
        fileConfig.sessionSendsLaunchEvents = true
        fileSession = URLSession(configuration: fileConfig, delegate: self, delegateQueue: nil)

        let hlsConfig = URLSessionConfiguration.background(withIdentifier: hlsID)
        hlsSession = AVAssetDownloadURLSession(configuration: hlsConfig, assetDownloadDelegate: self,
                                               delegateQueue: OperationQueue.main)
        Task { await reconcile() }
    }

    // MARK: Queries

    func entry(_ key: String) -> DownloadEntry? { entries.first { $0.id == key } }

    func localURL(for key: String) -> URL? {
        guard let e = entry(key), e.state == .done else { return nil }
        switch e.kind {
        case .file: return e.fileName.map { DownloadPaths.folder.appendingPathComponent($0) }
        case .hls: return e.relativePath.map { URL(fileURLWithPath: NSHomeDirectory() + $0) }
        }
    }

    var totalBytes: Int64 { entries.filter { $0.state == .done }.reduce(0) { $0 + $1.bytes } }
    var doneCount: Int { entries.filter { $0.state == .done }.count }
    var activeCount: Int { entries.filter { $0.state == .downloading }.count }

    static func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: Actions

    func start(url: URL, context: PlaybackContext, wifiOnly: Bool) {
        let key = context.key
        if let e = entry(key), e.state != .failed { return }
        entries.removeAll { $0.id == key }

        let isHLS = url.pathExtension.lowercased() == "m3u8"
        entries.append(DownloadEntry(id: key, itemID: context.item.id, itemType: context.item.type,
                                     name: context.item.name, poster: context.item.poster,
                                     episodeLabel: context.episodeLabel, kind: isHLS ? .hls : .file,
                                     state: .downloading, progress: 0, fileName: nil, relativePath: nil,
                                     bytes: 0, error: nil, added: Date()))
        persist()

        if isHLS {
            let asset = AVURLAsset(url: url, options: [AVURLAssetAllowsCellularAccessKey: !wifiOnly])
            guard let task = hlsSession.makeAssetDownloadTask(asset: asset, assetTitle: context.item.name,
                                                              assetArtworkData: nil, options: nil) else {
                fail(key, "Couldn't start the download.")
                return
            }
            task.taskDescription = key
            task.resume()
        } else {
            var request = URLRequest(url: url)
            request.allowsCellularAccess = !wifiOnly
            let task = fileSession.downloadTask(with: request)
            task.taskDescription = key
            task.resume()
        }
    }

    /// Cancels a running download, or deletes a finished one.
    func remove(_ key: String) {
        guard let e = entry(key) else { return }
        if e.state == .downloading {
            fileSession.getAllTasks { tasks in tasks.filter { $0.taskDescription == key }.forEach { $0.cancel() } }
            hlsSession.getAllTasks { tasks in tasks.filter { $0.taskDescription == key }.forEach { $0.cancel() } }
        }
        if let url = localURL(for: key) { try? FileManager.default.removeItem(at: url) }
        entries.removeAll { $0.id == key }
        persist()
    }

    func removeAll() {
        for e in entries { remove(e.id) }
    }

    // MARK: State changes (always on the main actor)

    fileprivate func setProgress(_ key: String, _ value: Double) {
        guard let i = entries.firstIndex(where: { $0.id == key }), entries[i].state == .downloading else { return }
        entries[i].progress = min(max(value, 0), 1)
    }

    fileprivate func finish(_ key: String, fileName: String?, relativePath: String?, bytes: Int64) {
        guard let i = entries.firstIndex(where: { $0.id == key }) else { return }
        entries[i].state = .done
        entries[i].progress = 1
        entries[i].fileName = fileName
        entries[i].relativePath = relativePath
        entries[i].bytes = bytes
        entries[i].error = nil
        persist()
    }

    fileprivate func fail(_ key: String, _ message: String) {
        guard let i = entries.firstIndex(where: { $0.id == key }), entries[i].state != .done else { return }
        entries[i].state = .failed
        entries[i].error = message
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: defaultsKey) }
    }

    /// After a crash or a force-quit, downloads that no longer have a running task are marked failed.
    private func reconcile() async {
        let fileTasks = await fileSession.allTasks
        let hlsTasks = await hlsSession.allTasks
        let live = Set((fileTasks + hlsTasks).compactMap(\.taskDescription))
        var changed = false
        for i in entries.indices where entries[i].state == .downloading && !live.contains(entries[i].id) {
            entries[i].state = .failed
            entries[i].error = "The download was interrupted."
            changed = true
        }
        if changed { persist() }
    }
}

// MARK: - Delegates

extension DownloadManager: URLSessionDownloadDelegate, AVAssetDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        guard let key = downloadTask.taskDescription else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
        guard (200..<300).contains(status) else {
            Task { @MainActor in self.fail(key, "The server returned \(status).") }
            return
        }
        var ext = downloadTask.originalRequest?.url?.pathExtension.lowercased() ?? ""
        if ext.isEmpty || ext.count > 5 { ext = "mp4" }
        let name = DownloadPaths.fileName(key, ext: ext)
        let dest = DownloadPaths.folder.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: location, to: dest)   // must happen before this method returns
            // Unreadable while the phone is locked, except for a file that is already playing.
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: dest.path)
            let size = DownloadPaths.size(of: dest)
            Task { @MainActor in self.finish(key, fileName: name, relativePath: nil, bytes: size) }
        } catch {
            let message = error.localizedDescription
            Task { @MainActor in self.fail(key, message) }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        guard let key = downloadTask.taskDescription, totalBytesExpectedToWrite > 0 else { return }
        let value = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in self.setProgress(key, value) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let key = task.taskDescription else { return }
        if (error as NSError).code == NSURLErrorCancelled { return }
        let message = error.localizedDescription
        Task { @MainActor in self.fail(key, message) }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let id = session.configuration.identifier ?? ""
        DispatchQueue.main.async {
            AppDelegate.backgroundCompletions.removeValue(forKey: id)?()
        }
    }

    // HLS

    nonisolated func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask,
                                didLoad timeRange: CMTimeRange, totalTimeRangesLoaded loadedTimeRanges: [NSValue],
                                timeRangeExpectedToLoad: CMTimeRange) {
        guard let key = assetDownloadTask.taskDescription else { return }
        let expected = timeRangeExpectedToLoad.duration.seconds
        guard expected > 0 else { return }
        let loaded = loadedTimeRanges.reduce(0.0) { $0 + $1.timeRangeValue.duration.seconds }
        Task { @MainActor in self.setProgress(key, loaded / expected) }
    }

    nonisolated func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask,
                                didFinishDownloadingTo location: URL) {
        guard let key = assetDownloadTask.taskDescription else { return }
        // Keep the path relative to the home folder: the app's container path can change between updates.
        var path = location.path
        let home = NSHomeDirectory()
        if path.hasPrefix(home) { path = String(path.dropFirst(home.count)) }
        let size = DownloadPaths.size(of: location)
        Task { @MainActor in self.finish(key, fileName: nil, relativePath: path, bytes: size) }
    }
}

// MARK: - Views

/// One row on the Downloads screen.
struct DownloadRow: View {
    let entry: DownloadEntry
    let onPlay: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: entry.poster.flatMap(URL.init(string:))) { $0.resizable().scaledToFill() }
                placeholder: { Rectangle().fill(.quaternary) }
                .frame(width: 44, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title).lineLimit(2)
                switch entry.state {
                case .done:
                    Text("Downloaded · \(DownloadManager.sizeText(entry.bytes))")
                        .font(.caption).foregroundStyle(.secondary)
                case .downloading:
                    ProgressView(value: entry.progress)
                    Text("\(Int(entry.progress * 100))%").font(.caption).foregroundStyle(.secondary)
                case .failed:
                    Text(entry.error ?? "Download failed").font(.caption).foregroundStyle(.red)
                }
            }
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: entry.state == .downloading ? "xmark.circle" : "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(entry.state == .downloading ? "Cancel download" : "Delete download")
        }
        .contentShape(Rectangle())
        .onTapGesture { if entry.state == .done { onPlay() } }
    }
}


/// A downloaded movie or episode shown as its full poster, with its state on top.
struct DownloadTile: View {
    let entry: DownloadEntry
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottom) {
                AsyncImage(url: entry.poster.flatMap(URL.init(string:))) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else {
                        ZStack {
                            Rectangle().fill(.quaternary)
                            Text(entry.name).font(.caption.weight(.semibold)).multilineTextAlignment(.center).padding(8)
                        }
                    }
                }
                .aspectRatio(2 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                switch entry.state {
                case .downloading:
                    VStack(spacing: 4) {
                        ProgressView(value: entry.progress).tint(.white)
                        Text("\(Int(entry.progress * 100))%").font(.caption2.weight(.bold)).foregroundStyle(.white)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.black.opacity(0.6))
                    .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10))
                case .failed:
                    Text(entry.error ?? "Failed").font(.caption2.weight(.bold)).foregroundStyle(.white)
                        .padding(6).frame(maxWidth: .infinity).background(.red.opacity(0.85))
                        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10))
                case .done:
                    EmptyView()
                }
            }
            .overlay(alignment: .topTrailing) {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: entry.state == .downloading ? "xmark" : "trash")
                        .font(.caption.weight(.bold))
                        .padding(7)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(6)
                .accessibilityLabel(entry.state == .downloading ? "Cancel download" : "Delete download")
            }
            .overlay(alignment: .topLeading) {
                if entry.state == .done {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.body)
                        .foregroundStyle(.white, .green)
                        .padding(6)
                }
            }

            Text(entry.name).font(.caption.weight(.semibold)).lineLimit(1)
            if let label = entry.episodeLabel {
                Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            } else if entry.state == .done {
                Text(DownloadManager.sizeText(entry.bytes)).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
