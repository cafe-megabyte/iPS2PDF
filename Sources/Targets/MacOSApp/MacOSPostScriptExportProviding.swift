import AppKit

@MainActor
protocol MacOSPostScriptExportProviding: AnyObject {
    var postScriptExportInput: MacOSPostScriptExportInput? { get }
    var postScriptExportWindow: NSWindow? { get }
}
