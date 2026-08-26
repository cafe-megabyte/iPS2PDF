import Foundation
import os

Logger(subsystem: "de.cafe-megabyte.iPS2PDF.MacOS.Ghostscript", category: "XPC")
    .notice("Starting Ghostscript XPC listener")
let delegate = MacOSGhostscriptListenerDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
