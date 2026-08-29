import AppKit

@MainActor
final class MacOSImagePolicySheetController: NSViewController, NSWindowDelegate {
    var onFinish: ((JoboptionsChangeSet?) -> Void)?

    private struct PolicyControls {
        let kind: SemanticJoboptions.ImageKind
        let resolution: NSTextField
        let policy: NSPopUpButton
    }

    private let session: JoboptionsEditingSession
    private var controls: [PolicyControls] = []
    private var didFinish = false

    init(session: JoboptionsEditingSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView()

        let sections = SemanticJoboptions.ImageKind.allCases.map(makePolicySection(for:))
        let policyStack = NSStackView(views: sections)
        policyStack.orientation = .vertical
        policyStack.alignment = .leading
        policyStack.spacing = 12
        sections.forEach {
            $0.widthAnchor.constraint(equalTo: policyStack.widthAnchor).isActive = true
        }

        let cancel = NSButton(title: String(localized: "Cancel"), target: self, action: #selector(cancel(_:)))
        cancel.keyEquivalent = "\u{1b}"
        let ok = NSButton(title: String(localized: "OK"), target: self, action: #selector(confirm(_:)))
        ok.keyEquivalent = "\r"
        let actionBar = NSStackView(views: [NSView(), cancel, ok])
        actionBar.orientation = .horizontal
        actionBar.spacing = 10
        actionBar.views[0].setContentHuggingPriority(.defaultLow, for: .horizontal)

        let content = NSStackView(views: [policyStack, actionBar])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 16
        content.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 16, right: 20)
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.topAnchor.constraint(equalTo: view.topAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            policyStack.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -40),
            actionBar.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -40)
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.delegate = self
    }

    override func cancelOperation(_ sender: Any?) {
        finish(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        finish(nil)
        return false
    }

    private func makePolicySection(for kind: SemanticJoboptions.ImageKind) -> NSView {
        let prefix = kind.rawValue
        let title = switch kind {
        case .color: String(localized: "Color images")
        case .grayscale: String(localized: "Grayscale images")
        case .monochrome: String(localized: "Monochrome images")
        }

        let configuration = SemanticJoboptions.imagePolicy(in: session.document, kind: kind)
        let resolution = NSTextField(string: String(configuration.minimumResolution ?? 150))
        resolution.formatter = integerFormatter(minimum: 1, maximum: 9_999)
        let resolutionPath = "/\(prefix)ImageMinResolution"
        resolution.toolTip = resolutionPath
        resolution.setAccessibilityHelp(resolutionPath)
        resolution.widthAnchor.constraint(equalToConstant: 90).isActive = true

        let unit = NSTextField(labelWithString: String(localized: "ppi"))
        unit.textColor = .secondaryLabelColor

        let resolutionLabel = NSTextField(labelWithString: String(localized: "Minimum resolution"))
        resolutionLabel.alignment = .right
        resolutionLabel.widthAnchor.constraint(equalToConstant: 180).isActive = true
        resolutionLabel.toolTip = resolutionPath
        resolutionLabel.setAccessibilityHelp(resolutionPath)

        let policy = NSPopUpButton()
        for value in SemanticJoboptions.ImagePolicy.allCases {
            let item = NSMenuItem(title: localizedPolicy(value), action: nil, keyEquivalent: "")
            item.representedObject = value.rawValue
            policy.menu?.addItem(item)
        }
        let current = configuration.policy?.rawValue ?? SemanticJoboptions.ImagePolicy.ignore.rawValue
        if let index = policy.itemArray.firstIndex(where: { ($0.representedObject as? String) == current }) {
            policy.selectItem(at: index)
        }
        let policyPath = "/\(prefix)ImageMinResolutionPolicy"
        policy.toolTip = policyPath
        policy.setAccessibilityHelp(policyPath)
        policy.widthAnchor.constraint(equalToConstant: 300).isActive = true

        controls.append(PolicyControls(kind: kind, resolution: resolution, policy: policy))
        let resolutionRow = NSStackView(views: [resolutionLabel, resolution, unit, NSView()])
        resolutionRow.orientation = .horizontal
        resolutionRow.alignment = .centerY
        resolutionRow.spacing = 10
        resolutionRow.views.last?.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let policySpacer = NSView()
        policySpacer.widthAnchor.constraint(equalToConstant: 180).isActive = true
        let policyRow = NSStackView(views: [policySpacer, policy, NSView()])
        policyRow.orientation = .horizontal
        policyRow.alignment = .centerY
        policyRow.spacing = 10
        policyRow.views.last?.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let rows = NSStackView(views: [resolutionRow, policyRow])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 10
        rows.translatesAutoresizingMaskIntoConstraints = false

        let box = NSBox()
        box.title = title
        box.titlePosition = .atTop
        box.boxType = .primary
        box.toolTip = "\(resolutionPath), \(policyPath)"
        box.contentView?.addSubview(rows)
        if let contentView = box.contentView {
            NSLayoutConstraint.activate([
                rows.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
                rows.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
                rows.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
                rows.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
            ])
        }
        box.heightAnchor.constraint(equalToConstant: 112).isActive = true
        return box
    }

    private func localizedPolicy(_ policy: SemanticJoboptions.ImagePolicy) -> String {
        switch policy {
        case .ignore: String(localized: "Ignore")
        case .warn: String(localized: "Warning")
        case .error: String(localized: "Report an error")
        }
    }

    private func integerFormatter(minimum: Int, maximum: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        formatter.minimum = NSNumber(value: minimum)
        formatter.maximum = NSNumber(value: maximum)
        return formatter
    }

    @objc private func cancel(_ sender: Any?) {
        finish(nil)
    }

    @objc private func confirm(_ sender: Any?) {
        var changes: [JoboptionsChange] = []
        for control in controls {
            let resolution = max(1, control.resolution.integerValue)
            let raw = control.policy.selectedItem?.representedObject as? String
            let policy = SemanticJoboptions.ImagePolicy(rawValue: raw ?? "") ?? .ignore
            changes.append(contentsOf: SemanticJoboptions.changeImagePolicy(
                kind: control.kind,
                minimumResolution: resolution,
                policy: policy
            ).changes)
        }
        finish(JoboptionsChangeSet(changes))
    }

    private func finish(_ changes: JoboptionsChangeSet?) {
        guard !didFinish else { return }
        didFinish = true
        onFinish?(changes)
    }
}
