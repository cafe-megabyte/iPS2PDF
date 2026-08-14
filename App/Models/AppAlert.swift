import Foundation

struct AppAlert: Identifiable {
    enum Kind {
        case error
        case notice
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let message: String
}

struct PDFPresentation: Identifiable {
    let id = UUID()
    let url: URL
}
