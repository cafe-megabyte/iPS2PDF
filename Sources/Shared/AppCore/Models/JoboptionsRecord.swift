import Foundation

struct JoboptionsRecord: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let origin: JoboptionsOrigin
    let url: URL

    var isBundled: Bool { origin == .bundled }
}
