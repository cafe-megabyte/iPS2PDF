import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class MacOSPDFInfoViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuItemValidation, MacOSPostScriptExportProviding {
    private let session: PDFInspectionSession
    private let actions: PDFEditingActions
    private var actionsObservation: AnyCancellable?
    private let metadataButton = NSButton(title: String(localized: "Remove metadata"), target: nil, action: nil)
    private let compressionButton = NSButton(title: String(localized: "Compress PDF…"), target: nil, action: nil)
    private let signatureButton = NSButton(title: String(localized: "Sign PDF…"), target: nil, action: nil)
    private let savePDFButton = NSButton(title: String(localized: "Export edited PDF…"), target: nil, action: nil)
    private let moreButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let postScriptMenuItem = NSMenuItem(
        title: String(localized: "Export as PostScript…"),
        action: nil,
        keyEquivalent: ""
    )
    private let encryptedPostScriptMenuItem = NSMenuItem(
        title: String(localized: "Export as Encrypted PostScript…"),
        action: nil,
        keyEquivalent: ""
    )
    private let undoPDFButton = NSButton(title: "", target: nil, action: nil)
    private let redoPDFButton = NSButton(title: "", target: nil, action: nil)
    private let cancelProcessingButton = NSButton(title: String(localized: "Cancel"), target: nil, action: nil)
    private let processingStatus = NSTextField(labelWithString: "")
    private var category = PDFInfoCategory.overview
    private var observation: AnyCancellable?
    private var items: [PDFOutlineItem] = []
    private var expanded: Set<String> = []
    private var collapsed: Set<String> = []
    private var isReloading = false
    private let outline = NSOutlineView()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let statusBox = NSStackView()
    private let detailsButton = NSButton(title: String(localized: "Details"), target: nil, action: nil)
    private let warning = NSButton(title: "", target: nil, action: nil)
    private let warningBox = NSBox()
    private let passwordBox = NSStackView()
    private let password = NSSecureTextField()
    private let passwordStatus = NSTextField(wrappingLabelWithString: "")
    private let copyButton = NSButton(title: String(localized: "Copy report"), target: nil, action: nil)
    private let saveRTFButton = NSButton(title: String(localized: "Save .rtf"), target: nil, action: nil)
    private let saveTXTButton = NSButton(title: String(localized: "Save .txt"), target: nil, action: nil)
    private let exportResourcesButton = NSButton(title: String(localized: "Export All Resources…"), target: nil, action: nil)
    private var resourceExportTask: Task<Void, Never>?
    private var isExportingResources = false
    private var resourceExportStatus = ""
    private var categoryButtons: [NSButton] = []

    init(session: PDFInspectionSession, editing: PDFEditingSession?) {
        self.session = session
        actions = PDFEditingActions(inspection: session, editing: editing)
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }
    override func loadView() {
        view = NSView()
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16), root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16), root.topAnchor.constraint(equalTo: view.topAnchor, constant: 14), root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)])
        let title = NSTextField(wrappingLabelWithString: session.report.fileName); title.font = .preferredFont(forTextStyle: .title2); title.isSelectable = true
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        copyButton.target = self; copyButton.action = #selector(copyReport)
        saveRTFButton.target = self; saveRTFButton.action = #selector(saveRTFReport)
        saveTXTButton.target = self; saveTXTButton.action = #selector(saveTXTReport)
        exportResourcesButton.target = self; exportResourcesButton.action = #selector(exportAllPDFResources(_:))
        exportResourcesButton.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
        exportResourcesButton.imagePosition = .imageLeading
        saveRTFButton.setAccessibilityIdentifier("pdf-save-rtf-report")
        saveTXTButton.setAccessibilityIdentifier("pdf-save-txt-report")
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [title, spacer, copyButton, saveRTFButton, saveTXTButton, exportResourcesButton]); header.spacing = 12
        root.addArrangedSubview(header); header.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        warning.target = self; warning.action = #selector(showMissingFonts); warning.bezelStyle = .inline
        warning.isBordered = false
        warning.alignment = .left; warning.font = .boldSystemFont(ofSize: 13)
        warning.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil); warning.imagePosition = .imageLeading
        warningBox.boxType = .custom; warningBox.borderWidth = 0; warningBox.cornerRadius = 8
        warningBox.fillColor = MacOSPDFReportSharing.warningColor
        warningBox.contentView = warning
        warningBox.contentViewMargins = NSSize(width: 10, height: 8)
        root.addArrangedSubview(warningBox); warningBox.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        warningBox.heightAnchor.constraint(equalToConstant: 44).isActive = true
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        status.maximumNumberOfLines = 2; status.lineBreakMode = .byTruncatingTail
        status.setAccessibilityIdentifier("pdf-analysis-status")
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailsButton.target = self; detailsButton.action = #selector(showAnalysisDetails)
        detailsButton.setAccessibilityIdentifier("pdf-analysis-details")
        statusBox.addArrangedSubview(status); statusBox.addArrangedSubview(NSView()); statusBox.addArrangedSubview(detailsButton)
        statusBox.spacing = 8
        root.addArrangedSubview(statusBox)
        NSLayoutConstraint.activate([statusBox.widthAnchor.constraint(equalTo: root.widthAnchor), statusBox.heightAnchor.constraint(lessThanOrEqualToConstant: 36), status.heightAnchor.constraint(lessThanOrEqualToConstant: 32)])
        passwordBox.orientation = .vertical; passwordBox.alignment = .leading; passwordBox.spacing = 8
        password.placeholderString = String(localized: "Password"); password.target = self; password.action = #selector(unlock)
        let open = NSButton(title: String(localized: "Open"), target: self, action: #selector(unlock))
        passwordStatus.textColor = .systemRed
        passwordBox.addArrangedSubview(NSTextField(labelWithString: String(localized: "Enter the PDF opening password.")))
        passwordBox.addArrangedSubview(NSStackView(views: [password, open])); password.widthAnchor.constraint(equalToConstant: 260).isActive = true
        passwordBox.addArrangedSubview(passwordStatus)
        root.addArrangedSubview(passwordBox)
        let sidebar = NSStackView(); sidebar.orientation = .vertical; sidebar.alignment = .leading; sidebar.spacing = 5
        for (index, category) in PDFInfoCategory.allCases.enumerated() {
            let button = NSButton(title: category.title, target: self, action: #selector(selectCategory(_:)))
            button.tag = index; button.setButtonType(.pushOnPushOff); button.bezelStyle = .accessoryBarAction
            button.alignment = .left; button.image = NSImage(systemSymbolName: category.symbol, accessibilityDescription: nil); button.imagePosition = .imageLeading
            button.lineBreakMode = .byWordWrapping
            sidebar.addArrangedSubview(button); button.widthAnchor.constraint(equalToConstant: 170).isActive = true
            categoryButtons.append(button)
        }
        let fill = NSView(); sidebar.addArrangedSubview(fill)
        let labelColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("label")); labelColumn.title = String(localized: "Property"); labelColumn.width = 190; labelColumn.minWidth = 140
        let valueColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("value")); valueColumn.title = String(localized: "Value"); valueColumn.width = 420; valueColumn.minWidth = 160
        outline.addTableColumn(labelColumn); outline.addTableColumn(valueColumn); outline.outlineTableColumn = labelColumn
        outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outline.dataSource = self; outline.delegate = self; outline.selectionHighlightStyle = .regular
        outline.usesAlternatingRowBackgroundColors = true; outline.indentationPerLevel = 12
        outline.target = self; outline.doubleAction = #selector(showValue)
        let scroll = NSScrollView(); scroll.setAccessibilityIdentifier("pdf-information-table"); scroll.documentView = outline; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false; scroll.borderType = .bezelBorder
        let body = NSStackView(views: [sidebar, scroll]); body.alignment = .top; body.spacing = 14
        root.addArrangedSubview(body)
        NSLayoutConstraint.activate([body.widthAnchor.constraint(equalTo: root.widthAnchor), sidebar.widthAnchor.constraint(equalToConstant: 170), sidebar.heightAnchor.constraint(equalTo: body.heightAnchor), scroll.heightAnchor.constraint(equalTo: body.heightAnchor), scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160)])
        let hint = NSTextField(labelWithString: String(localized: "Double-click a value to show its full text.")); hint.font = .systemFont(ofSize: 10); hint.textColor = .secondaryLabelColor
        root.addArrangedSubview(hint)
        metadataButton.target = self; metadataButton.action = #selector(removeMetadata)
        metadataButton.image = NSImage(systemSymbolName: "eraser", accessibilityDescription: nil)
        metadataButton.imagePosition = .imageLeading
        metadataButton.setAccessibilityIdentifier("pdf-remove-metadata")
        compressionButton.target = self; compressionButton.action = #selector(compressPDF(_:))
        compressionButton.image = NSImage(systemSymbolName: "arrow.down.right.and.arrow.up.left", accessibilityDescription: nil)
        compressionButton.imagePosition = .imageLeading
        compressionButton.setAccessibilityIdentifier("pdf-compress")
        signatureButton.target = self; signatureButton.action = #selector(signPDF(_:))
        signatureButton.image = NSImage(systemSymbolName: "signature", accessibilityDescription: nil)
        signatureButton.imagePosition = .imageLeading
        signatureButton.setAccessibilityIdentifier("pdf-sign")
        savePDFButton.target = self; savePDFButton.action = #selector(exportEditedPDF)
        moreButton.bezelStyle = .accessoryBarAction
        moreButton.addItem(withTitle: "")
        moreButton.lastItem?.image = NSImage(
            systemSymbolName: "ellipsis",
            accessibilityDescription: String(localized: "More export options")
        )
        postScriptMenuItem.action = #selector(exportAsPostScript)
        postScriptMenuItem.target = self
        moreButton.menu?.addItem(postScriptMenuItem)
        encryptedPostScriptMenuItem.action = #selector(exportAsEncryptedPostScript)
        encryptedPostScriptMenuItem.target = self
        moreButton.menu?.addItem(encryptedPostScriptMenuItem)
        moreButton.setAccessibilityLabel(String(localized: "More export options"))
        undoPDFButton.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: String(localized: "Undo PDF edit"))
        redoPDFButton.image = NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: String(localized: "Redo PDF edit"))
        undoPDFButton.target = self; undoPDFButton.action = #selector(undoPDFEdit)
        redoPDFButton.target = self; redoPDFButton.action = #selector(redoPDFEdit)
        cancelProcessingButton.target = self; cancelProcessingButton.action = #selector(cancelProcessing)
        processingStatus.font = .systemFont(ofSize: 11); processingStatus.textColor = .secondaryLabelColor
        let tools = NSStackView(views: [metadataButton, compressionButton, signatureButton, NSView(), undoPDFButton, redoPDFButton, savePDFButton, moreButton])
        tools.spacing = 10; root.addArrangedSubview(tools)
        tools.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        let progress = NSStackView(views: [processingStatus, NSView(), cancelProcessingButton])
        root.addArrangedSubview(progress); progress.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        MacOSApplicationModel.shared.postScriptExportController.register(self)
        observation = session.objectWillChange.sink { [weak self] _ in Task { @MainActor [weak self] in self?.refresh() } }
        actionsObservation = actions.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh(); self?.showProcessingFeedback() }
        }
        refresh()
    }
    private func refresh() {
        let report = session.report
        warningBox.isHidden = report.warningSummary == nil
        warning.title = report.warningSummary ?? ""
        warning.setAccessibilityLabel(report.warningSummary ?? "")
        var summary: [String] = []
        if session.isReading {
            summary.append(report.pageCount > 0 ? String.localizedStringWithFormat(String(localized: "Reading page %lld of %lld"), Int64(report.pagesRead), Int64(report.pageCount)) : String(localized: "Reading PDF information…"))
        }
        if !report.notices.isEmpty {
            summary.append(String.localizedStringWithFormat(String(localized: "Analysis incomplete — %lld notices"), Int64(report.notices.count)))
        }
        if let error = session.errorMessage { summary = [error] }
        status.stringValue = summary.joined(separator: " · "); status.toolTip = status.stringValue
        statusBox.isHidden = summary.isEmpty
        detailsButton.isHidden = report.notices.isEmpty && session.errorMessage == nil
        passwordBox.isHidden = !report.isLocked
        password.isEnabled = !session.isReading
        passwordStatus.stringValue = session.passwordWasIncorrect ? String(localized: "The password is incorrect. Please try again.") : ""
        copyButton.isEnabled = !session.isReading && !report.isLocked && session.errorMessage == nil
        saveRTFButton.isEnabled = copyButton.isEnabled
        saveTXTButton.isEnabled = copyButton.isEnabled
        exportResourcesButton.isEnabled = copyButton.isEnabled && report.allowsResourceExporting && !report.exportableResources.isEmpty && !isExportingResources
        exportResourcesButton.toolTip = report.allowsResourceExporting ? nil : String(localized: "The PDF does not permit content copying.")
        metadataButton.isEnabled = copyButton.isEnabled && !actions.isProcessing && !isExportingResources
        undoPDFButton.isEnabled = actions.editing?.canUndo == true && !actions.isProcessing
        redoPDFButton.isEnabled = actions.editing?.canRedo == true && !actions.isProcessing
        savePDFButton.isEnabled = actions.editing?.isEdited == true && !actions.isProcessing
        compressionButton.isEnabled = metadataButton.isEnabled
        signatureButton.isEnabled = metadataButton.isEnabled
        postScriptMenuItem.isEnabled = postScriptExportInput != nil
        encryptedPostScriptMenuItem.isEnabled =
            postScriptExportInput != nil
                && MacOSApplicationModel.shared.postScriptEncryptionController.canPresent
        moreButton.isEnabled = postScriptMenuItem.isEnabled || encryptedPostScriptMenuItem.isEnabled
        cancelProcessingButton.isHidden = !actions.isProcessing && !isExportingResources
        processingStatus.stringValue = isExportingResources ? resourceExportStatus : (actions.isProcessing ? String(localized: "Removing metadata…") : "")
        categoryButtons.enumerated().forEach { $0.element.state = PDFInfoCategory.allCases[$0.offset] == category ? .on : .off }
        let sections = report.sections(in: category)
        isReloading = true
        items = sections.map(PDFOutlineItem.init(section:))
        if items.isEmpty, !session.isReading { items = [PDFOutlineItem(field: PDFInfoField("Entries", report.isComplete ? String(localized: "No entries found") : PDFInspectionFormat.unknown))] }
        outline.reloadData()
        for item in items {
            guard let section = item.section else { continue }
            let expandsInitially = category != .fonts && (section.initiallyExpanded || section.warning != nil)
            if expanded.contains(section.id) || (!collapsed.contains(section.id) && expandsInitially) { outline.expandItem(item) }
        }
        isReloading = false
    }
    func stopProcessing() {
        MacOSApplicationModel.shared.postScriptExportController.unregister(self)
        actions.cancel()
        resourceExportTask?.cancel()
        resourceExportTask = nil
    }
    @objc private func cancelProcessing() { actions.cancel(); resourceExportTask?.cancel(); resourceExportTask = nil; isExportingResources = false; refresh() }
    @objc private func undoPDFEdit() { actions.editing?.undo() }
    @objc private func redoPDFEdit() { actions.editing?.redo() }
    @objc func compressPDF(_ sender: Any?) {
        guard metadataButton.isEnabled else { return }
        do {
            let editing = try actions.editingSession()
            view.window?.identifier = NSUserInterfaceItemIdentifier("pdf-editing:" + editing.id.uuidString)
            MacOSPDFCompressionWindowController.present(editing: editing)
        }
        catch { actions.errorMessage = error.localizedDescription }
    }
    @objc private func signPDF(_ sender: Any?) {
        guard metadataButton.isEnabled else { return }
        do {
            let editing = try actions.editingSession()
            view.window?.identifier = NSUserInterfaceItemIdentifier("pdf-editing:" + editing.id.uuidString)
            MacOSPDFSignatureWindowController.present(editing: editing)
        } catch { actions.errorMessage = error.localizedDescription }
    }
    @objc private func removeMetadata() {
        guard session.report.hasConformityDeclaration else {
            actions.removeMetadata(preserveConformity: false)
            return
        }
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Preserve PDF conformity?")
        alert.informativeText = String(localized: "Preserving conformity retains only the metadata required by the declared PDF standard. The original file remains unchanged until you explicitly save or export.")
        alert.addButton(withTitle: String(localized: "Preserve conformity"))
        alert.addButton(withTitle: String(localized: "Discard conformity"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn || response == .alertSecondButtonReturn else { return }
            self?.actions.removeMetadata(preserveConformity: response == .alertFirstButtonReturn)
        }
    }
    private func showProcessingFeedback() {
        guard let window = view.window, let message = actions.errorMessage ?? actions.notice else { return }
        actions.errorMessage = nil; actions.notice = nil
        let alert = NSAlert(); alert.messageText = String(localized: "PDF information"); alert.informativeText = message
        alert.beginSheetModal(for: window)
    }
    @objc private func exportEditedPDF() {
        guard let window = view.window, let revision = actions.editing?.current else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]; panel.nameFieldStringValue = revision.input.fileName
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            Task {
                do {
                    try await Task.detached(priority: .userInitiated) {
                        // Copy the accepted immutable revision; PDFKit must not
                        // reserialize it and reintroduce producer/date metadata.
                        try Data(contentsOf: revision.input.url, options: .mappedIfSafe).write(to: destination, options: .atomic)
                    }.value
                } catch { self?.actions.errorMessage = error.localizedDescription }
            }
        }
    }
    @objc private func exportAsPostScript() {
        MacOSApplicationModel.shared.postScriptExportController.export(using: self)
    }

    @objc private func exportAsEncryptedPostScript() {
        guard let input = postScriptExportInput else {
            NSSound.beep()
            return
        }
        MacOSApplicationModel.shared.postScriptEncryptionController.exportEncrypted(
            input: input,
            parentWindow: view.window
        )
    }

    var postScriptExportInput: MacOSPostScriptExportInput? {
        guard !session.isReading, !session.report.isLocked,
              let input = actions.editing?.current?.input ?? session.currentInput
        else { return nil }
        return MacOSPostScriptExportInput(
            url: input.url,
            sourceName: input.fileName,
            inputPassword: actions.editing?.passwordForProcessing ?? session.unlockedPassword,
            retainedInput: input
        )
    }

    var postScriptExportWindow: NSWindow? { view.window }
    @objc private func selectCategory(_ sender: NSButton) { category = PDFInfoCategory.allCases[sender.tag]; refresh(); outline.scrollRowToVisible(0) }
    @objc private func showMissingFonts() { category = .fonts; for section in session.report.fontWarnings { expanded.insert(section.id); collapsed.remove(section.id) }; refresh(); outline.scrollRowToVisible(0) }
    @objc private func showAnalysisDetails() {
        if let error = session.errorMessage, let window = view.window {
            let alert = NSAlert(); alert.messageText = String(localized: "PDF information"); alert.informativeText = error; alert.beginSheetModal(for: window)
            return
        }
        category = .overview; expanded.insert("analysis-notices"); collapsed.remove("analysis-notices")
        refresh(); outline.scrollRowToVisible(0)
    }
    @objc private func unlock() { let value = password.stringValue; password.stringValue = ""; session.unlock(value) }
    @objc private func copyReport() {
        do { try MacOSPDFReportSharing.copy(session.report) }
        catch { if let window = view.window { NSAlert(error: error).beginSheetModal(for: window) } }
    }
    @objc private func saveRTFReport() { saveReport(formatted: true) }
    @objc private func saveTXTReport() { saveReport(formatted: false) }
    private func saveReport(formatted: Bool) {
        guard let window = view.window else { return }
        MacOSPDFReportSharing.export(session.report, formatted: formatted, window: window)
    }
    @objc func exportAllPDFResources(_ sender: Any?) {
        let resources = session.report.exportableResources
        guard !resources.isEmpty, session.report.allowsResourceExporting,
              !session.isReading, !isExportingResources, let window = view.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.folder]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = PDFResourceExporter.defaultFolderName(for: session.report.fileName)
        panel.message = String(localized: "Choose where to save all exportable PDF resources.")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let destination = panel.url, let self else { return }
            self.startResourceExport(resources, destination: destination)
        }
    }
    private func startResourceExport(_ resources: [PDFExtractableResource], destination: URL) {
        isExportingResources = true
        resourceExportStatus = String(localized: "Preparing resource export…")
        refresh()
        resourceExportTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await PDFResourceExporter.exportAll(resources, from: self.session, to: destination,
                                                        destinationAccess: .exactItem) { [weak self] update in
                    await MainActor.run {
                        guard let self else { return }
                        self.resourceExportStatus = update.completed == update.total
                            ? String(localized: "Finishing resource export…")
                            : String.localizedStringWithFormat(String(localized: "Exporting resource %lld of %lld: %@"), Int64(update.completed + 1), Int64(update.total), update.filename)
                        self.refresh()
                    }
                }
            } catch {
                if !(error is CancellationError) { self.actions.errorMessage = error.localizedDescription }
            }
            self.isExportingResources = false
            self.resourceExportTask = nil
            self.refresh()
        }
    }
    @objc private func exportResource(_ sender: PDFResourceExportButton) {
        guard let resource = sender.resource, session.report.allowsResourceExporting,
              !isExportingResources, let window = view.window else { return }
        let panel = NSSavePanel()
        if let type = UTType(filenameExtension: resource.format.pathExtension), !resource.format.pathExtension.isEmpty {
            panel.allowedContentTypes = [type]
        }
        panel.nameFieldStringValue = resource.suggestedFilename
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let destination = panel.url, let self else { return }
            self.isExportingResources = true
            self.resourceExportStatus = String.localizedStringWithFormat(String(localized: "Exporting resource: %@"), resource.suggestedFilename)
            self.refresh()
            self.resourceExportTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let artifact = try await PDFResourceExporter.extract(resource, from: session)
                    try await Task.detached(priority: .userInitiated) { try PDFResourceExporter.copy(artifact, to: destination) }.value
                } catch {
                    if !(error is CancellationError) { actions.errorMessage = error.localizedDescription }
                }
                isExportingResources = false
                resourceExportTask = nil
                refresh()
            }
        }
    }
    @objc private func showValue() {
        guard outline.clickedRow >= 0, let item = outline.item(atRow: outline.clickedRow) as? PDFOutlineItem, let field = item.field, let parent = view.window else { return }
        let text = NSTextView(); text.string = field.value; text.isEditable = false; text.isSelectable = true; text.font = .monospacedSystemFont(ofSize: 12, weight: .regular); text.textContainerInset = NSSize(width: 12, height: 12)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 660, height: 460)); scroll.hasVerticalScroller = true; scroll.documentView = text
        text.frame = scroll.contentView.bounds; text.isVerticallyResizable = true; text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        let alert = NSAlert(); alert.messageText = field.label; alert.accessoryView = scroll; alert.addButton(withTitle: String(localized: "Close")); alert.beginSheetModal(for: parent)
    }
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { (item as? PDFOutlineItem)?.children.count ?? items.count }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { (item as? PDFOutlineItem)?.children[index] ?? items[index] }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { !(item as! PDFOutlineItem).children.isEmpty }
    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        let item = item as! PDFOutlineItem
        guard let field = item.field else { return 34 }
        let width = max(140, outline.tableColumns.last?.width ?? 350) - 16
        let rect = (field.value as NSString).boundingRect(with: NSSize(width: width, height: 140), options: [.usesLineFragmentOrigin], attributes: [.font: NSFont.systemFont(ofSize: 12)])
        return min(150, max(34, ceil(rect.height) + 14))
    }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let item = item as! PDFOutlineItem
        let isLabel = tableColumn == outline.outlineTableColumn
        let value = isLabel ? (item.section?.title ?? item.field?.label ?? "") : (item.section?.warning ?? item.field?.value ?? "")
        let label = NSTextField(wrappingLabelWithString: value)
        label.isSelectable = item.field != nil; label.font = item.section == nil ? .systemFont(ofSize: 12) : .boldSystemFont(ofSize: 13)
        label.textColor = isLabel && item.section == nil ? .secondaryLabelColor : .labelColor
        label.maximumNumberOfLines = 8; label.lineBreakMode = .byTruncatingTail; label.translatesAutoresizingMaskIntoConstraints = false
        let cell = NSTableCellView(); cell.addSubview(label)
        var trailing = label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -5)
        if !isLabel, let resource = item.section?.resource {
            let button = PDFResourceExportButton(image: NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil) ?? NSImage(), target: self, action: #selector(exportResource(_:)))
            button.resource = resource
            button.bezelStyle = .accessoryBarAction
            button.isEnabled = session.report.allowsResourceExporting && !isExportingResources
            button.toolTip = session.report.allowsResourceExporting
                ? String.localizedStringWithFormat(String(localized: "Export %@…"), resource.kind.accessibilityName)
                : String(localized: "The PDF does not permit content copying.")
            button.setAccessibilityLabel(String.localizedStringWithFormat(String(localized: "Export %@"), resource.kind.accessibilityName))
            button.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(button)
            trailing = label.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -6)
            NSLayoutConstraint.activate([button.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -5), button.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
        }
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 5), trailing, label.topAnchor.constraint(equalTo: cell.topAnchor, constant: 6), label.bottomAnchor.constraint(lessThanOrEqualTo: cell.bottomAnchor, constant: -4)])
        return cell
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(exportAllPDFResources(_:)) { return exportResourcesButton.isEnabled }
        if menuItem.action == #selector(exportAsPostScript) { return postScriptExportInput != nil }
        if menuItem.action == #selector(exportAsEncryptedPostScript) {
            return postScriptExportInput != nil
                && MacOSApplicationModel.shared.postScriptEncryptionController.canPresent
        }
        return true
    }
    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let row = PDFInformationRowView()
        let item = item as! PDFOutlineItem
        let section = item.section ?? (outline.parent(forItem: item) as? PDFOutlineItem)?.section
        row.isProblem = section?.warning != nil
        row.emphasis = item.field?.emphasis
        return row
    }
    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !isReloading, let item = notification.userInfo?["NSObject"] as? PDFOutlineItem, let id = item.section?.id else { return }; expanded.insert(id); collapsed.remove(id)
    }
    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !isReloading, let item = notification.userInfo?["NSObject"] as? PDFOutlineItem, let id = item.section?.id else { return }; collapsed.insert(id); expanded.remove(id)
    }
}
