import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class MacOSJoboptionsManagementViewController: NSViewController,
    NSTableViewDataSource,
    NSTableViewDelegate,
    NSWindowDelegate {
    var onFinish: (() -> Void)?

    private enum Row {
        case group(String)
        case record(JoboptionsRecord)
    }

    private let repository: JoboptionsRepository
    private let tableView = NSTableView()
    private let saveAsButton = NSButton()
    private let importButton = NSButton()
    private let exportButton = NSButton()
    private let duplicateButton = NSButton()
    private let deleteButton = NSButton()
    private var rows: [Row] = []
    private var observation: AnyCancellable?
    private var didFinish = false

    init(repository: JoboptionsRepository) {
        self.repository = repository
        super.init(nibName: nil, bundle: nil)
        observation = repository.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.reload()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView()

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("joboptions"))
        column.title = String(localized: "Joboptions")
        column.minWidth = 420
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowSizeStyle = .medium
        tableView.allowsEmptySelection = false
        tableView.dataSource = self
        tableView.delegate = self

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        configure(saveAsButton, title: String(localized: "Save As..."), action: #selector(saveAs(_:)))
        configure(importButton, title: String(localized: "Import..."), action: #selector(importJoboptions(_:)))
        configure(exportButton, title: String(localized: "Export..."), action: #selector(exportJoboptions(_:)))
        configure(duplicateButton, title: String(localized: "Duplicate"), action: #selector(duplicate(_:)))
        configure(deleteButton, title: String(localized: "Delete"), action: #selector(deleteSelected(_:)))
        deleteButton.contentTintColor = .systemRed

        let doneButton = NSButton(
            title: String(localized: "Done"),
            target: self,
            action: #selector(done(_:))
        )
        doneButton.keyEquivalent = "\r"

        let buttonRow = NSStackView(views: [
            saveAsButton, importButton, exportButton, duplicateButton, deleteButton,
            NSView(), doneButton
        ])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.views[5].setContentHuggingPriority(.defaultLow, for: .horizontal)

        view.addSubview(scrollView)
        view.addSubview(buttonRow)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            scrollView.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -16),
            buttonRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            buttonRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            buttonRow.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
        ])
        reload()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.delegate = self
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        guard rows.indices.contains(row) else { return false }
        if case .group = rows[row] { return true }
        return false
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byTruncatingMiddle
        switch rows[row] {
        case let .group(title):
            field.stringValue = title
            field.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
            field.textColor = .secondaryLabelColor
        case let .record(record):
            let isActive = repository.activeRecord?.id == record.id
            field.stringValue = "\(isActive ? "✓  " : "   ")\(record.name)"
            field.toolTip = record.url.path
        }
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let record = selectedRecord else {
            updateButtons()
            return
        }
        if repository.activeRecord?.id != record.id {
            do { try repository.activate(record) }
            catch { present(error) }
        }
        updateButtons()
        tableView.reloadData()
    }

    func windowWillClose(_ notification: Notification) {
        finish()
    }

    private var selectedRecord: JoboptionsRecord? {
        guard rows.indices.contains(tableView.selectedRow),
              case let .record(record) = rows[tableView.selectedRow]
        else { return nil }
        return record
    }

    private func reload() {
        rows = [
            .group(String(localized: "Bundled"))
        ] + repository.records.filter(\.isBundled).map(Row.record) + [
            .group(String(localized: "User"))
        ] + repository.records.filter { !$0.isBundled }.map(Row.record)
        tableView.reloadData()
        if let activeID = repository.activeRecord?.id,
           let index = rows.firstIndex(where: {
               if case let .record(record) = $0 { return record.id == activeID }
               return false
           }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            tableView.scrollRowToVisible(index)
        }
        updateButtons()
    }

    private func updateButtons() {
        let record = selectedRecord
        saveAsButton.isEnabled = repository.activeDocument != nil
        exportButton.isEnabled = record != nil
        duplicateButton.isEnabled = record != nil
        deleteButton.isEnabled = record?.isBundled == false
    }

    @objc private func saveAs(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Save Joboptions As")
        alert.informativeText = String(localized: "Enter a name for the new user Joboptions.")
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let field = NSTextField(string: repository.activeName)
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field
        guard let window = view.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            do { _ = try repository.saveAs(name: field.stringValue) }
            catch { present(error) }
        }
    }

    @objc private func importJoboptions(_ sender: Any?) {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.joboptions, .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let sourceURL = panel.url else { return }
            Task { @MainActor in
                let accessed = sourceURL.startAccessingSecurityScopedResource()
                defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }
                let workspace = MacOSDocumentWorkspace()
                do {
                    let stagedURL = try await workspace.stageInput(from: sourceURL)
                    try await MacOSApplicationModel.shared.conversionCoordinator.validate(
                        joboptionsURL: stagedURL
                    )
                    _ = try repository.importJoboptions(from: stagedURL)
                    try? await workspace.clear()
                } catch {
                    try? await workspace.clear()
                    present(error)
                }
            }
        }
    }

    @objc private func exportJoboptions(_ sender: Any?) {
        guard let record = selectedRecord, let window = view.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.joboptions]
        panel.nameFieldStringValue = record.name + ".joboptions"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let destination = panel.url, let self else { return }
            do {
                try Data(contentsOf: record.url).write(to: destination, options: [.atomic])
            } catch { present(error) }
        }
    }

    @objc private func duplicate(_ sender: Any?) {
        guard let record = selectedRecord else { return }
        do { _ = try repository.duplicate(record) }
        catch { present(error) }
    }

    @objc private func deleteSelected(_ sender: Any?) {
        guard let record = selectedRecord, !record.isBundled else { return }
        do { try repository.delete(record) }
        catch { present(error) }
    }

    @objc private func done(_ sender: Any?) { finish() }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        onFinish?()
    }

    private func configure(_ button: NSButton, title: String, action: Selector) {
        button.title = title
        button.target = self
        button.action = action
        button.bezelStyle = .rounded
    }

    private func present(_ error: Error) {
        repository.lastError = error.localizedDescription
        guard let window = view.window else { return }
        NSAlert(error: error).beginSheetModal(for: window)
    }
}
