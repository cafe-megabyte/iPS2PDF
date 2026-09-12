import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class MacOSPDFInfoWindowController: NSWindowController, NSWindowDelegate {
    private static var windows: [UUID: MacOSPDFInfoWindowController] = [:]
    private static var cascadePoint = NSPoint.zero
    private let identifier = UUID()
    private let session: PDFInspectionSession
    private let ownsInspection: Bool

    static func present(url: URL) {
        present(session: PDFInspectionSession(url: url))
    }
    static func present(input: PDFInspectionInput) {
        present(session: PDFInspectionSession(input: input))
    }
    static func present(editing: PDFEditingSession) {
        guard let inspection = editing.inspection else { return }
        present(session: inspection, editing: editing)
    }
    private static func present(session: PDFInspectionSession, editing: PDFEditingSession? = nil) {
        let controller = MacOSPDFInfoWindowController(session: session, editing: editing)
        windows[controller.identifier] = controller
        if let window = controller.window { cascadePoint = window.cascadeTopLeft(from: cascadePoint) }
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    static func openPanel(parentWindow: NSWindow? = nil) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = String(localized: "Select PDFs to display their information.")
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            for url in panel.urls { present(url: url) }
        }
        if let parentWindow, parentWindow.attachedSheet == nil {
            panel.beginSheetModal(for: parentWindow, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }
    private init(session: PDFInspectionSession, editing: PDFEditingSession?) {
        self.session = session
        ownsInspection = editing == nil
        let window = NSWindow(contentViewController: MacOSPDFInfoViewController(session: session, editing: editing))
        window.title = String(localized: "PDF information") + " — " + session.report.fileName
        window.setContentSize(NSSize(width: 900, height: 720))
        window.minSize = NSSize(width: 680, height: 430)
        window.styleMask.formUnion([.titled, .resizable, .closable, .miniaturizable])
        window.isReleasedWhenClosed = false
        if let editing { window.identifier = NSUserInterfaceItemIdentifier("pdf-editing:" + editing.id.uuidString) }
        super.init(window: window)
        window.delegate = self
        window.center()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }
    func windowWillClose(_ notification: Notification) {
        (contentViewController as? MacOSPDFInfoViewController)?.stopProcessing()
        if ownsInspection { session.cancel() }
        Self.windows.removeValue(forKey: identifier)
    }
}
