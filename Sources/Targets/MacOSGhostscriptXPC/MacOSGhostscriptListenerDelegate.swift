import Foundation
import os

final class MacOSGhostscriptListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        Logger(subsystem: "de.cafe-megabyte.iPS2PDF.MacOS.Ghostscript", category: "XPC")
            .notice("Accepting XPC connection")
        connection.exportedInterface = NSXPCInterface(
            with: MacOSGhostscriptXPCProtocol.self
        )
        connection.exportedObject = MacOSGhostscriptXPCService()
        connection.resume()
        return true
    }
}
