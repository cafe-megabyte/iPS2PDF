#if os(macOS)
import Foundation

@objc protocol MacOSGhostscriptXPCProtocol {
    func send(
        _ request: Data,
        inputFileHandle: FileHandle?,
        withReply reply: @escaping (Data?, String?) -> Void
    )
}
#endif
