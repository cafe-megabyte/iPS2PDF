import Foundation

struct JoboptionsConsistencyContext: Equatable, Sendable {
    struct Profile: Equatable, Sendable {
        let name: String
        let colorSpace: String
    }

    var availableProfiles: [Profile]

    static let empty = Self(availableProfiles: [])
}
