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
    let details: String?

    init(kind: Kind, title: String, message: String, details: String? = nil) {
        self.kind = kind
        self.title = title
        self.message = message
        self.details = details
    }
}

