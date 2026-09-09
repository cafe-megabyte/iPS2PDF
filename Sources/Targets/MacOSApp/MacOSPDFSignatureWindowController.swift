import AppKit
import SwiftUI

@MainActor
final class MacOSPDFSignatureWindowController: NSWindowController, NSWindowDelegate {
    private static var windows: [UUID: MacOSPDFSignatureWindowController] = [:]
    private let session: PDFSignatureEditingSession

    static func present(editing: PDFEditingSession) {
        do {
            let session = try PDFSignatureEditingSession(editing: editing)
            let controller = MacOSPDFSignatureWindowController(session: session)
            windows[session.id] = controller
            controller.sizeForInitialPresentation()
            controller.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        } catch { NSApp.presentError(error) }
    }

    private init(session: PDFSignatureEditingSession) {
        self.session = session
        let windowSizing = MacOSPDFWindowSizing.signatureEditor
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: windowSizing.initialContentSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.title = String(localized: "Sign PDF") + " — " + session.input.input.fileName
        window.contentViewController = NSHostingController(
            rootView: PDFSignatureEditorView(session: session) { [weak self] in self?.close() }
        )
        window.minSize = windowSizing.minimumWindowSize
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    private func sizeForInitialPresentation() {
        guard let window else { return }
        MacOSPDFWindowSizing.prepare(
            window,
            forPDFAt: session.input.input.url,
            configuration: MacOSPDFWindowSizing.signatureEditor,
            centerAfterResizing: true
        )
    }

    func windowWillClose(_ notification: Notification) {
        if session.didFinish,
           !NSApp.windows.contains(where: { $0 !== window && $0.isVisible &&
               $0.identifier == NSUserInterfaceItemIdentifier("pdf-editing:" + session.editing.id.uuidString) }) {
            MacOSPDFInfoWindowController.present(editing: session.editing)
        }
        session.cancel()
        Self.windows.removeValue(forKey: session.id)
    }
}
