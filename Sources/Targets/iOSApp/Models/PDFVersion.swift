import Foundation

enum PDFVersion: String, CaseIterable, Identifiable, Sendable {
    case v11 = "1.1"
    case v12 = "1.2"
    case v13 = "1.3"
    case v14 = "1.4"
    case v15 = "1.5"
    case v16 = "1.6"
    case v17 = "1.7"
    case v20 = "2.0"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .v11:
            String(localized: "pdf_version_1_1_title")
        case .v12:
            String(localized: "pdf_version_1_2_title")
        case .v13:
            String(localized: "pdf_version_1_3_title")
        case .v14:
            String(localized: "pdf_version_1_4_title")
        case .v15:
            String(localized: "pdf_version_1_5_title")
        case .v16:
            String(localized: "pdf_version_1_6_title")
        case .v17:
            String(localized: "pdf_version_1_7_title")
        case .v20:
            String(localized: "pdf_version_2_0_title")
        }
    }

    var detail: String? {
        switch self {
        case .v11:
            String(localized: "pdf_version_1_1_detail")
        case .v12:
            String(localized: "pdf_version_1_2_detail")
        case .v13:
            String(localized: "pdf_version_1_3_detail")
        case .v14:
            String(localized: "pdf_version_1_4_detail")
        case .v15:
            String(localized: "pdf_version_1_5_detail")
        case .v16:
            String(localized: "pdf_version_1_6_detail")
        case .v17:
            String(localized: "pdf_version_1_7_detail")
        case .v20:
            nil
        }
    }

    var isHighlighted: Bool {
        switch self {
        case .v13, .v15, .v17:
            true
        case .v11, .v12, .v14, .v16, .v20:
            false
        }
    }

}
