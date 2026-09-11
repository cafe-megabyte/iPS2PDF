import Foundation

struct GhostscriptRuntimeSettingsSnapshot: Sendable {
    let securityLimitsEnabled: Bool
    let postScriptRandomSeed: Int
}
