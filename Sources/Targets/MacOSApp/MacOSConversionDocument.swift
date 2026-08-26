import AppKit
import PDFKit
import UniformTypeIdentifiers

@MainActor
final class MacOSConversionDocument: NSDocument {
    private enum WindowSizing {
        static let initialContentSize = NSSize(width: 860, height: 700)
        static let minimumSize = NSSize(width: 440, height: 360)
        static let pagePadding = NSSize(width: 80, height: 80)
        static let maximumContentHeightOnLargeDisplays: CGFloat = 980
        static let maximumScreenWidthFraction: CGFloat = 0.92
    }

    private static var nextCascadeTopLeft = NSPoint.zero

    private let viewModel = MacOSDocumentViewModel()
    nonisolated(unsafe) private var sourceURL: URL?
    nonisolated(unsafe) private var sourceDisplayName = "Conversion.pdf"
    nonisolated(unsafe) private var convertedPDFURL: URL?
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
        window.setContentSize(WindowSizing.initialContentSize)
        window.minSize = WindowSizing.minimumSize
        window.styleMask.formUnion([.resizable, .closable, .miniaturizable, .titled])
        cascadeWindowBeforeDisplay(window)

        let windowController = NSWindowController(window: window)
        addWindowController(windowController)
        windowController.synchronizeWindowTitleWithDocumentName()
        window.standardWindowButton(.closeButton)?.isEnabled = false
        conversionIsActive = true
        MacOSApplicationModel.shared.conversionDidStart()

        viewModel.onPDFReady = { [weak self, weak window, weak windowController] url in
            guard let self else { return }
            convertedPDFURL = url
            updateChangeCount(.changeCleared)
            if let window {
                resizeWindowForFirstPDFPage(at: url, window: window)
            }
            showInitialWindowIfNeeded()
            windowController?.synchronizeWindowTitleWithDocumentName()
        }
        viewModel.onShouldShowWindow = { [weak self] in
            self?.showInitialWindowIfNeeded()
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
        guard let source = convertedPDFURL else { throw ConversionFailure.outputMissing }
        try FileManager.default.copyItem(at: source, to: url)
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

    override func close() {
        super.close()
        viewModel.clearWorkspace()
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

    private func resizeWindowForFirstPDFPage(at url: URL, window: NSWindow) {
        guard let document = PDFDocument(url: url),
              let firstPage = document.page(at: 0),
              let screen = window.screen ?? NSScreen.main
        else { return }

        let pageBounds = firstPage.bounds(for: .cropBox)
        guard pageBounds.width > 0, pageBounds.height > 0 else { return }

        let visibleFrame = screen.visibleFrame
        let currentTopLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        let contentFrame = window.contentRect(forFrameRect: window.frame)
        let frameInsetWidth = window.frame.width - contentFrame.width
        let frameInsetHeight = window.frame.height - contentFrame.height

        let availableFrameWidth = max(
            WindowSizing.minimumSize.width,
            visibleFrame.maxX - currentTopLeft.x
        )
        let availableFrameHeight = max(
            WindowSizing.minimumSize.height,
            currentTopLeft.y - visibleFrame.minY
        )
        let maximumFrameHeight = min(
            availableFrameHeight,
            WindowSizing.maximumContentHeightOnLargeDisplays + frameInsetHeight
        )
        let maximumContentSize = NSSize(
            width: max(
                WindowSizing.minimumSize.width - frameInsetWidth,
                min(availableFrameWidth, visibleFrame.width * WindowSizing.maximumScreenWidthFraction) - frameInsetWidth
            ),
            height: max(
                WindowSizing.minimumSize.height - frameInsetHeight,
                maximumFrameHeight - frameInsetHeight
            )
        )

        let availablePageWidth = maximumContentSize.width - WindowSizing.pagePadding.width
        let availablePageHeight = maximumContentSize.height - WindowSizing.pagePadding.height
        let scale = min(
            1.0,
            availablePageWidth / pageBounds.width,
            availablePageHeight / pageBounds.height
        )

        let targetContentSize = NSSize(
            width: min(
                maximumContentSize.width,
                max(WindowSizing.minimumSize.width - frameInsetWidth, pageBounds.width * scale + WindowSizing.pagePadding.width)
            ),
            height: min(
                maximumContentSize.height,
                max(WindowSizing.minimumSize.height - frameInsetHeight, pageBounds.height * scale + WindowSizing.pagePadding.height)
            )
        )
        setContentSizePreservingTopLeft(targetContentSize, for: window)
    }

    private func setContentSizePreservingTopLeft(_ contentSize: NSSize, for window: NSWindow) {
        let currentTopLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        let targetFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))
        let targetOrigin = NSPoint(
            x: currentTopLeft.x,
            y: currentTopLeft.y - targetFrame.height
        )
        window.setFrame(NSRect(origin: targetOrigin, size: targetFrame.size), display: true)
    }
}
