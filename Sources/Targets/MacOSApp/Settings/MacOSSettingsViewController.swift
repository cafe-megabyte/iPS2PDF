import AppKit
import Combine

@MainActor
final class MacOSSettingsViewController: NSViewController {
    private let repository: JoboptionsRepository
    private let joboptionsPopup = NSPopUpButton()
    private let versionPopup = NSPopUpButton()
    private let pdfaPopup = NSPopUpButton()
    private let configureButton = NSButton()
    private let manageButton = NSButton()
    private var observation: AnyCancellable?
    private var detailWindowController: NSWindowController?
    private var managementWindowController: NSWindowController?

    init(repository: JoboptionsRepository) {
        self.repository = repository
        super.init(nibName: nil, bundle: nil)
        JoboptionsEditingSession.cleanupStaleDirectories()
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

        configurePopup(joboptionsPopup, action: #selector(selectJoboptions(_:)))
        configurePopup(versionPopup, action: #selector(selectVersion(_:)))
        configurePopup(pdfaPopup, action: #selector(selectPDFA(_:)))

        configureButton.title = String(localized: "Configure...")
        configureButton.bezelStyle = .rounded
        configureButton.target = self
        configureButton.action = #selector(showDetailEditor(_:))

        manageButton.title = String(localized: "Manage Joboptions...")
        manageButton.bezelStyle = .rounded
        manageButton.target = self
        manageButton.action = #selector(showManagement(_:))

        let grid = NSGridView(views: [
            [label(String(localized: "Active Joboptions")), joboptionsPopup],
            [label(String(localized: "PDF version")), versionPopup],
            [label(String(localized: "PDF/A compatibility")), pdfaPopup]
        ])
        grid.rowSpacing = 12
        grid.columnSpacing = 16
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = NSStackView(views: [manageButton, NSView(), configureButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.distribution = .fill
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.views[1].setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [grid, buttonRow])
        stack.orientation = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24),
            joboptionsPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 250),
            versionPopup.widthAnchor.constraint(equalTo: joboptionsPopup.widthAnchor),
            pdfaPopup.widthAnchor.constraint(equalTo: joboptionsPopup.widthAnchor)
        ])

        joboptionsPopup.nextKeyView = versionPopup
        versionPopup.nextKeyView = pdfaPopup
        pdfaPopup.nextKeyView = manageButton
        manageButton.nextKeyView = configureButton
        configureButton.nextKeyView = joboptionsPopup
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Task { [weak self] in
            guard let self else { return }
            await repository.waitUntilReady()
            reload()
        }
    }

    private func reload() {
        reloadJoboptions()
        reloadVersions()
        reloadPDFA()
        versionPopup.isEnabled = repository.activeStandard == .none
        configureButton.isEnabled = repository.activeDocument != nil
    }

    private func reloadJoboptions() {
        let selectedID = repository.activeRecord?.id
        joboptionsPopup.removeAllItems()

        addJoboptionsSection(
            title: String(localized: "Bundled"),
            records: repository.records.filter(\.isBundled)
        )
        addJoboptionsSection(
            title: String(localized: "User"),
            records: repository.records.filter { !$0.isBundled }
        )

        let selectedIndex = joboptionsPopup.itemArray.firstIndex {
            ($0.representedObject as? String) == selectedID
        } ?? joboptionsPopup.itemArray.firstIndex {
            $0.representedObject is String
        }
        if let index = selectedIndex {
            joboptionsPopup.selectItem(at: index)
        }
    }

    private func addJoboptionsSection(title: String, records: [JoboptionsRecord]) {
        guard !records.isEmpty else { return }
        joboptionsPopup.menu?.addItem(.sectionHeader(title: title))
        for record in records {
            let item = NSMenuItem(title: record.name, action: nil, keyEquivalent: "")
            item.representedObject = record.id
            joboptionsPopup.menu?.addItem(item)
        }
    }

    private func reloadVersions() {
        versionPopup.removeAllItems()
        for version in PDFVersion.allCases {
            let item = NSMenuItem(title: version.title, action: nil, keyEquivalent: "")
            item.representedObject = version.rawValue
            versionPopup.menu?.addItem(item)
        }
        let displayedVersion = repository.activeStandard.requiredCompatibilityLevel
            ?? selectedPDFACompatibility.requiredPDFVersion?.rawValue
            ?? repository.compatibilityLevel
        if let index = PDFVersion.allCases.firstIndex(where: {
            $0.rawValue == displayedVersion
        }) {
            versionPopup.selectItem(at: index)
        }
    }

    private func reloadPDFA() {
        let choices = PDFACompatibility.allCases
        pdfaPopup.removeAllItems()
        for choice in choices {
            let item = NSMenuItem(title: choice.title, action: nil, keyEquivalent: "")
            item.representedObject = choice.rawValue
            pdfaPopup.menu?.addItem(item)
        }
        let selected = selectedPDFACompatibility
        pdfaPopup.selectItem(at: choices.firstIndex(of: selected) ?? 0)
    }

    private var selectedPDFACompatibility: PDFACompatibility {
        switch repository.activeStandard {
        case .pdfa1b: .pdfa1b
        case .pdfa2b: .pdfa2b
        case .pdfa3b: .pdfa3b
        default: .none
        }
    }

    @objc private func selectJoboptions(_ sender: NSPopUpButton) {
        guard let id = sender.selectedItem?.representedObject as? String,
              let record = repository.records.first(where: { $0.id == id })
        else { return }
        do { try repository.activate(record) }
        catch { present(error) }
    }

    @objc private func selectVersion(_ sender: NSPopUpButton) {
        guard repository.activeStandard == .none,
              let raw = sender.selectedItem?.representedObject as? String,
              let version = PDFVersion(rawValue: raw)
        else { reload(); return }
        do {
            try repository.update(
                key: "CompatibilityLevel",
                value: .number(Double(version.rawValue) ?? 1.3, original: version.rawValue)
            )
        } catch { present(error) }
    }

    @objc private func selectPDFA(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let choice = PDFACompatibility(rawValue: raw)
        else { return }
        let standard: PDFStandard = switch choice {
        case .none: .none
        case .pdfa1b: .pdfa1b
        case .pdfa2b: .pdfa2b
        case .pdfa3b: .pdfa3b
        }
        do { try repository.setStandard(standard) }
        catch { present(error) }
    }

    @objc private func showDetailEditor(_ sender: Any?) {
        guard detailWindowController == nil, let parentWindow = view.window else { return }
        do {
            let session = try JoboptionsEditingSession(repository: repository)
            let controller = MacOSDistillerEditorViewController(
                session: session,
                repository: repository
            )
            let window = NSWindow(contentViewController: controller)
            window.title = String.localizedStringWithFormat(
                String(localized: "PDF settings: %@"),
                repository.activeName
            )
            window.setContentSize(NSSize(width: 900, height: 670))
            window.minSize = NSSize(width: 760, height: 560)
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            let windowController = NSWindowController(window: window)
            detailWindowController = windowController
            controller.onFinish = { [weak self, weak parentWindow, weak window] commits in
                guard let self else { return }
                if commits { try session.commit() } else { session.cancel() }
                if let window, let parentWindow { parentWindow.endSheet(window) }
                detailWindowController = nil
                reload()
            }
            parentWindow.beginSheet(window)
        } catch {
            present(error)
        }
    }

    @objc private func showManagement(_ sender: Any?) {
        guard managementWindowController == nil, let parentWindow = view.window else { return }
        let controller = MacOSJoboptionsManagementViewController(repository: repository)
        let window = NSWindow(contentViewController: controller)
        window.title = String(localized: "Manage Joboptions")
        window.setContentSize(NSSize(width: 700, height: 520))
        window.minSize = NSSize(width: 620, height: 430)
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        let windowController = NSWindowController(window: window)
        managementWindowController = windowController
        controller.onFinish = { [weak self, weak parentWindow, weak window] in
            guard let self else { return }
            if let window, let parentWindow { parentWindow.endSheet(window) }
            managementWindowController = nil
            reload()
        }
        parentWindow.beginSheet(window)
    }

    private func configurePopup(_ popup: NSPopUpButton, action: Selector) {
        popup.target = self
        popup.action = action
        popup.controlSize = .regular
    }

    private func label(_ title: String) -> NSTextField {
        let field = NSTextField(labelWithString: title)
        field.alignment = .right
        return field
    }

    private func present(_ error: Error) {
        repository.lastError = error.localizedDescription
        guard let window = view.window else { return }
        NSAlert(error: error).beginSheetModal(for: window)
    }
}
