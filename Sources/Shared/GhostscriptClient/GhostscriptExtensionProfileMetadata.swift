import Foundation

/// Serializable ICC profile metadata returned by the Ghostscript extension.
struct GhostscriptExtensionProfileMetadata: Codable, Sendable {
    let file: String
    let name: String
    let fileStem: String
    let profileClass: String
    let colorSpace: String
    let connectionSpace: String
    let outputConditionIdentifier: String?

    init(record: ICCProfileRecord) {
        file = record.url.lastPathComponent
        name = record.name
        fileStem = record.fileStem
        profileClass = record.profileClass
        colorSpace = record.colorSpace
        connectionSpace = record.connectionSpace
        outputConditionIdentifier = record.outputConditionIdentifier
    }
}
