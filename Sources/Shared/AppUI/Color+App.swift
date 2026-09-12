import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

extension Color {
    static let appTint = Color(
        red: 204 / 255.0,
        green: 33 / 255.0,
        blue: 49 / 255.0
    )

    static var appGroupedBackground: Color {
#if os(iOS)
        Color(uiColor: .systemGroupedBackground)
#else
        Color(nsColor: .windowBackgroundColor)
#endif
    }

    static var appSecondaryGroupedBackground: Color {
#if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
#else
        Color(nsColor: .controlBackgroundColor)
#endif
    }
}
