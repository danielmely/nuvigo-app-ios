import SwiftUI
import AVFoundation
import CoreMedia

/// How subtitles look. Applies to subtitles from addons (drawn by NuviGo) and, for size, colour and background,
/// to subtitles that are inside the video file. Position only applies to addon subtitles.
enum SubtitleStyle {
    static let sizeKey = "subSize"              // text scale: 0.8, 1, 1.25, 1.5, 1.8
    static let colorKey = "subColor"            // white, yellow, cyan, green
    static let backgroundKey = "subBackground"  // none, soft, solid
    static let positionKey = "subPosition"      // low, middle, high

    static let sizes: [(label: String, value: Double)] = [("Small", 0.8), ("Default", 1.0), ("Large", 1.25), ("Larger", 1.5), ("Largest", 1.8)]
    static let colors: [(label: String, key: String)] = [("White", "white"), ("Yellow", "yellow"), ("Cyan", "cyan"), ("Green", "green")]
    static let backgrounds: [(label: String, key: String)] = [("None", "none"), ("Soft", "soft"), ("Solid", "solid")]
    static let positions: [(label: String, key: String)] = [("Low", "low"), ("Middle", "middle"), ("High", "high")]

    static func color(_ key: String) -> Color {
        switch key {
        case "yellow": return Color(red: 1, green: 0.92, blue: 0.3)
        case "cyan": return Color(red: 0.4, green: 0.95, blue: 1)
        case "green": return Color(red: 0.5, green: 1, blue: 0.5)
        default: return .white
        }
    }
    static func rgb(_ key: String) -> [CGFloat] {
        switch key {
        case "yellow": return [1, 0.92, 0.3]
        case "cyan": return [0.4, 0.95, 1]
        case "green": return [0.5, 1, 0.5]
        default: return [1, 1, 1]
        }
    }
    static func backgroundOpacity(_ key: String) -> Double { key == "none" ? 0 : key == "solid" ? 0.9 : 0.55 }
    static func bottomPadding(_ key: String) -> CGFloat { key == "high" ? 190 : key == "middle" ? 140 : 96 }

    /// Applies size, colour and background to subtitles stored inside the video file.
    static func applyEmbedded(to item: AVPlayerItem?) {
        guard let item else { return }
        let d = UserDefaults.standard
        let size = d.object(forKey: sizeKey) as? Double ?? 1
        let color = d.string(forKey: colorKey) ?? "white"
        let background = d.string(forKey: backgroundKey) ?? "soft"
        guard size != 1 || color != "white" || background != "soft" else { item.textStyleRules = nil; return }
        let c = rgb(color)
        var attrs: [String: Any] = [
            kCMTextMarkupAttribute_ForegroundColorARGB as String: [1.0, c[0], c[1], c[2]],
            kCMTextMarkupAttribute_BaseFontSizePercentageRelativeToVideoHeight as String: 5.0 * size,
        ]
        attrs[kCMTextMarkupAttribute_CharacterBackgroundColorARGB as String] = [backgroundOpacity(background), 0, 0, 0]
        if let rule = AVTextStyleRule(textMarkupAttributes: attrs) { item.textStyleRules = [rule] }
    }
}

/// One line of subtitle text, drawn in the chosen style. Used by the player and by the preview in Account.
struct StyledSubtitleText: View {
    let text: String
    @AppStorage(SubtitleStyle.sizeKey) private var size = 1.0
    @AppStorage(SubtitleStyle.colorKey) private var color = "white"
    @AppStorage(SubtitleStyle.backgroundKey) private var background = "soft"

    var body: some View {
        Text(text)
            .font(.system(size: 20 * size, weight: .semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(SubtitleStyle.color(color))
            .shadow(color: .black.opacity(background == "none" ? 0.9 : 0), radius: 2)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.black.opacity(SubtitleStyle.backgroundOpacity(background)), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct SubtitleStyleSection: View {
    @AppStorage(SubtitleStyle.sizeKey) private var size = 1.0
    @AppStorage(SubtitleStyle.colorKey) private var color = "white"
    @AppStorage(SubtitleStyle.backgroundKey) private var background = "soft"
    @AppStorage(SubtitleStyle.positionKey) private var position = "low"

    var body: some View {
        CollapsibleSection("Subtitle style") {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: [.gray, .black], startPoint: .top, endPoint: .bottom))
                StyledSubtitleText(text: String(localized: "This is how subtitles will look."))
                    .padding(.horizontal, 12)
            }
            .frame(height: 110)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            Picker("Size", selection: $size) {
                ForEach(SubtitleStyle.sizes, id: \.value) { Text(LocalizedStringKey($0.label)).tag($0.value) }
            }
            Picker("Color", selection: $color) {
                ForEach(SubtitleStyle.colors, id: \.key) { Text(LocalizedStringKey($0.label)).tag($0.key) }
            }
            Picker("Background", selection: $background) {
                ForEach(SubtitleStyle.backgrounds, id: \.key) { Text(LocalizedStringKey($0.label)).tag($0.key) }
            }
            Picker("Position", selection: $position) {
                ForEach(SubtitleStyle.positions, id: \.key) { Text(LocalizedStringKey($0.label)).tag($0.key) }
            }
            Button("Reset to default") { size = 1; color = "white"; background = "soft"; position = "low" }
            Text("Position only applies to subtitles from addons. Subtitles that are inside the video file use the size, color and background.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
