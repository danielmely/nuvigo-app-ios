import Foundation

/// What a stream's name and title say about its quality.
struct StreamInfo {
    var resolution = 0
    var hdr = false
    var dolbyVision = false
    var codec: String?
    var container: String?

    /// "1080p · HEVC · HDR"
    var badges: String {
        var parts: [String] = []
        if resolution > 0 { parts.append(resolution >= 2160 ? "4K" : "\(resolution)p") }
        if dolbyVision { parts.append("Dolby Vision") } else if hdr { parts.append("HDR") }
        if let codec { parts.append(codec) }
        if let container { parts.append(container.uppercased()) }
        return parts.joined(separator: " · ")
    }

    /// True when the built-in player can't open this container and the extra player isn't installed.
    var likelyUnplayable: Bool {
        guard let container else { return false }
        return !AltEngine.isAvailable && AltEngine.extensions.contains(container)
    }
}

/// Sorts streams so the best playable one comes first.
enum StreamRanker {
    private static func match(_ pattern: String, in text: String) -> String? {
        guard let r = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[r])
    }

    static func info(_ s: Stream) -> StreamInfo {
        let text = [s.name, s.title, s.description, s.url].compactMap { $0 }.joined(separator: " ").lowercased()
        var i = StreamInfo()
        if match("2160p|\\b4k\\b|\\buhd\\b", in: text) != nil { i.resolution = 2160 }
        else if text.contains("1080") { i.resolution = 1080 }
        else if text.contains("720") { i.resolution = 720 }
        else if text.contains("480") { i.resolution = 480 }
        i.dolbyVision = match("\\bdv\\b|dolby.?vision|dovi", in: text) != nil
        i.hdr = text.contains("hdr")
        if match("\\bav1\\b", in: text) != nil { i.codec = "AV1" }
        else if match("x265|h\\.?265|hevc", in: text) != nil { i.codec = "HEVC" }
        else if match("x264|h\\.?264|\\bavc\\b", in: text) != nil { i.codec = "H.264" }
        if let ext = s.url.flatMap(URL.init(string:))?.pathExtension.lowercased(),
           ["mkv", "mp4", "m4v", "mov", "avi", "webm", "m3u8"].contains(ext) {
            i.container = ext
        } else if let m = match("\\b(mkv|mp4|m4v|avi|webm)\\b", in: text) {
            i.container = m
        }
        return i
    }

    static func score(_ e: StreamEntry, maxResolution: Int, playable: Bool) -> Int {
        let i = info(e.stream)
        var score = 0
        if playable { score += 100_000 }
        if e.stream.hasDirectURL { score += 2_000 }          // direct links start at once
        let res = i.resolution == 0 ? 480 : i.resolution
        score += res <= maxResolution ? res : max(maxResolution - 300, 0)
        if i.hdr || i.dolbyVision { score += 10 }
        if i.likelyUnplayable { score -= 5_000 }
        if i.codec == "AV1" && !AltEngine.isAvailable { score -= 3_000 }
        return score
    }

    /// Best first. Streams with equal scores keep the order the addons gave them.
    static func sorted(_ entries: [StreamEntry], maxResolution: Int, playable: (StreamEntry) -> Bool) -> [StreamEntry] {
        entries.enumerated()
            .map { (index: $0.offset, entry: $0.element, score: score($0.element, maxResolution: maxResolution, playable: playable($0.element))) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
            .map(\.entry)
    }
}
