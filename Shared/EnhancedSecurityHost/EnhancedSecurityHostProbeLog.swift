import Foundation

enum EnhancedSecurityHostProbeLog {
    private static let prefix = "🧭 iPS2PDF-ES"

    static func log(_ message: String) {
        NSLog("%@ host %@", prefix, message)
    }
}
