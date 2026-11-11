import SwiftUI
import UIKit

/// The app's accent color. Change the three numbers to make it brighter, darker or a different purple.
enum Theme {
    private static let r = 0.69, g = 0.50, b = 1.0

    /// Light mode uses a deeper purple so text and buttons in the accent color stay readable on white.
    static let accentUI = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: r, green: g, blue: b, alpha: 1)
            : UIColor(red: 0.49, green: 0.23, blue: 0.93, alpha: 1)
    }
    static let accent = Color(uiColor: accentUI)
}

/// The Appearance setting in Account. "System" follows the phone; Light and Dark override it.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
