import SwiftUI
import Combine
import UIKit

/// Lets you pick a different app icon. The pictures are the PNG files in the AlternateIcons folder,
/// and each one is also listed under CFBundleAlternateIcons in Info.plist (see SETUP-NEW-FEATURES.md).
struct AppIconOption: Identifiable, Hashable {
    let id: String          // nil icon name = the normal icon
    let name: String?       // alternate icon name, nil for the default
    let title: String

    static let all: [AppIconOption] = [
        AppIconOption(id: "default", name: nil, title: "Default"),
        AppIconOption(id: "midnight", name: "IconMidnight", title: "Midnight"),
        AppIconOption(id: "mono", name: "IconMono", title: "Light"),
        AppIconOption(id: "sunrise", name: "IconSunrise", title: "Sunrise"),
        AppIconOption(id: "ocean", name: "IconOcean", title: "Ocean"),
    ]
}

struct AppIconSection: View {
    @State private var current: String? = UIApplication.shared.alternateIconName
    @State private var failed = false

    var body: some View {
        CollapsibleSection("App icon") {
            if !UIApplication.shared.supportsAlternateIcons {
                Text("Alternate icons aren't available on this device.").font(.footnote).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(AppIconOption.all) { option in
                            Button { choose(option) } label: { tile(option) }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(LocalizedStringKey(option.title)))
                                .accessibilityAddTraits(current == option.name ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 6)
                }
                if failed {
                    Text("Couldn't change the icon. Try again in a moment.").font(.footnote).foregroundStyle(.red)
                }
            }
        }
    }

    private func tile(_ option: AppIconOption) -> some View {
        let selected = current == option.name
        return VStack(spacing: 6) {
            preview(option)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(selected ? Theme.accent : Color.secondary.opacity(0.3), lineWidth: selected ? 3 : 1))
            Text(LocalizedStringKey(option.title)).font(.caption).foregroundStyle(selected ? Theme.accent : .secondary)
        }
    }

    @ViewBuilder
    private func preview(_ option: AppIconOption) -> some View {
        if let name = option.name, let img = UIImage(named: name) {
            Image(uiImage: img).resizable().scaledToFill()
        } else if let mark = LogoData.mark {
            ZStack { Color.white; Image(uiImage: mark).resizable().scaledToFit().padding(8) }
        } else {
            Color.secondary.opacity(0.2)
        }
    }

    private func choose(_ option: AppIconOption) {
        guard option.name != current else { return }
        failed = false
        UIApplication.shared.setAlternateIconName(option.name) { error in
            DispatchQueue.main.async {
                if error == nil { current = option.name } else { failed = true }
            }
        }
    }
}
