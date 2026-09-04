import AppKit

@MainActor
final class MacOSImagePolicySheetController: NSViewController, NSWindowDelegate {
    var onFinish: ((JoboptionsChangeSet?) -> Void)?

    private struct PolicyControls {
        let kind: SemanticJoboptions.ImageKind
        let resolution: PolicyTextField
        let policy: NSPopUpButton
        let resolutionRow: NSView
        let policyRow: NSView
    }

    private let session: JoboptionsEditingSession
    private let openingDocument: LosslessJoboptionsDocument
    private var controls: [PolicyControls] = []
    private var didFinish = false

    init(session: JoboptionsEditingSession) {
        self.session = session
        openingDocument = session.document
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
        try? session.restore(openingDocument)
        finish(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        try? session.restore(openingDocument)
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

        let rawResolution = session.document.value(forKey: "\(prefix)ImageMinResolution")
        let resolution = PolicyTextField(
            rawResolution?.textualValue ?? rawResolution?.postScript ?? ""
        )
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
        let rawPolicy = session.document.value(forKey: "\(prefix)ImageMinResolutionPolicy")
        let current = rawPolicy?.textualValue
        if current == nil {
            let item = NSMenuItem(title: String(localized: "Not set"), action: nil, keyEquivalent: "")
            item.representedObject = "__not_set__"
            policy.menu?.addItem(item)
        } else if !SemanticJoboptions.ImagePolicy.allCases.contains(where: { $0.rawValue == current }) {
            let item = NSMenuItem(
                title: String.localizedStringWithFormat(String(localized: "Custom: %@"), current ?? ""),
                action: nil,
                keyEquivalent: ""
            )
            item.representedObject = current
            policy.menu?.addItem(item)
        }
        for value in SemanticJoboptions.ImagePolicy.allCases {
            let item = NSMenuItem(title: localizedPolicy(value), action: nil, keyEquivalent: "")
            item.representedObject = value.rawValue
            policy.menu?.addItem(item)
        }
        let selected = current ?? "__not_set__"
        if let index = policy.itemArray.firstIndex(where: { ($0.representedObject as? String) == selected }) {
            policy.selectItem(at: index)
        }
        let policyPath = "/\(prefix)ImageMinResolutionPolicy"
        policy.toolTip = policyPath
        policy.setAccessibilityHelp(policyPath)
        policy.widthAnchor.constraint(equalToConstant: 300).isActive = true

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

        resolution.onChange = { [weak self] text in
            guard let value = Int(text), (1...9_600).contains(value) else { return false }
            do {
                try self?.session.apply(JoboptionsChangeSet([
                    JoboptionsChange(
                        "/\(prefix)ImageMinResolution",
                        .number(Double(value), original: String(value))
                    )
                ]))
                self?.updateHighlights()
                return true
            } catch {
                return false
            }
        }
        policy.target = self
        policy.action = #selector(policyChanged(_:))
        policy.identifier = NSUserInterfaceItemIdentifier(prefix)
        controls.append(PolicyControls(
            kind: kind,
            resolution: resolution,
            policy: policy,
            resolutionRow: resolutionRow,
            policyRow: policyRow
        ))

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
        updateHighlights()
        return box
    }

    private func localizedPolicy(_ policy: SemanticJoboptions.ImagePolicy) -> String {
        switch policy {
        case .ignore: String(localized: "Ignore")
        case .warn: String(localized: "Warning")
        case .error: String(localized: "Report an error")
        }
    }

    @objc private func cancel(_ sender: Any?) {
        try? session.restore(openingDocument)
        finish(nil)
    }

    @objc private func confirm(_ sender: Any?) {
        view.window?.endEditing(for: nil)
        guard controls.allSatisfy({ $0.resolution.validateCurrentValue() }) else {
            NSSound.beep()
            return
        }
        finish(JoboptionsChangeSet([]))
    }

    @objc private func policyChanged(_ sender: NSPopUpButton) {
        guard let prefix = sender.identifier?.rawValue,
              let raw = sender.selectedItem?.representedObject as? String,
              SemanticJoboptions.ImagePolicy(rawValue: raw) != nil
        else { return }
        do {
            try session.apply(JoboptionsChangeSet([
                JoboptionsChange("/\(prefix)ImageMinResolutionPolicy", .name(raw))
            ]))
            updateHighlights()
        } catch {
            NSSound.beep()
        }
    }

    private func updateHighlights() {
        let index = JoboptionsConsistencyIssueIndex(session.issues)
        let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let color = isDark
            ? NSColor(calibratedRed: 0.46, green: 0.29, blue: 0.07, alpha: 0.72)
            : NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.48, alpha: 0.58)
        for control in controls {
            let prefix = control.kind.rawValue
            for (row, path) in [
                (control.resolutionRow, JoboptionsKeyPath("/\(prefix)ImageMinResolution")),
                (control.policyRow, JoboptionsKeyPath("/\(prefix)ImageMinResolutionPolicy"))
            ] {
                row.wantsLayer = true
                row.layer?.cornerRadius = 6
                row.layer?.backgroundColor = index.affects(path) ? color.cgColor : NSColor.clear.cgColor
            }
        }
    }

    private func finish(_ changes: JoboptionsChangeSet?) {
        guard !didFinish else { return }
        didFinish = true
        onFinish?(changes)
    }

    private final class PolicyTextField: NSTextField, NSTextFieldDelegate {
        var onChange: ((String) -> Bool)?
        private var hasUserEdited = false

        init(_ value: String) {
            super.init(frame: .zero)
            stringValue = value
            delegate = self
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        func controlTextDidChange(_ obj: Notification) {
            hasUserEdited = true
            _ = validateCurrentValue()
        }

        @discardableResult
        func validateCurrentValue() -> Bool {
            guard hasUserEdited else { return true }
            let valid = onChange?(stringValue) ?? true
            backgroundColor = valid ? .textBackgroundColor : .systemRed.withAlphaComponent(0.16)
            return valid
        }
    }
}
