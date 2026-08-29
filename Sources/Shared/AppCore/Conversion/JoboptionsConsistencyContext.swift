import Foundation

struct JoboptionsConsistencyContext: Equatable, Sendable {
    struct Profile: Equatable, Sendable {
        let name: String
        var fileStem: String? = nil
        let colorSpace: String

        func matches(_ value: String) -> Bool {
            name == value || fileStem == value
        }
    }

    var availableProfiles: [Profile]

    static let empty = Self(availableProfiles: [])
}
