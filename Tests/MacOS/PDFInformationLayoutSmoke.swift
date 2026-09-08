import AppKit

@main
struct PDFInformationLayoutSmoke {
    /// Runs the production AppKit view in a small standalone app, without XPC/provisioning
    /// or a simulator. Its fixture must be packaged in the test app's Resources directory.
    @MainActor
    private final class LayoutSmokeDelegate: NSObject, NSApplicationDelegate {
        func applicationDidFinishLaunching(_ notification: Notification) {
            Task { @MainActor in
                do {
                    guard let url = Bundle.main.url(forResource: "many-incomplete-pages", withExtension: "pdf") else { throw Failure("Missing fixture") }
                    MacOSPDFInfoWindowController.present(url: url)
                    let deadline = Date().addingTimeInterval(20)
                    var candidate: NSWindow?
                    while Date() < deadline {
                        candidate = NSApp.windows.first { $0.title.contains("many-incomplete-pages") }
                        if let root = candidate?.contentView, let status = find("pdf-analysis-status", in: root) as? NSTextField, status.stringValue.contains("35") { break }
                        try await Task.sleep(for: .milliseconds(50))
                    }
                    guard let window = candidate, let root = window.contentView,
                          let status = find("pdf-analysis-status", in: root) as? NSTextField,
                          let details = find("pdf-analysis-details", in: root) as? NSButton,
                          let saveRTF = find("pdf-save-rtf-report", in: root) as? NSButton,
                          let saveTXT = find("pdf-save-txt-report", in: root) as? NSButton,
                          let scroll = find("pdf-information-table", in: root) as? NSScrollView,
                          let outline = scroll.documentView as? NSOutlineView else { throw Failure("Missing production controls") }
                    root.layoutSubtreeIfNeeded()
                    try require(saveRTF.title == "Save .rtf" && saveTXT.title == "Save .txt", "Report formats are not separate save buttons")
                    try require(descendants(NSPopUpButton.self, in: root).isEmpty, "PDF information still contains an export dropdown")
                    try require(status.stringValue.contains("35"), "Analysis did not finish with 35 notices")
                    try require(!status.stringValue.contains("\n"), "Fixed status contains individual notices")
                    try require(status.frame.height <= 32.5, "Status exceeds compact height: \(status.frame.height)")
                    try require(scroll.frame.height >= 450, "Details table displaced: \(scroll.frame.height)")
                    print("900×720: status=\(status.frame.height) pt, table=\(scroll.frame.height) pt")
                    let collapsedRows = outline.numberOfRows
                    details.performClick(nil)
                    root.layoutSubtreeIfNeeded()
                    try require(outline.numberOfRows >= collapsedRows + 35, "Details button did not reveal all 35 notices")
                    try require(outline.isItemExpanded(outline.item(atRow: 0)), "Notice section remained collapsed")
                    try require(scroll.contentView.bounds.minY < 40, "Details button did not scroll to notices")
                    let screenshotURL = URL(fileURLWithPath: CommandLine.arguments[1])
                    if let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
                        root.cacheDisplay(in: root.bounds, to: bitmap)
                        try bitmap.representation(using: .png, properties: [:])?.write(to: screenshotURL)
                    }
                    window.setContentSize(NSSize(width: 680, height: 408))
                    root.layoutSubtreeIfNeeded()
                    try require(status.frame.height <= 32.5 && scroll.frame.height >= 160, "Compact window lost usable table")
                    print("680×408: status=\(status.frame.height) pt, table=\(scroll.frame.height) pt")
                    if CommandLine.arguments.contains("--interactive") {
                        window.setContentSize(NSSize(width: 900, height: 720))
                        print("Layout assertions passed; window remains open for visual inspection.")
                        return
                    }
                    window.close()
                    let editing = try PDFEditingSession(input: PDFInspectionInput(sourceURL: url))
                    MacOSPDFCompressionWindowController.present(editing: editing)
                    guard let compressionWindow = NSApp.windows.first(where: { $0.title.hasPrefix(String(localized: "Compress PDF")) }),
                          let screen = compressionWindow.screen ?? NSScreen.main else { throw Failure("Compression window did not open") }
                    let target = screen.visibleFrame
                    try require(abs(compressionWindow.frame.minX - target.minX) < 1 &&
                                abs(compressionWindow.frame.minY - target.minY) < 1 &&
                                abs(compressionWindow.frame.width - target.width) < 1 &&
                                abs(compressionWindow.frame.height - target.height) < 1,
                                "Compression window did not fill the visible screen")
                    compressionWindow.close()
                    editing.cancel()
                    print("PASS: separate report save buttons; maximum compression window; compact information layout with all 35 notices accessible.")
                    NSApp.terminate(nil)
                } catch {
                    FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8)); exit(1)
                }
            }
        }
        private struct Failure: Error, CustomStringConvertible { let description: String; init(_ message: String) { description = message } }
        private func require(_ condition: Bool, _ message: String) throws { if !condition { throw Failure(message) } }
        private func find(_ identifier: String, in view: NSView) -> NSView? {
            if view.accessibilityIdentifier() == identifier { return view }
            for child in view.subviews { if let result = find(identifier, in: child) { return result } }
            return nil
        }
        private func descendants<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
            view.subviews.flatMap { child in (child as? T).map { [$0] } ?? descendants(type, in: child) }
        }
    }

    @MainActor static func main() {
        guard CommandLine.arguments.count >= 2 else { fatalError("Expected screenshot output path") }
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        let delegate = LayoutSmokeDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
