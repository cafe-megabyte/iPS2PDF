import Foundation

enum EnhancedSecurityHelperProbeLog {
    private static let prefix = "🧭 iPS2PDF-ES"

    static func log(_ message: String) {
        NSLog("%@ helper %@", prefix, message)
    }
}
