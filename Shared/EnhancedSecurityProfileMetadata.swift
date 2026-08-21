import Foundation

#if !ENHANCED_SECURITY_HELPER
struct EnhancedSecurityProfileMetadata: Codable, Sendable {
    let name: String
    let file: String
    let profileClass: String
    let colorSpace: String
    let connectionSpace: String

    enum CodingKeys: String, CodingKey {
        case name, file
        case profileClass = "class"
        case colorSpace, connectionSpace
    }
}
#endif
