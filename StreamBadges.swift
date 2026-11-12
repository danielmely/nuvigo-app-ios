import SwiftUI
import Combine

/// A tiny outlined label, like the 4K and HD badges on a TV remote.
struct GlyphChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(lineWidth: 1.2))
    }
}

/// The row of icons under a stream's title: resolution, HDR, codec, file type and where it comes from.
struct StreamBadges: View {
    let entry: StreamEntry

    private var info: StreamInfo { StreamRanker.info(entry.stream) }
    private var isServer: Bool { ["Jellyfin", "Plex"].contains(entry.addon) }

    private var resolutionGlyph: String? {
        switch info.resolution {
        case 2160...: return "4K"
        case 1080...: return "FHD"
        case 720...: return "HD"
        case 1...: return "SD"
        default: return nil
        }
    }

    private var codecGlyph: String? {
        switch info.codec {
        case "HEVC": return "H.265"
        case "H.264": return "H.264"
        case "AV1": return "AV1"
        default: return nil
        }
    }

    private var containerSymbol: String? {
        guard let c = info.container else { return nil }
        if info.likelyUnplayable { return "exclamationmark.triangle.fill" }
        if c == "m3u8" { return "dot.radiowaves.left.and.right" }
        return ["mp4", "m4v", "mov"].contains(c) ? "film" : "film.stack"
    }

    private var sourceSymbol: String {
        if isServer { return "server.rack" }
        return entry.stream.hasDirectURL ? "link" : "bolt.fill"
    }

    private var spoken: String {
        var parts = [info.badges]
        if info.likelyUnplayable { parts.append("may not play") }
        parts.append(isServer ? "from your server" : (entry.stream.hasDirectURL ? "direct link" : "torrent through debrid"))
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 8) {
            if let r = resolutionGlyph { GlyphChip(text: r) }
            if info.dolbyVision { Image(systemName: "circle.lefthalf.filled") }
            else if info.hdr { Image(systemName: "sun.max.fill") }
            if let c = codecGlyph { GlyphChip(text: c) }
            if let s = containerSymbol {
                Image(systemName: s)
                    .foregroundStyle(info.likelyUnplayable ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tint))
            }
            Image(systemName: sourceSymbol)
        }
        .font(.caption)
        .foregroundStyle(.tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}
