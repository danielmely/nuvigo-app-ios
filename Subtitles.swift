import Foundation

struct SubtitleCue {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

/// Parses SRT and WebVTT. AVPlayer can't load external subtitle files, so NuviGo draws them itself.
enum SubtitleParser {
    static func parse(_ raw: String) -> [SubtitleCue] {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var cues: [SubtitleCue] = []
        for block in text.components(separatedBy: "\n\n") {
            let lines = block.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard let i = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let times = lines[i].components(separatedBy: "-->")
            guard times.count == 2, let start = seconds(times[0]), let end = seconds(times[1]) else { continue }
            let body = clean(lines[(i + 1)...].joined(separator: "\n"))
            if !body.isEmpty { cues.append(SubtitleCue(start: start, end: end, text: body)) }
        }
        return cues.sorted { $0.start < $1.start }
    }

    /// "00:01:02,345", "01:02.345", or "00:01:02.345 align:start"
    private static func seconds(_ s: String) -> TimeInterval? {
        let token = s.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
        let parts = token.replacingOccurrences(of: ",", with: ".").split(separator: ":").map(String.init)
        guard (2...3).contains(parts.count) else { return nil }
        var total = 0.0
        for p in parts {
            guard let v = Double(p) else { return nil }
            total = total * 60 + v
        }
        return total
    }

    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\{\\\\[^}]*\\}", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SubtitleLoader {
    static func load(_ track: SubtitleTrack) async -> [SubtitleCue] {
        guard let url = URL(string: track.url) else { return [] }
        return await load(url: url)
    }

    static func load(url: URL) async -> [SubtitleCue] {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return [] }
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        return SubtitleParser.parse(text)
    }
}
