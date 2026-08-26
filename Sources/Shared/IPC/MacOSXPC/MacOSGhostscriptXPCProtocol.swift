#if os(macOS)
import Foundation

@objc protocol MacOSGhostscriptXPCProtocol {
    func send(
        _ request: Data,
        withReply reply: @escaping (Data?, String?) -> Void
    )
}
#endif
