import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class MacOSPDFCompressionWindowController: NSWindowController, NSWindowDelegate {
    private static var windows: [UUID: MacOSPDFCompressionWindowController] = [:]
    private let session: PDFCompressionSession

    static func present(editing: PDFEditingSession) {
        do {
            let session = try PDFCompressionSession(editing: editing)
            let controller = MacOSPDFCompressionWindowController(session: session)
            windows[session.id] = controller
            controller.maximizeForInitialPresentation()
            controller.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        } catch { NSApp.presentError(error) }
    }
    static func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let input = try await Task.detached(priority: .userInitiated) { try PDFInspectionInput(sourceURL: url) }.value
                    let editing = try PDFEditingSession(input: input)
                    // Keep an information/export window for a standalone PDF;
                    // adopting a candidate never overwrites the selected file.
                    MacOSPDFInfoWindowController.present(editing: editing)
                    present(editing: editing)
                } catch { NSApp.presentError(error) }
            }
        }
    }
    private init(session: PDFCompressionSession) {
        self.session = session
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1050, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = String(localized: "Compress PDF") + " — " + session.input.input.fileName
        window.contentViewController = NSHostingController(rootView: PDFCompressionView(session: session) { [weak self] in self?.close() })
        window.minSize = NSSize(width: 800, height: 580)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }
    private func maximizeForInitialPresentation() {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        // Fill the screen's usable area while remaining a normal macOS window.
        // This deliberately avoids the separate system full-screen space.
        window.setFrame(screen.visibleFrame, display: false)
    }
    func windowWillClose(_ notification: Notification) {
        if let candidate = session.candidate, session.editing.current?.id == candidate.id {
            let identifier = NSUserInterfaceItemIdentifier("pdf-editing:" + session.editing.id.uuidString)
            if !NSApp.windows.contains(where: { $0 !== window && $0.isVisible && $0.identifier == identifier }) {
                // The originating document/info window may have been closed
                // while compression ran. Keep an explicit export route alive.
                MacOSPDFInfoWindowController.present(editing: session.editing)
            }
        }
        session.cancel()
        Self.windows.removeValue(forKey: session.id)
    }
}
