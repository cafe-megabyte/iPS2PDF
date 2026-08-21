import Foundation

enum DistillerCategory: String, CaseIterable, Identifiable, Sendable, Hashable {
    case general
    case images
    case fonts
    case color
    case advanced
    case standards
    case additional

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .images: String(localized: "Images")
        case .fonts: String(localized: "Fonts")
        case .color: String(localized: "Color")
        case .advanced: String(localized: "Advanced")
        case .standards: String(localized: "Standards")
        case .additional: String(localized: "Additional")
        }
    }

    var systemImage: String {
        switch self {
        case .general: "doc.badge.gearshape"
        case .images: "photo.on.rectangle.angled"
        case .fonts: "textformat"
        case .color: "paintpalette"
        case .advanced: "slider.horizontal.3"
        case .standards: "checkmark.seal"
        case .additional: "ellipsis.circle"
        }
    }
}
