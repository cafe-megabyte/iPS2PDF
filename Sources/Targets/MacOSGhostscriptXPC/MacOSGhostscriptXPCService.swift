import Foundation
import os

final class MacOSGhostscriptXPCService: NSObject, MacOSGhostscriptXPCProtocol {
    private let handler = GhostscriptExtensionRequestHandler()

    func send(
        _ request: Data,
        withReply reply: @escaping (Data?, String?) -> Void
    ) {
        Logger(subsystem: "de.cafe-megabyte.iPS2PDF.MacOS.Ghostscript", category: "XPC")
            .notice("Handling XPC request")
        do {
            let requestDictionary = try MacOSXPCMessageCodec.decode(request)
            let response = handler.handle(requestDictionary)
            reply(try MacOSXPCMessageCodec.encode(response), nil)
        } catch {
            reply(nil, error.localizedDescription)
        }
    }
}
