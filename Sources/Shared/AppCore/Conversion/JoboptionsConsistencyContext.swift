import Foundation

struct JoboptionsConsistencyContext: Equatable, Sendable {
    struct Profile: Equatable, Sendable {
        let name: String
        var fileStem: String? = nil
        let colorSpace: String
        var profileClass: String = ""
        var outputConditionIdentifier: String? = nil

        func matches(_ value: String) -> Bool {
            func normalized(_ text: String) -> String {
                text.trimmingCharacters(in: .whitespacesAndNewlines).folding(
                    options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                )
            }
            let requested = normalized(value)
            // Match the aliases accepted by the runtime profile resolver.
            let aliases = [
                normalized("sRGB IEC61966-2.1"): normalized("sRGB Profile"),
                normalized("Gray Gamma 2.2"): normalized("Generic Gray Gamma 2.2 Profile")
            ]
            let candidates = [requested, aliases[requested]].compactMap { $0 }
            return candidates.contains(normalized(name))
                || fileStem.map { candidates.contains(normalized($0)) } == true
        }
    }

    var availableProfiles: [Profile]

    static let empty = Self(availableProfiles: [])
}
