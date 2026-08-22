import Foundation

struct EnhancedSecurityProfileMetadata: Codable, Sendable {
    let file: String
    let name: String
    let profileClass: String
    let colorSpace: String
    let connectionSpace: String

    init(record: ICCProfileRecord) {
        file = record.url.lastPathComponent
        name = record.name
        profileClass = record.profileClass
        colorSpace = record.colorSpace
        connectionSpace = record.connectionSpace
    }
}
