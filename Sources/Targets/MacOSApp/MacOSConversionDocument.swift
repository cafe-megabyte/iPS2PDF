import AppKit
import PDFKit
import UniformTypeIdentifiers

@MainActor
final class MacOSConversionDocument: NSDocument, MacOSPostScriptExportProviding {
    private static var nextCascadeTopLeft = NSPoint.zero

    private let viewModel = MacOSDocumentViewModel()
    nonisolated(unsafe) private var sourceURL: URL?
    nonisolated(unsafe) private var sourceDisplayName = "Conversion.pdf"
    nonisolated(unsafe) private var convertedPDFURL: URL?
    private let exportSnapshot = PDFEditingSnapshotStore()
    private var conversionIsActive = false
    private var defersInitialWindowShow = true

    override class var autosavesInPlace: Bool { false }

    override init() {
        super.init()
    }

    override func read(from url: URL, ofType typeName: String) throws {
        sourceURL = url
        let stem = url.deletingPathExtension().lastPathComponent
        sourceDisplayName = (stem.isEmpty ? "Conversion" : stem) + ".pdf"
    }

    override func makeWindowControllers() {
        guard windowControllers.isEmpty, let sourceURL else { return }

        fileURL = nil
        fileType = UTType.pdf.identifier
        displayName = sourceDisplayName

        let viewController = MacOSDocumentViewController(viewModel: viewModel)
        let window = NSWindow(contentViewController: viewController)
        let windowSizing = MacOSPDFWindowSizing.convertedDocument
        window.setContentSize(windowSizing.initialContentSize)
        window.minSize = windowSizing.minimumWindowSize
        window.styleMask.formUnion([.resizable, .closable, .miniaturizable, .titled])
        cascadeWindowBeforeDisplay(window)

        let windowController = NSWindowController(window: window)
        addWindowController(windowController)
        MacOSApplicationModel.shared.postScriptExportController.register(self)
        windowController.synchronizeWindowTitleWithDocumentName()
        window.standardWindowButton(.closeButton)?.isEnabled = false
        conversionIsActive = true
        MacOSApplicationModel.shared.conversionDidStart()

        viewModel.onPDFReady = { [weak self, weak window, weak windowController] url in
            guard let self else { return }
            convertedPDFURL = url
            exportSnapshot.store(viewModel.editingSession?.current)
            if let editing = viewModel.editingSession {
                window?.identifier = NSUserInterfaceItemIdentifier("pdf-editing:" + editing.id.uuidString)
            }
            updateChangeCount(.changeCleared)
            if let window {
                MacOSPDFWindowSizing.resize(
                    window,
                    forFirstPageOf: url,
                    configuration: MacOSPDFWindowSizing.convertedDocument
                )
            }
            showInitialWindowIfNeeded()
            windowController?.synchronizeWindowTitleWithDocumentName()
        }
        viewModel.onShouldShowWindow = { [weak self] in
            self?.showInitialWindowIfNeeded()
        }
        viewModel.onPDFEdited = { [weak self] revision, isEdited in
            guard let self else { return }
            exportSnapshot.store(revision)
            convertedPDFURL = revision.input.url
            updateChangeCount(isEdited ? .changeDone : .changeCleared)
        }
        viewModel.onTerminalState = { [weak self, weak window] in
            window?.standardWindowButton(.closeButton)?.isEnabled = true
            guard let self, conversionIsActive else { return }
            conversionIsActive = false
            MacOSApplicationModel.shared.conversionDidFinish()
        }
        viewModel.onJoboptionsImported = { [weak self] in
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            self?.close()
        }
        viewModel.start(sourceURL: sourceURL)
    }

    override func showWindows() {
        guard !defersInitialWindowShow else { return }
        super.showWindows()
    }

    override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] {
        [UTType.pdf.identifier]
    }

    override func fileNameExtension(
        forType typeName: String,
        saveOperation: NSDocument.SaveOperationType
    ) -> String? {
        "pdf"
    }

    nonisolated override func write(to url: URL, ofType typeName: String) throws {
        guard let revision = exportSnapshot.value() else { throw ConversionFailure.outputMissing }
        try FileManager.default.copyItem(at: revision.input.url, to: url)
    }

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        guard let convertedPDFURL,
              let document = PDFDocument(url: convertedPDFURL),
              let operation = document.printOperation(
                for: NSPrintInfo(dictionary: printSettings),
                scalingMode: .pageScaleDownToFit,
                autoRotate: true
              )
        else {
            throw ConversionFailure.outputMissing
        }
        return operation
    }

    @IBAction func showPDFInformation(_ sender: Any?) {
        if let editing = viewModel.editingSession {
            MacOSPDFInfoWindowController.present(editing: editing)
            return
        }
        guard let convertedPDFURL else { return }
        do {
            // Snapshot now, before this document can remove its conversion workspace.
            MacOSPDFInfoWindowController.present(input: try PDFInspectionInput(sourceURL: convertedPDFURL))
        } catch { presentError(error) }
    }

    @IBAction func compressPDF(_ sender: Any?) {
        if let editing = viewModel.editingSession { MacOSPDFCompressionWindowController.present(editing: editing) }
        else { MacOSPDFCompressionWindowController.openPanel() }
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(showPDFInformation(_:)) { return convertedPDFURL != nil }
        return super.validateMenuItem(menuItem)
    }

    override func close() {
        MacOSApplicationModel.shared.postScriptExportController.unregister(self)
        super.close()
        viewModel.clearWorkspace()
    }

    var postScriptExportInput: MacOSPostScriptExportInput? {
        guard let revision = viewModel.editingSession?.current else { return nil }
        return MacOSPostScriptExportInput(
            url: revision.input.url,
            sourceName: revision.input.fileName,
            inputPassword: viewModel.editingSession?.passwordForProcessing,
            retainedInput: revision.input
        )
    }

    var postScriptExportWindow: NSWindow? {
        windowControllers.first?.window
    }

    private func showInitialWindowIfNeeded() {
        guard defersInitialWindowShow else { return }
        defersInitialWindowShow = false
        showWindows()
    }

    private func cascadeWindowBeforeDisplay(_ window: NSWindow) {
        let screen = window.screen ?? NSScreen.main
        if Self.nextCascadeTopLeft == .zero, let screen {
            Self.nextCascadeTopLeft = NSPoint(
                x: screen.visibleFrame.minX,
                y: screen.visibleFrame.maxY
            )
        }
        Self.nextCascadeTopLeft = window.cascadeTopLeft(from: Self.nextCascadeTopLeft)
    }

}
