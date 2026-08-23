import Foundation

/// Keys shared by the app-side Ghostscript extension client.
enum GhostscriptExtensionEnvelope {
    static let version: Int64 = 2
    static let operation = "operation"
    static let envelopeVersion = "envelopeVersion"
    static let validate = "validate"
    static let profiles = "profiles"
    static let run = "run"
    static let limitsEnabled = "limitsEnabled"
    static let allowTransparency = "allowTransparency"
    static let standard = "standard"
    static let postScriptRandomSeed = "postScriptRandomSeed"
    static let deadline = "deadline"
    static let maximumOutputBytes = "maximumOutputBytes"
    static let status = "status"
    static let ghostscriptCode = "ghostscriptCode"
    static let stage = "stage"
    static let message = "message"
    static let profileMetadataJSON = "profileMetadataJSON"
    static let profileSelectionCount = "profileSelectionCount"
    static func profileSelectionKey(_ index: Int) -> String { "profileSelectionKey\(index)" }
    static func profileSelectionName(_ index: Int) -> String { "profileSelectionName\(index)" }
    static let userProfileCount = "userProfileCount"
    static func userProfileKey(_ index: Int) -> String { "userProfileKey\(index)" }
}
