import AppKit

@MainActor
final class MacOSDistillerEditorViewController: NSViewController, NSWindowDelegate {
    private enum Layout {
        static let sectionSpacing: CGFloat = 8
        static let formInsets = NSEdgeInsets(top: 6, left: 20, bottom: 16, right: 20)
        static let rowSpacing: CGFloat = 4
        static let compactRowHeight: CGFloat = 20
        static let labeledRowHeight: CGFloat = 30
        static let descriptionEditorHeight: CGFloat = 90
        static let labelWidth: CGFloat = 245
        static let controlMinWidth: CGFloat = 280
        static let sectionTopInset: CGFloat = 6
        static let sectionBottomInset: CGFloat = 8
        static let sectionChromeHeight: CGFloat = 22
    }

    var onFinish: ((Bool) throws -> Void)?

    private let session: JoboptionsEditingSession
    private let repository: JoboptionsRepository
    private let categoryControl = NSSegmentedControl()
    private let contentContainer = NSView()
    private let banner = MacOSConsistencyBannerView()
    private var bannerHeightConstraint: NSLayoutConstraint!
    private var selectedCategory: DistillerCategory = .general
    private var policyWindowController: NSWindowController?
    private var didFinish = false
    private weak var activeScrollView: NSScrollView?
    private weak var activeDocumentView: NSView?
    private weak var activeFormStack: NSStackView?
    private var activeFormHeightConstraint: NSLayoutConstraint?
    private var activeDocumentContentHeight: CGFloat = 0
    private var declaredMinimumHeights: [ObjectIdentifier: CGFloat] = [:]
    private var declaredHeightConstraints: [ObjectIdentifier: NSLayoutConstraint] = [:]
    private var highlightRegistrations: [(view: NSView, paths: [JoboptionsKeyPath])] = []

    init(session: JoboptionsEditingSession, repository: JoboptionsRepository) {
        self.session = session
        self.repository = repository
        super.init(nibName: nil, bundle: nil)
        session.onChange = { [weak self] in self?.sessionDidChange() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView()

        let categories = DistillerCategory.allCases
        categoryControl.segmentCount = categories.count
        for (index, category) in categories.enumerated() {
            categoryControl.setLabel(category.title, forSegment: index)
            categoryControl.setToolTip(category.title, forSegment: index)
        }
        categoryControl.selectedSegment = 0
        categoryControl.segmentStyle = .automatic
        categoryControl.target = self
        categoryControl.action = #selector(changeCategory(_:))
        categoryControl.translatesAutoresizingMaskIntoConstraints = false

        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        let cancelButton = NSButton(
            title: String(localized: "Cancel"),
            target: self,
            action: #selector(cancel(_:))
        )
        cancelButton.keyEquivalent = "\u{1b}"
        let okButton = NSButton(
            title: String(localized: "OK"),
            target: self,
            action: #selector(confirm(_:))
        )
        okButton.keyEquivalent = "\r"
        let actionBar = NSStackView(views: [NSView(), cancelButton, okButton])
        actionBar.orientation = .horizontal
        actionBar.spacing = 10
        actionBar.translatesAutoresizingMaskIntoConstraints = false
        actionBar.views[0].setContentHuggingPriority(.defaultLow, for: .horizontal)

        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.onRepair = { [weak self] in self?.repair() }
        banner.onHeightChange = { [weak self] height in self?.setBannerHeight(height) }

        view.addSubview(categoryControl)
        view.addSubview(contentContainer)
        view.addSubview(actionBar)
        view.addSubview(banner)
        bannerHeightConstraint = banner.heightAnchor.constraint(equalToConstant: 52)
        NSLayoutConstraint.activate([
            categoryControl.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            categoryControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            categoryControl.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 18),
            categoryControl.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -18),

            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: categoryControl.bottomAnchor, constant: 10),
            contentContainer.bottomAnchor.constraint(equalTo: actionBar.topAnchor, constant: -8),

            actionBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            actionBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            actionBar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),

            banner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            banner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            banner.bottomAnchor.constraint(equalTo: actionBar.topAnchor, constant: -8),
            bannerHeightConstraint
        ])

        buildSelectedCategory()
        updateBanner(animated: false)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.delegate = self
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        resizeActiveDocument()
    }

    override func cancelOperation(_ sender: Any?) {
        finish(commits: false)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        finish(commits: false)
        return false
    }

    @objc private func changeCategory(_ sender: NSSegmentedControl) {
        guard DistillerCategory.allCases.indices.contains(sender.selectedSegment) else { return }
        guard validateVisibleTextFields() else {
            sender.selectedSegment = DistillerCategory.allCases.firstIndex(of: selectedCategory) ?? 0
            return
        }
        selectedCategory = DistillerCategory.allCases[sender.selectedSegment]
        buildSelectedCategory()
    }

    @objc private func cancel(_ sender: Any?) { finish(commits: false) }
    @objc private func confirm(_ sender: Any?) {
        view.window?.endEditing(for: nil)
        guard validateVisibleTextFields() else { return }
        finish(commits: true)
    }

    private func finish(commits: Bool) {
        guard !didFinish else { return }
        do {
            try onFinish?(commits)
            didFinish = true
        } catch {
            present(error)
        }
    }

    private func sessionDidChange() {
        updateBanner(animated: true)
        updateConsistencyHighlights()
    }

    private func repair() {
        view.window?.endEditing(for: nil)
        guard validateVisibleTextFields() else { return }
        do {
            try session.repair()
            buildSelectedCategory()
        } catch { present(error) }
    }

    private func apply(_ changeSet: JoboptionsChangeSet) {
        do {
            try session.apply(changeSet)
        } catch { present(error) }
    }

    private func setStandard(_ standard: PDFStandard) {
        do {
            let showsNotice = try session.setStandard(standard)
            buildSelectedCategory()
            if showsNotice {
                presentPDFXOutputIntentNotice()
            }
        } catch { present(error) }
    }

    private func buildSelectedCategory() {
        activeScrollView = nil
        activeDocumentView = nil
        activeFormStack = nil
        activeFormHeightConstraint = nil
        activeDocumentContentHeight = 0
        highlightRegistrations.removeAll(keepingCapacity: true)
        declaredMinimumHeights.removeAll(keepingCapacity: true)
        declaredHeightConstraints.removeAll(keepingCapacity: true)
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .windowBackgroundColor
        scrollView.contentView.drawsBackground = true
        scrollView.contentView.backgroundColor = .windowBackgroundColor
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let formStack = FlippedStackView()
        formStack.orientation = .vertical
        formStack.alignment = .leading
        formStack.distribution = .fill
        formStack.spacing = Layout.sectionSpacing
        formStack.edgeInsets = Layout.formInsets
        formStack.translatesAutoresizingMaskIntoConstraints = false
        formStack.setContentHuggingPriority(.required, for: .vertical)
        formStack.setContentCompressionResistancePriority(.required, for: .vertical)

        if selectedCategory == .additional {
            buildAdditional(in: formStack)
        } else {
            buildCatalogCategory(selectedCategory, in: formStack)
        }

        let horizontalInsets = formStack.edgeInsets.left + formStack.edgeInsets.right
        for section in formStack.arrangedSubviews.compactMap({ $0 as? NSBox }) {
            section.widthAnchor.constraint(
                equalTo: formStack.widthAnchor,
                constant: -horizontalInsets
            ).isActive = true
        }

        activeDocumentContentHeight = documentContentHeight(for: formStack)

        let documentView = FlippedView(frame: NSRect(
            x: 0,
            y: 0,
            width: max(contentContainer.bounds.width, 760),
            height: max(activeDocumentContentHeight, 1)
        ))
        formStack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(formStack)
        let formHeightConstraint = formStack.heightAnchor.constraint(
            greaterThanOrEqualToConstant: activeDocumentContentHeight
        )
        NSLayoutConstraint.activate([
            formStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            formStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            formStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            formHeightConstraint,
            formStack.bottomAnchor.constraint(lessThanOrEqualTo: documentView.bottomAnchor)
        ])
        scrollView.documentView = documentView
        contentContainer.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
        activeScrollView = scrollView
        activeDocumentView = documentView
        activeFormStack = formStack
        activeFormHeightConstraint = formHeightConstraint
        resizeActiveDocument()
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        updateConsistencyHighlights()
    }

    private func resizeActiveDocument() {
        guard let scrollView = activeScrollView,
              let documentView = activeDocumentView
        else { return }
        let visibleSize = scrollView.contentSize
        guard visibleSize.width > 0, visibleSize.height > 0 else { return }

        let previousOrigin = scrollView.contentView.bounds.origin
        documentView.frame = NSRect(
            origin: .zero,
            size: NSSize(
                width: visibleSize.width,
                height: max(activeDocumentContentHeight, visibleSize.height)
            )
        )
        documentView.layoutSubtreeIfNeeded()

        let maximumX = max(documentView.frame.width - visibleSize.width, 0)
        let maximumY = max(documentView.frame.height - visibleSize.height, 0)
        scrollView.contentView.scroll(to: NSPoint(
            x: min(max(previousOrigin.x, 0), maximumX),
            y: min(max(previousOrigin.y, 0), maximumY)
        ))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func buildCatalogCategory(
        _ category: DistillerCategory,
        in formStack: NSStackView
    ) {
        var definitions = DistillerOptionCatalog.options(in: category).filter {
            guard $0.classification == .distillerControl else { return false }
            if case .companion = $0.semanticEditor { return false }
            if case .imagePolicy = $0.semanticEditor { return false }
            return true
        }
        if category == .fonts {
            let checkboxKeys = Set(["EmbedAllFonts", "EmbedSubstituteFonts", "SubsetFonts", "EmbedOpenType"])
            definitions.removeAll { !checkboxKeys.contains($0.key) }
        }

        var bySection: [DistillerSection: [DistillerOptionDefinition]] = [:]
        for definition in definitions {
            bySection[definition.section, default: []].append(definition)
        }
        let preferredSections = preferredSectionOrder(for: category)
        let remainingSections = bySection.keys
            .filter { !preferredSections.contains($0) }
            .sorted { $0.rawValue < $1.rawValue }
        let sectionOrder = preferredSections.filter { bySection[$0] != nil } + remainingSections
        for section in sectionOrder {
            let rows = bySection[section, default: []].compactMap(makeEditor(for:))
            guard !rows.isEmpty else { continue }
            formStack.addArrangedSubview(makeSection(title: section.title, rows: rows))
        }

        if category == .images {
            let button = ActionButton(title: String(localized: "Policies...")) { [weak self] in
                self?.showImagePolicies()
            }
            button.toolTip = [
                "/ColorImageMinResolution", "/ColorImageMinResolutionPolicy",
                "/GrayImageMinResolution", "/GrayImageMinResolutionPolicy",
                "/MonoImageMinResolution", "/MonoImageMinResolutionPolicy"
            ].joined(separator: ", ")
            button.setAccessibilityHelp(button.toolTip)
            formStack.addArrangedSubview(button)
        }
    }

    private func makeEditor(for definition: DistillerOptionDefinition) -> NSView? {
        let row: NSView?
        switch definition.semanticEditor {
        case .scalar:
            row = makeScalarEditor(definition)
        case .description:
            row = makeDescriptionEditor(definition)
        case .deviceResolution:
            row = makeResolutionEditor(definition)
        case .pageRange:
            row = makePageRangeEditor(definition)
        case .pageSize:
            row = makePageSizeEditor(definition)
        case let .downsampling(kind):
            row = makeDownsamplingEditor(definition, kind: kind)
        case let .compression(kind):
            row = makeCompressionEditor(definition, kind: kind)
        case .monoSmoothing:
            row = makeMonoSmoothingEditor(definition)
        case .distillerOverrides:
            row = makeDistillerOverridesEditor(definition)
        case .standard:
            row = makeStandardEditor(definition)
        case .pdfXBoxes:
            row = makePDFXBoxesEditor(definition)
        case .imagePolicy, .companion:
            row = nil
        }
        if let row {
            applyTechnicalTooltip(definition.localizedHelp, to: row)
            registerConsistencyHighlight(row, paths: definition.keyPaths)
        }
        if let row, isLocked(definition) {
            controls(in: row).forEach { $0.isEnabled = false }
            row.alphaValue = 0.62
        }
        return row
    }

    private func makeScalarEditor(_ definition: DistillerOptionDefinition) -> NSView {
        let value = session.document.value(forKey: definition.key)
        let control: NSView
        switch definition.kind {
        case .boolean:
            let button = ActionButton.checkbox(
                title: definition.localizedTitle,
                state: value?.boolValue
            ) { [weak self] state in
                self?.apply(JoboptionsChangeSet([
                    JoboptionsChange("/\(definition.key)", .boolean(state))
                ]))
            }
            control = selectedCategory == .standards ? checkboxRow(button) : button
        case let .name(choices):
            control = makeChoicePopup(
                title: definition.localizedTitle,
                choices: choices,
                selected: value?.textualValue,
                localizesChoices: true
            ) { [weak self] selected in
                self?.apply(JoboptionsChangeSet([
                    JoboptionsChange("/\(definition.key)", .name(selected))
                ]))
            }
        case let .literal(choices):
            control = makeChoicePopup(
                title: definition.localizedTitle,
                choices: choices,
                selected: value?.textualValue,
                localizesChoices: false
            ) { [weak self] selected in
                self?.apply(JoboptionsChangeSet([
                    JoboptionsChange(
                        "/\(definition.key)",
                        .number(Double(selected) ?? 0, original: selected)
                    )
                ]))
            }
        case let .integer(range):
            let field = CommitTextField(value?.textualValue ?? "") { [weak self] text in
                guard let number = Int(text), range.contains(number) else { return false }
                self?.apply(JoboptionsChangeSet([
                    JoboptionsChange(
                        "/\(definition.key)",
                        .number(Double(number), original: String(number))
                    )
                ]))
                return true
            }
            field.placeholderString = value == nil ? String(localized: "Not set") : nil
            control = labeledRow(definition.localizedTitle, field)
        case let .number(range):
            let field = CommitTextField(value?.textualValue ?? "") { [weak self] text in
                guard let number = Double(text), range.contains(number) else { return false }
                self?.apply(JoboptionsChangeSet([
                    JoboptionsChange("/\(definition.key)", .number(number, original: text))
                ]))
                return true
            }
            field.placeholderString = value == nil ? String(localized: "Not set") : nil
            control = labeledRow(definition.localizedTitle, field)
        case .string:
            if isProfileSetting(definition.key) {
                control = makeProfileEditor(definition)
            } else {
                let field = CommitTextField(value?.textualValue ?? "") { [weak self] text in
                    self?.apply(JoboptionsChangeSet([
                        JoboptionsChange("/\(definition.key)", .string(text))
                    ]))
                    return true
                }
                field.placeholderString = value == nil ? String(localized: "Not set") : nil
                control = labeledRow(definition.localizedTitle, field)
            }
        }
        return control
    }

    private func makeDescriptionEditor(_ definition: DistillerOptionDefinition) -> NSView {
        let value = SemanticJoboptions.description(in: session.document) ?? ""
        let editor = GrowingTextEditor(value)
        declareMinimumHeight(Layout.descriptionEditorHeight, for: editor)
        editor.onTextChange = { [weak self] text in
            guard let self else { return }
            apply(SemanticJoboptions.changeDescription(to: text, in: session.document))
        }
        let row = labeledRow(definition.localizedTitle, editor, alignment: .top)
        editor.onHeightChange = { [weak self, weak editor, weak row] height in
            guard let self, let editor, let row else { return }
            updateDescriptionHeight(height, editor: editor, row: row)
        }
        return row
    }

    private func makeResolutionEditor(_ definition: DistillerOptionDefinition) -> NSView {
        let values = rawArrayTexts(key: "HWResolution", count: 2)
        let x = CommitTextField(values[0])
        let y = CommitTextField(values[1])
        let commit = { [weak self, weak x, weak y] () -> Bool in
            guard let xValue = Int(x?.stringValue ?? ""),
                  let yValue = Int(y?.stringValue ?? ""),
                  (1...9_600).contains(xValue), (1...9_600).contains(yValue)
            else { return false }
            self?.apply(SemanticJoboptions.changeDeviceResolution(x: xValue, y: yValue))
            return true
        }
        x.setCommitHandler { _ in commit() }
        y.setCommitHandler { _ in commit() }
        let controls = NSStackView(views: [x, text(String(localized: "×")), y, text(String(localized: "dpi"))])
        controls.orientation = .horizontal
        controls.spacing = 6
        return labeledRow(definition.localizedTitle, controls)
    }

    private func makePageRangeEditor(_ definition: DistillerOptionDefinition) -> NSView {
        let popup = ActionPopUpButton()
        popup.addItem(withTitle: String(localized: "All pages"), representedObject: "all")
        popup.addItem(withTitle: String(localized: "Page range"), representedObject: "range")
        let rawStart = session.document.value(forKey: "StartPage")
        let rawEnd = session.document.value(forKey: "EndPage")
        let start = CommitTextField(rawStart?.textualValue ?? rawStart?.postScript ?? "")
        let end = CommitTextField(rawEnd?.textualValue ?? rawEnd?.postScript ?? "")
        switch SemanticJoboptions.pageSelection(in: session.document) {
        case .all:
            popup.selectRepresentedObject("all")
        case let .range(first, last):
            popup.selectRepresentedObject("range")
            start.stringValue = String(first)
            end.stringValue = String(last)
        case .custom:
            popup.addItem(
                withTitle: String.localizedStringWithFormat(
                    String(localized: "Custom: %@"),
                    "\(start.stringValue) … \(end.stringValue)"
                ),
                representedObject: "custom"
            )
            popup.selectRepresentedObject("custom")
        }
        start.setCommitHandler { [weak self] text in
            guard let value = Int(text), value >= 1 else { return false }
            self?.apply(JoboptionsChangeSet([
                JoboptionsChange("/StartPage", .number(Double(value), original: String(value)))
            ]))
            return true
        }
        end.setCommitHandler { [weak self] text in
            guard let value = Int(text), value == -1 || value >= 1 else { return false }
            self?.apply(JoboptionsChangeSet([
                JoboptionsChange("/EndPage", .number(Double(value), original: String(value)))
            ]))
            return true
        }
        popup.onSelection = { [weak self, weak popup, weak start, weak end] in
            guard let selection = popup?.selectedRepresentedObject as? String else { return }
            if selection == "all" {
                self?.apply(SemanticJoboptions.changePageSelection(.all))
                start?.stringValue = "1"
                end?.stringValue = "-1"
            } else if selection == "range" {
                let first = max(Int(start?.stringValue ?? "") ?? 1, 1)
                let parsedLast = Int(end?.stringValue ?? "") ?? first
                let last = max(parsedLast, first)
                start?.stringValue = String(first)
                end?.stringValue = String(last)
                self?.apply(SemanticJoboptions.changePageSelection(.range(start: first, end: last)))
            }
        }
        let controls = NSStackView(views: [popup, start, text(String(localized: "to")), end])
        controls.orientation = .horizontal
        controls.spacing = 6
        return labeledRow(definition.localizedTitle, controls)
    }

    private func makePageSizeEditor(_ definition: DistillerOptionDefinition) -> NSView {
        let values = rawArrayTexts(key: "PageSize", count: 2)
        let width = CommitTextField(values[0])
        let height = CommitTextField(values[1])
        let unit = ActionPopUpButton()
        for choice in SemanticJoboptions.MeasurementUnit.allCases {
            let title: String = switch choice {
            case .points: String(localized: "Points")
            case .inches: String(localized: "Inches")
            case .millimeters: String(localized: "Millimeters")
            }
            unit.addItem(withTitle: title, representedObject: choice.rawValue)
        }
        let commit = { [weak self, weak width, weak height, weak unit] () -> Bool in
            guard let widthValue = Double(width?.stringValue ?? ""),
                  let heightValue = Double(height?.stringValue ?? ""),
                  widthValue > 0, heightValue > 0,
                  let raw = unit?.selectedRepresentedObject as? String,
                  let selectedUnit = SemanticJoboptions.MeasurementUnit(rawValue: raw)
            else { return false }
            self?.apply(
                SemanticJoboptions.changePageSize(
                    width: widthValue,
                    height: heightValue,
                    unit: selectedUnit
                )
            )
            return true
        }
        width.setCommitHandler { _ in commit() }
        height.setCommitHandler { _ in commit() }
        unit.onSelection = { _ = commit() }
        let controls = NSStackView(views: [unit, width, text(String(localized: "×")), height])
        controls.orientation = .horizontal
        controls.spacing = 6
        return labeledRow(definition.localizedTitle, controls)
    }

    private func makeDownsamplingEditor(
        _ definition: DistillerOptionDefinition,
        kind: SemanticJoboptions.ImageKind
    ) -> NSView {
        let popup = ActionPopUpButton()
        popup.addItem(withTitle: String(localized: "Off"), representedObject: "off")
        for mode in SemanticJoboptions.DownsamplingMode.allCases {
            popup.addItem(
                withTitle: DistillerOptionCatalog.localizedChoice(mode.rawValue),
                representedObject: mode.rawValue
            )
        }
        let prefix = kind.rawValue
        let rawMode = session.document.value(forKey: "\(prefix)ImageDownsampleType")?.textualValue
        let rawResolution = session.document.value(forKey: "\(prefix)ImageResolution")
        let rawThreshold = session.document.value(forKey: "\(prefix)ImageDownsampleThreshold")
        let resolution = CommitTextField(rawResolution?.textualValue ?? rawResolution?.postScript ?? "")
        let threshold = CommitTextField(rawThreshold?.textualValue ?? rawThreshold?.postScript ?? "")
        switch SemanticJoboptions.downsampling(in: session.document, kind: kind) {
        case .off:
            popup.selectRepresentedObject("off")
        case let .configured(mode, selectedResolution, selectedThreshold):
            popup.selectRepresentedObject(mode.rawValue)
            resolution.stringValue = String(selectedResolution)
            threshold.stringValue = numberText(selectedThreshold)
        case .custom:
            popup.addItem(
                withTitle: String.localizedStringWithFormat(
                    String(localized: "Custom: %@"), rawMode ?? String(localized: "Not set")
                ),
                representedObject: "custom"
            )
            popup.selectRepresentedObject("custom")
        }
        resolution.setCommitHandler { [weak self] text in
            guard let value = Int(text), (1...9_600).contains(value) else { return false }
            self?.apply(JoboptionsChangeSet([
                JoboptionsChange("/\(prefix)ImageResolution", .number(Double(value), original: String(value)))
            ]))
            return true
        }
        threshold.setCommitHandler { [weak self] text in
            guard let value = Double(text), (1...10).contains(value) else { return false }
            self?.apply(JoboptionsChangeSet([
                JoboptionsChange("/\(prefix)ImageDownsampleThreshold", .number(value, original: text))
            ]))
            return true
        }
        popup.onSelection = { [weak self, weak popup] in
            guard let selected = popup?.selectedRepresentedObject as? String else { return }
            if selected == "off" {
                self?.apply(JoboptionsChangeSet([
                    JoboptionsChange("/Downsample\(prefix)Images", .boolean(false))
                ]))
            } else if let mode = SemanticJoboptions.DownsamplingMode(rawValue: selected) {
                self?.apply(JoboptionsChangeSet([
                    JoboptionsChange("/Downsample\(prefix)Images", .boolean(true)),
                    JoboptionsChange("/\(prefix)ImageDownsampleType", .name(mode.rawValue))
                ]))
            }
        }
        let controls = NSStackView(views: [
            popup, resolution, text(String(localized: "ppi")),
            text(String(localized: "above")), threshold
        ])
        controls.orientation = .horizontal
        controls.spacing = 6
        return labeledRow(definition.localizedTitle, controls)
    }

    private func makeCompressionEditor(
        _ definition: DistillerOptionDefinition,
        kind: SemanticJoboptions.ImageKind
    ) -> NSView {
        let popup = ActionPopUpButton()
        var choices: [(String, String)] = []
        if kind != .monochrome {
            choices += [
                (String(localized: "Automatic (JPEG)"), "automaticJPEG"),
                (String(localized: "JPEG"), "jpeg"),
                (String(localized: "JPEG 2000"), "jpeg2000")
            ]
        }
        choices.append((String(localized: "Flate"), "flate"))
        if kind == .monochrome {
            choices += [
                (String(localized: "CCITT Group 4"), "ccitt"),
                (String(localized: "Run Length"), "runLength")
            ]
        }
        choices.append((String(localized: "Off"), "off"))
        choices.forEach { popup.addItem(withTitle: $0.0, representedObject: $0.1) }

        let configuration = SemanticJoboptions.imageCompression(in: session.document, kind: kind)
        let selectedCompression = compressionIdentifier(configuration.compression)
        if choices.contains(where: { $0.1 == selectedCompression }) {
            popup.selectRepresentedObject(selectedCompression)
        } else {
            let prefix = kind.rawValue
            let parts = [
                session.document.value(forKey: "Encode\(prefix)Images")?.postScript,
                session.document.value(forKey: "AutoFilter\(prefix)Images")?.postScript,
                session.document.value(forKey: "\(prefix)ImageFilter")?.postScript
            ].compactMap { $0 }.joined(separator: ", ")
            popup.addItem(
                withTitle: String.localizedStringWithFormat(
                    String(localized: "Custom: %@"),
                    parts.isEmpty ? String(localized: "Not set") : parts
                ),
                representedObject: "custom"
            )
            popup.selectRepresentedObject("custom")
        }

        let quality = ActionPopUpButton()
        let qualityChoices = ["minimum", "low", "medium", "high", "maximum"]
        for choice in qualityChoices {
            quality.addItem(withTitle: localizedQuality(choice), representedObject: choice)
        }
        let currentQuality = qualityIdentifier(configuration.quality)
        if qualityChoices.contains(currentQuality) {
            quality.selectRepresentedObject(currentQuality)
        } else {
            let rawQuality = activeQualityValue(in: session.document, kind: kind, compression: configuration.compression)
            let title = rawQuality.map {
                String.localizedStringWithFormat(String(localized: "Custom: %@"), numberText($0))
            } ?? String(localized: "Not set")
            quality.addItem(withTitle: title, representedObject: "custom")
            quality.selectRepresentedObject("custom")
        }
        let prefix = kind.rawValue
        let rawJPXQuality = session.document.value(
            forPath: "/JPEG2000\(prefix)ImageDict /Quality"
        )
        let jpxQuality = CommitTextField(
            rawJPXQuality?.textualValue ?? rawJPXQuality?.postScript ?? ""
        ) { [weak self] text in
            guard let value = Double(text), (0...100).contains(value) else { return false }
            self?.apply(JoboptionsChangeSet([
                JoboptionsChange(
                    "/JPEG2000\(prefix)ImageDict /Quality",
                    .number(value, original: text)
                )
            ]))
            return true
        }
        jpxQuality.placeholderString = rawJPXQuality == nil ? String(localized: "Not set") : nil
        let showsJPXQuality = configuration.compression == .jpeg2000
        quality.isHidden = kind == .monochrome || showsJPXQuality
        jpxQuality.isHidden = kind == .monochrome || !showsJPXQuality

        popup.onSelection = { [weak self, weak popup, weak quality] in
            guard let self,
                  let rawCompression = popup?.selectedRepresentedObject as? String,
                  let compression = compressionValue(rawCompression)
            else { return }
            let selectedQuality = (quality?.selectedRepresentedObject as? String)
                .flatMap(qualityValue)
            apply(
                SemanticJoboptions.changeCompression(
                    kind: kind,
                    compression: compression,
                    quality: selectedQuality
                )
            )
            buildSelectedCategory()
        }
        quality.onSelection = { [weak self, weak quality] in
            guard let self,
                  let rawQuality = quality?.selectedRepresentedObject as? String,
                  let selectedQuality = qualityValue(rawQuality)
            else { return }
            let compression = SemanticJoboptions.imageCompression(
                in: session.document, kind: kind
            ).compression
            guard compression == .automaticJPEG || compression == .jpeg else { return }
            apply(SemanticJoboptions.changeCompression(
                kind: kind,
                compression: compression,
                quality: selectedQuality
            ))
        }
        let controls = NSStackView(views: [popup, quality, jpxQuality])
        controls.orientation = .horizontal
        controls.spacing = 6
        return labeledRow(definition.localizedTitle, controls)
    }

    private func makeMonoSmoothingEditor(_ definition: DistillerOptionDefinition) -> NSView {
        let popup = ActionPopUpButton()
        let choices = [
            (String(localized: "Off"), "off"),
            (String(localized: "2 bit"), "2"),
            (String(localized: "4 bit"), "4"),
            (String(localized: "8 bit"), "8")
        ]
        choices.forEach { popup.addItem(withTitle: $0.0, representedObject: $0.1) }
        switch SemanticJoboptions.monoSmoothing(in: session.document) {
        case .off:
            popup.selectRepresentedObject("off")
        case let .depth(depth):
            popup.selectRepresentedObject(String(depth))
        case .custom:
            let enabled = session.document.value(forKey: "AntiAliasMonoImages")?.postScript
                ?? String(localized: "Not set")
            let depth = session.document.value(forKey: "MonoImageDepth")?.postScript
                ?? String(localized: "Not set")
            popup.addItem(
                withTitle: String.localizedStringWithFormat(
                    String(localized: "Custom: %@"), "\(enabled), \(depth)"
                ),
                representedObject: "custom"
            )
            popup.selectRepresentedObject("custom")
        }
        popup.onSelection = { [weak self, weak popup] in
            guard let selected = popup?.selectedRepresentedObject as? String else { return }
            if selected == "off" {
                self?.apply(SemanticJoboptions.changeMonoSmoothing(.off))
            } else if let depth = Int(selected) {
                self?.apply(SemanticJoboptions.changeMonoSmoothing(.depth(depth)))
            }
        }
        return labeledRow(definition.localizedTitle, popup)
    }

    private func makeDistillerOverridesEditor(_ definition: DistillerOptionDefinition) -> NSView {
        ActionButton.checkbox(
            title: definition.localizedTitle,
            state: session.document.value(forKey: "LockDistillerParams")?.boolValue.map { !$0 }
        ) { [weak self] allows in
            self?.apply(SemanticJoboptions.changeAllowsDistillerOverrides(allows))
        }
    }

    private func makeStandardEditor(_ definition: DistillerOptionDefinition) -> NSView {
        let popup = ActionPopUpButton()
        let rawStandard = session.document.value(forKey: "iPS2PDFStandard")?.textualValue
        if rawStandard == nil {
            popup.addItem(withTitle: String(localized: "Not set"), representedObject: "__not_set__")
        } else if let rawStandard, PDFStandard(rawValue: rawStandard) == nil {
            popup.addItem(
                withTitle: String.localizedStringWithFormat(String(localized: "Custom: %@"), rawStandard),
                representedObject: "__custom__"
            )
        }
        for standard in PDFStandard.allCases {
            popup.addItem(withTitle: standard.title, representedObject: standard.rawValue)
        }
        popup.selectRepresentedObject(rawStandard ?? "__not_set__")
        if let rawStandard, PDFStandard(rawValue: rawStandard) == nil {
            popup.selectRepresentedObject("__custom__")
        }
        popup.onSelection = { [weak self, weak popup] in
            guard let raw = popup?.selectedRepresentedObject as? String,
                  let standard = PDFStandard(rawValue: raw)
            else { return }
            self?.setStandard(standard)
        }
        return labeledRow(definition.localizedTitle, popup)
    }

    private func makePDFXBoxesEditor(_ definition: DistillerOptionDefinition) -> NSView {
        let rules = SemanticJoboptions.pdfXBoxRules(in: session.document)
        let trimPopup = ActionPopUpButton()
        trimPopup.addItem(withTitle: String(localized: "Report an error"), representedObject: "error")
        trimPopup.addItem(withTitle: String(localized: "Use media box with offsets"), representedObject: "media")
        trimPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        trimPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        let trimOffsets: [Double]
        switch rules.trim {
        case .error:
            trimPopup.selectRepresentedObject("error")
            trimOffsets = [0, 0, 0, 0]
        case let .mediaBox(offsets):
            trimPopup.selectRepresentedObject("media")
            trimOffsets = offsets
        case .trimBox, .custom:
            let raw = session.document.value(forKey: "PDFXNoTrimBoxError")?.postScript
                ?? String(localized: "Not set")
            trimPopup.addItem(
                withTitle: String.localizedStringWithFormat(String(localized: "Custom: %@"), raw),
                representedObject: "custom"
            )
            trimPopup.selectRepresentedObject("custom")
            trimOffsets = rawArrayNumbers(key: "PDFXTrimBoxToMediaBoxOffset", count: 4)
        }
        let trimFields = offsetFields(
            texts: rawArrayTexts(key: "PDFXTrimBoxToMediaBoxOffset", count: 4),
            fallbackValues: trimOffsets
        )

        let bleedPopup = ActionPopUpButton()
        bleedPopup.addItem(withTitle: String(localized: "Use media box"), representedObject: "media")
        bleedPopup.addItem(withTitle: String(localized: "Use trim box with offsets"), representedObject: "trim")
        bleedPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bleedPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        let bleedOffsets: [Double]
        switch rules.bleed {
        case .mediaBox:
            bleedPopup.selectRepresentedObject("media")
            bleedOffsets = [0, 0, 0, 0]
        case let .trimBox(offsets):
            bleedPopup.selectRepresentedObject("trim")
            bleedOffsets = offsets
        case .error, .custom:
            let raw = session.document.value(forKey: "PDFXSetBleedBoxToMediaBox")?.postScript
                ?? String(localized: "Not set")
            bleedPopup.addItem(
                withTitle: String.localizedStringWithFormat(String(localized: "Custom: %@"), raw),
                representedObject: "custom"
            )
            bleedPopup.selectRepresentedObject("custom")
            bleedOffsets = rawArrayNumbers(key: "PDFXBleedBoxToTrimBoxOffset", count: 4)
        }
        let bleedFields = offsetFields(
            texts: rawArrayTexts(key: "PDFXBleedBoxToTrimBoxOffset", count: 4),
            fallbackValues: bleedOffsets
        )

        trimPopup.onSelection = { [weak self, weak trimPopup] in
            guard let value = trimPopup?.selectedRepresentedObject as? String else { return }
            if value == "error" {
                self?.apply(JoboptionsChangeSet([
                    JoboptionsChange("/PDFXNoTrimBoxError", .boolean(true))
                ]))
            } else if value == "media" {
                self?.apply(JoboptionsChangeSet([
                    JoboptionsChange("/PDFXNoTrimBoxError", .boolean(false))
                ]))
            }
        }
        bleedPopup.onSelection = { [weak self, weak bleedPopup] in
            guard let value = bleedPopup?.selectedRepresentedObject as? String else { return }
            if value == "media" {
                self?.apply(JoboptionsChangeSet([
                    JoboptionsChange("/PDFXSetBleedBoxToMediaBox", .boolean(true))
                ]))
            } else if value == "trim" {
                self?.apply(JoboptionsChangeSet([
                    JoboptionsChange("/PDFXSetBleedBoxToMediaBox", .boolean(false))
                ]))
            }
        }
        let commitTrimOffsets = { [weak self] () -> Bool in
            guard let values = self?.offsetValues(trimFields) else { return false }
            self?.apply(JoboptionsChangeSet([
                JoboptionsChange("/PDFXTrimBoxToMediaBoxOffset", self?.offsetArray(values) ?? .array([]))
            ]))
            return true
        }
        let commitBleedOffsets = { [weak self] () -> Bool in
            guard let values = self?.offsetValues(bleedFields) else { return false }
            self?.apply(JoboptionsChangeSet([
                JoboptionsChange("/PDFXBleedBoxToTrimBoxOffset", self?.offsetArray(values) ?? .array([]))
            ]))
            return true
        }
        trimFields.forEach { $0.setCommitHandler { _ in commitTrimOffsets() } }
        bleedFields.forEach { $0.setCommitHandler { _ in commitBleedOffsets() } }

        let trimRow = pdfXBoxRuleRow(
            title: String(localized: "Trim box"),
            popup: trimPopup,
            fields: trimFields
        )
        let bleedRow = pdfXBoxRuleRow(
            title: String(localized: "Bleed box"),
            popup: bleedPopup,
            fields: bleedFields
        )
        let rows = NSStackView(views: [trimRow, bleedRow])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.distribution = .fill
        rows.spacing = 7
        rows.setContentHuggingPriority(.defaultLow, for: .horizontal)
        rows.setContentCompressionResistancePriority(.required, for: .vertical)
        rows.widthAnchor.constraint(greaterThanOrEqualToConstant: 620).isActive = true
        declareMinimumHeight(24 * 2 + rows.spacing, for: rows)
        return rows
    }

    private func pdfXBoxRuleRow(
        title: String,
        popup: NSView,
        fields: [NSView]
    ) -> NSView {
        let label = text(title)
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 120).isActive = true

        let row = NSStackView(views: [label, popup] + fields)
        row.orientation = .horizontal
        row.spacing = 5
        row.distribution = .fill
        row.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    private func buildAdditional(in formStack: NSStackView) {
        let embedOutputIntentProfile = ActionButton.checkbox(
            title: String(localized: "Embed output intent profile"),
            state: SemanticJoboptions.embedsOutputIntentProfile(in: session.document)
        ) { [weak self] value in
            self?.apply(SemanticJoboptions.changeEmbedsOutputIntentProfile(value))
        }
        let limits = ActionButton.checkbox(
            title: String(localized: "Security limits"),
            state: session.securityLimitsEnabled
        ) { [weak self] value in self?.session.setSecurityLimitsEnabled(value) }
        let automatic = ActionButton.checkbox(
            title: String(localized: "Automatic random seed"),
            state: session.automaticRandomSeed
        ) { [weak self] value in
            self?.session.setAutomaticRandomSeed(value)
            self?.buildSelectedCategory()
        }
        var appRows: [NSView] = [embedOutputIntentProfile, limits, automatic]
        if !session.automaticRandomSeed {
            let seed = CommitTextField(String(session.manualRandomSeed)) { [weak self] text in
                guard let value = Int(text) else { return false }
                self?.session.setManualRandomSeed(value)
                return true
            }
            appRows.append(labeledRow(String(localized: "Seed"), seed))
        }
        formStack.addArrangedSubview(makeSection(title: "iPS2PDF", rows: appRows))

        let knownAdditional = DistillerOptionCatalog.options
            .filter { $0.classification == .knownAdditional }
            .compactMap(makeEditor(for:))
        if !knownAdditional.isEmpty {
            formStack.addArrangedSubview(
                makeSection(
                    title: String(localized: "Known additional settings"),
                    rows: knownAdditional
                )
            )
        }

        let catalogued = Set(DistillerOptionCatalog.options.map(\.key))
        let unknownKeys = session.document.keys.subtracting(catalogued).sorted()
        if !unknownKeys.isEmpty {
            let rows = unknownKeys.map(makeUnknownEditor(key:))
            formStack.addArrangedSubview(
                makeSection(title: String(localized: "Preserved settings"), rows: rows)
            )
        }

        let sourceView = NSTextView(frame: NSRect(x: 0, y: 0, width: 650, height: 220))
        sourceView.string = session.document.sourceText
        sourceView.isEditable = false
        sourceView.isSelectable = true
        sourceView.isVerticallyResizable = true
        sourceView.isHorizontallyResizable = true
        sourceView.autoresizingMask = [.width]
        sourceView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        sourceView.textContainer?.widthTracksTextView = false
        sourceView.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        let scroll = NSScrollView()
        scroll.documentView = sourceView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.borderType = .bezelBorder
        declareMinimumHeight(220, for: scroll)
        formStack.addArrangedSubview(
            makeSection(title: String(localized: "Original source"), rows: [scroll])
        )
    }

    private func makeUnknownEditor(key: String) -> NSView {
        guard let value = session.document.value(forKey: key) else { return NSView() }
        let technicalName = "/\(key)"
        let row: NSView
        if let boolean = value.boolValue {
            row = ActionButton.checkbox(title: technicalName, state: boolean) { [weak self] state in
                self?.apply(JoboptionsChangeSet([JoboptionsChange("/\(key)", .boolean(state))]))
            }
        } else {
            switch value {
            case .array, .dictionary:
                let field = text(value.postScript)
                field.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
                field.lineBreakMode = .byTruncatingMiddle
                row = labeledRow(technicalName, field)
            default:
                let field = CommitTextField(value.postScript) { [weak self] raw in
                    self?.apply(JoboptionsChangeSet([JoboptionsChange("/\(key)", .raw(raw))]))
                    return true
                }
                field.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
                row = labeledRow(technicalName, field)
            }
        }
        applyTechnicalTooltip(technicalName, to: row)
        return row
    }

    private func makeProfileEditor(_ definition: DistillerOptionDefinition) -> NSView {
        let popup = ActionPopUpButton()
        let storedValue = session.document.value(forKey: definition.key)
        let current = storedValue?.textualValue ?? ""
        let profiles = repository.profiles.filter { profile in
            switch definition.key {
            case "CalGrayProfile": profile.colorSpace == "GRAY"
            case "PDFXOutputIntentProfile":
                profile.colorSpace == "CMYK" && profile.profileClass == "prtr"
            case "CalCMYKProfile": profile.colorSpace == "CMYK"
            case "CalRGBProfile", "sRGBProfile", "OutputICCProfile": profile.colorSpace == "RGB"
            default: true
            }
        }
        if storedValue == nil {
            popup.addItem(withTitle: String(localized: "Not set"), representedObject: "__not_set__")
        } else if !current.isEmpty, !profiles.contains(where: { $0.name == current }) {
            popup.addItem(withTitle: String.localizedStringWithFormat(
                String(localized: "Custom: %@"), current
            ), representedObject: current)
        }
        popup.addItem(withTitle: String(localized: "None"), representedObject: "")
        for profile in profiles {
            popup.addItem(withTitle: profile.name, representedObject: profile.name)
        }
        popup.selectRepresentedObject(storedValue == nil ? "__not_set__" : current)
        popup.onSelection = { [weak self, weak popup] in
            guard let name = popup?.selectedRepresentedObject as? String else { return }
            guard name != "__not_set__" else { return }
            self?.apply(JoboptionsChangeSet([
                JoboptionsChange("/\(definition.key)", .string(name))
            ]))
        }
        return labeledRow(definition.localizedTitle, popup)
    }

    private func makeChoicePopup(
        title: String,
        choices: [String],
        selected: String?,
        localizesChoices: Bool,
        onSelection: @escaping (String) -> Void
    ) -> NSView {
        let popup = ActionPopUpButton()
        if selected == nil {
            popup.addItem(
                withTitle: String(localized: "Not set"),
                representedObject: "__not_set__"
            )
        } else if let selected, !choices.contains(selected) {
            popup.addItem(
                withTitle: String.localizedStringWithFormat(String(localized: "Custom: %@"), selected),
                representedObject: selected
            )
        }
        for choice in choices {
            popup.addItem(
                withTitle: localizesChoices ? DistillerOptionCatalog.localizedChoice(choice) : choice,
                representedObject: choice
            )
        }
        popup.selectRepresentedObject(selected ?? "__not_set__")
        popup.onSelection = { [weak popup] in
            guard let value = popup?.selectedRepresentedObject as? String else { return }
            guard value != "__not_set__" else { return }
            onSelection(value)
        }
        return labeledRow(title, popup)
    }

    private func makeSection(title: String, rows: [NSView]) -> NSView {
        let box = NSBox()
        box.title = title
        box.titlePosition = .atTop
        box.boxType = .primary
        guard let contentView = box.contentView else { return box }
        box.translatesAutoresizingMaskIntoConstraints = false
        box.setContentHuggingPriority(.required, for: .vertical)
        box.setContentCompressionResistancePriority(.required, for: .vertical)
        box.widthAnchor.constraint(greaterThanOrEqualToConstant: 650).isActive = true

        declareMinimumHeight(sectionHeight(for: rows), for: box)

        var previousRow: NSView?
        for row in rows {
            row.translatesAutoresizingMaskIntoConstraints = false
            row.setContentCompressionResistancePriority(.required, for: .vertical)
            if declaredMinimumHeights[ObjectIdentifier(row)] == nil {
                declareMinimumHeight(Layout.compactRowHeight, for: row)
            }
            contentView.addSubview(row)
            let topConstraint = if let previousRow {
                row.topAnchor.constraint(equalTo: previousRow.bottomAnchor, constant: Layout.rowSpacing)
            } else {
                row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Layout.sectionTopInset)
            }
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
                row.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -12),
                topConstraint
            ])
            previousRow = row
        }
        if let previousRow {
            previousRow.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -Layout.sectionBottomInset
            ).isActive = true
        }
        return box
    }

    private func labeledRow(
        _ title: String,
        _ control: NSView,
        alignment: NSLayoutConstraint.Attribute = .centerY
    ) -> NSView {
        let label = text(title)
        label.alignment = .right
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 3
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.widthAnchor.constraint(equalToConstant: Layout.labelWidth).isActive = true
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .vertical)
        let minimumControlWidth = control.widthAnchor.constraint(greaterThanOrEqualToConstant: Layout.controlMinWidth)
        minimumControlWidth.priority = .defaultHigh
        minimumControlWidth.isActive = true
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = alignment
        row.distribution = .fill
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        row.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.setContentCompressionResistancePriority(.required, for: .vertical)
        declareMinimumHeight(
            declaredMinimumHeight(for: control, fallback: Layout.labeledRowHeight),
            for: row
        )
        return row
    }

    private func checkboxRow(_ checkbox: NSView) -> NSView {
        let spacer = NSView()
        spacer.widthAnchor.constraint(equalToConstant: Layout.labelWidth).isActive = true
        let row = NSStackView(views: [spacer, checkbox])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        row.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.setContentCompressionResistancePriority(.required, for: .vertical)
        declareMinimumHeight(Layout.compactRowHeight, for: row)
        return row
    }

    private func showImagePolicies() {
        guard policyWindowController == nil, let parent = view.window else { return }
        let controller = MacOSImagePolicySheetController(session: session)
        let window = NSWindow(contentViewController: controller)
        window.title = String(localized: "Image policies")
        window.setContentSize(NSSize(width: 640, height: 430))
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        let windowController = NSWindowController(window: window)
        policyWindowController = windowController
        controller.onFinish = { [weak self, weak parent, weak window] changes in
            guard let self else { return }
            if let changes, !changes.changes.isEmpty { apply(changes) }
            if let parent, let window { parent.endSheet(window) }
            policyWindowController = nil
        }
        parent.beginSheet(window)
    }

    private func updateBanner(animated: Bool) {
        let issues = session.issues
        banner.update(issues: issues)
        let shouldShow = !issues.isEmpty
        guard banner.isHidden == shouldShow || banner.alphaValue != (shouldShow ? 1 : 0) else { return }
        let changes = {
            self.banner.alphaValue = shouldShow ? 1 : 0
        }
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            banner.isHidden = false
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                banner.animator().alphaValue = shouldShow ? 1 : 0
            } completionHandler: { [weak self] in
                Task { @MainActor in
                    self?.banner.isHidden = !shouldShow
                }
            }
        } else {
            changes()
            banner.isHidden = !shouldShow
        }
    }

    private func registerConsistencyHighlight(_ view: NSView, paths: [JoboptionsKeyPath]) {
        view.wantsLayer = true
        view.layer?.cornerRadius = 6
        highlightRegistrations.append((view, paths))
    }

    private func updateConsistencyHighlights() {
        let index = JoboptionsConsistencyIssueIndex(session.issues)
        let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let color = isDark
            ? NSColor(calibratedRed: 0.46, green: 0.29, blue: 0.07, alpha: 0.72)
            : NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.48, alpha: 0.58)
        for registration in highlightRegistrations {
            registration.view.layer?.backgroundColor = index.affects(any: registration.paths)
                ? color.cgColor
                : NSColor.clear.cgColor
        }
    }

    private func validateVisibleTextFields() -> Bool {
        let fields = controls(in: view).compactMap { $0 as? CommitTextField }
        let invalid = fields.filter { !$0.validateCurrentValue() }
        if let first = invalid.first {
            first.window?.makeFirstResponder(first)
            NSSound.beep()
        }
        return invalid.isEmpty
    }

    private func setBannerHeight(_ height: CGFloat) {
        let changes = {
            self.bannerHeightConstraint.constant = height
            self.view.layoutSubtreeIfNeeded()
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            changes()
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                changes()
            }
        }
    }

    private func isLocked(_ definition: DistillerOptionDefinition) -> Bool {
        let raw = session.document.value(forKey: "iPS2PDFStandard")?.textualValue ?? "none"
        return raw != PDFStandard.none.rawValue && definition.isDisabledBySelectedStandard
    }

    private func controls(in view: NSView) -> [NSControl] {
        var result = view is NSControl ? [view as! NSControl] : []
        for subview in view.subviews { result += controls(in: subview) }
        return result
    }

    private func preferredSectionOrder(for category: DistillerCategory) -> [DistillerSection] {
        switch category {
        case .general:
            [.description, .fileOptions, .pageRange, .pageSize]
        case .images:
            [.colorImages, .grayscaleImages, .monochromeImages, .imagePolicies]
        case .fonts:
            [.fontEmbedding]
        case .color:
            [.colorSettings, .colorManagement, .workingSpaces, .deviceDependentColor]
        case .advanced:
            [.advancedOptions, .dsc]
        case .standards:
            [.conformance, .pageBoxes, .outputIntent]
        case .additional:
            [.application, .preserved, .originalSource]
        }
    }

    private func applyTechnicalTooltip(_ tooltip: String, to view: NSView) {
        view.toolTip = tooltip
        view.setAccessibilityHelp(tooltip)
        for subview in view.subviews {
            applyTechnicalTooltip(tooltip, to: subview)
        }
    }

    private func declaredMinimumHeight(for view: NSView, fallback: CGFloat) -> CGFloat {
        max(declaredMinimumHeights[ObjectIdentifier(view)] ?? 0, fallback)
    }

    private func declareMinimumHeight(_ height: CGFloat, for view: NSView) {
        let identifier = ObjectIdentifier(view)
        declaredMinimumHeights[identifier] = height
        if let constraint = declaredHeightConstraints[identifier] {
            constraint.constant = height
        } else {
            let constraint = view.heightAnchor.constraint(greaterThanOrEqualToConstant: height)
            constraint.isActive = true
            declaredHeightConstraints[identifier] = constraint
        }
    }

    private func sectionHeight(for rows: [NSView]) -> CGFloat {
        let rowsHeight = rows.reduce(CGFloat.zero) {
            $0 + declaredMinimumHeight(for: $1, fallback: Layout.compactRowHeight)
        }
        let interRowSpacing = Layout.rowSpacing * CGFloat(max(rows.count - 1, 0))
        return rowsHeight
            + interRowSpacing
            + Layout.sectionTopInset
            + Layout.sectionBottomInset
            + Layout.sectionChromeHeight
    }

    private func documentContentHeight(for formStack: NSStackView) -> CGFloat {
        let arrangedHeights = formStack.arrangedSubviews.reduce(CGFloat.zero) {
            $0 + declaredMinimumHeight(for: $1, fallback: 24)
        }
        let arrangedSpacing = formStack.spacing * CGFloat(max(formStack.arrangedSubviews.count - 1, 0))
        return arrangedHeights
            + arrangedSpacing
            + formStack.edgeInsets.top
            + formStack.edgeInsets.bottom
    }

    private func updateDescriptionHeight(
        _ height: CGFloat,
        editor: NSView,
        row: NSView
    ) {
        let height = max(ceil(height), Layout.labeledRowHeight)
        guard abs(declaredMinimumHeight(for: row, fallback: 0) - height) >= 0.5 else { return }
        declareMinimumHeight(height, for: editor)
        declareMinimumHeight(height, for: row)

        guard let box = ancestor(of: NSBox.self, from: row),
              let contentView = box.contentView,
              let formStack = activeFormStack
        else { return }
        declareMinimumHeight(sectionHeight(for: contentView.subviews), for: box)
        activeDocumentContentHeight = documentContentHeight(for: formStack)
        activeFormHeightConstraint?.constant = activeDocumentContentHeight
        resizeActiveDocument()
    }

    private func ancestor<View: NSView>(of type: View.Type, from view: NSView) -> View? {
        var candidate = view.superview
        while let current = candidate {
            if let match = current as? View { return match }
            candidate = current.superview
        }
        return nil
    }

    private func compressionIdentifier(_ value: SemanticJoboptions.ImageCompression) -> String {
        switch value {
        case .automaticJPEG: "automaticJPEG"
        case .jpeg: "jpeg"
        case .flate: "flate"
        case .jpeg2000: "jpeg2000"
        case .ccittGroup4: "ccitt"
        case .runLength: "runLength"
        case .off: "off"
        case .custom: "custom"
        }
    }

    private func compressionValue(_ value: String) -> SemanticJoboptions.ImageCompression? {
        return switch value {
        case "automaticJPEG": .automaticJPEG
        case "jpeg": .jpeg
        case "flate": .flate
        case "jpeg2000": .jpeg2000
        case "ccitt": .ccittGroup4
        case "runLength": .runLength
        case "off": .off
        default: nil
        }
    }

    private func qualityIdentifier(_ value: SemanticJoboptions.ImageQuality?) -> String {
        return switch value {
        case .maximum: "maximum"
        case .high: "high"
        case .medium: "medium"
        case .low: "low"
        case .minimum: "minimum"
        case .custom, nil: "custom"
        }
    }

    private func qualityValue(_ value: String) -> SemanticJoboptions.ImageQuality? {
        return switch value {
        case "minimum": .minimum
        case "low": .low
        case "medium": .medium
        case "high": .high
        case "maximum": .maximum
        default: nil
        }
    }

    private func localizedQuality(_ value: String) -> String {
        return switch value {
        case "minimum": String(localized: "Minimum")
        case "low": String(localized: "Low")
        case "medium": String(localized: "Medium")
        case "high": String(localized: "High")
        default: String(localized: "Maximum")
        }
    }

    private func rawArrayTexts(key: String, count: Int) -> [String] {
        guard let value = session.document.value(forKey: key) else {
            return Array(repeating: "", count: count)
        }
        guard case let .array(values) = value else {
            return [value.postScript] + Array(repeating: "", count: max(count - 1, 0))
        }
        return (0..<count).map { index in
            guard values.indices.contains(index) else { return "" }
            return values[index].textualValue ?? values[index].postScript
        }
    }

    private func rawArrayNumbers(key: String, count: Int) -> [Double] {
        guard case let .array(values) = session.document.value(forKey: key) else { return [] }
        let numbers = values.compactMap(\.numberValue)
        return numbers.count == count ? numbers : []
    }

    private func offsetFields(texts: [String], fallbackValues: [Double]) -> [CommitTextField] {
        (0..<4).map { index in
            let fallback = fallbackValues.indices.contains(index) ? numberText(fallbackValues[index]) : ""
            return CommitTextField(texts.indices.contains(index) && !texts[index].isEmpty ? texts[index] : fallback)
        }
    }

    private func offsetValues(_ fields: [CommitTextField]) -> [Double]? {
        let values = fields.compactMap { Double($0.stringValue) }
        return values.count == 4 ? values : nil
    }

    private func offsetArray(_ values: [Double]) -> JoboptionsValue {
        .array(values.map { .number($0, original: numberText($0)) })
    }

    private func activeQualityValue(
        in document: LosslessJoboptionsDocument,
        kind: SemanticJoboptions.ImageKind,
        compression: SemanticJoboptions.ImageCompression
    ) -> Double? {
        let prefix = kind.rawValue
        return switch compression {
        case .automaticJPEG:
            document.value(forPath: "/\(prefix)ACSImageDict /QFactor")?.numberValue
        case .jpeg:
            document.value(forPath: "/\(prefix)ImageDict /QFactor")?.numberValue
        case .jpeg2000:
            document.value(forPath: "/JPEG2000\(prefix)ImageDict /Quality")?.numberValue
        default:
            nil
        }
    }

    private func numberText(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.rounded() == value ? String(Int(value)) : String(value)
    }

    private func isProfileSetting(_ key: String) -> Bool {
        [
            "CalGrayProfile", "CalRGBProfile", "CalCMYKProfile", "sRGBProfile",
            "OutputICCProfile", "GraphicICCProfile", "ImageICCProfile", "TextICCProfile",
            "PDFXOutputIntentProfile"
        ].contains(key)
    }

    private func text(_ value: String) -> NSTextField {
        NSTextField(labelWithString: value)
    }

    private func present(_ error: Error) {
        guard let window = view.window else { return }
        NSAlert(error: error).beginSheetModal(for: window)
    }

    private func presentPDFXOutputIntentNotice() {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "PDF/X output intent")
        alert.informativeText = String(localized: "Generic CMYK Profile has been selected as the PDF/X output intent. Check whether this profile matches the intended print condition.")
        alert.addButton(withTitle: String(localized: "OK"))
        alert.beginSheetModal(for: window)
    }

    private final class ActionButton: NSButton {
        private var actionHandler: (() -> Void)?

        init(title: String, action: @escaping () -> Void) {
            actionHandler = action
            super.init(frame: .zero)
            self.title = title
            bezelStyle = .rounded
            target = self
            self.action = #selector(invoke(_:))
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        static func checkbox(
            title: String,
            state: Bool?,
            action: @escaping (Bool) -> Void
        ) -> ActionButton {
            let button = ActionButton(title: title) {}
            button.setButtonType(.switch)
            button.allowsMixedState = true
            button.state = state.map { $0 ? .on : .off } ?? .mixed
            button.actionHandler = { [weak button] in action(button?.state == .on) }
            return button
        }

        @objc private func invoke(_ sender: Any?) { actionHandler?() }
    }

    private final class ActionPopUpButton: NSPopUpButton {
        var onSelection: (() -> Void)?
        var selectedRepresentedObject: Any? { selectedItem?.representedObject }

        init() {
            super.init(frame: .zero, pullsDown: false)
            target = self
            action = #selector(selectionChanged(_:))
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        func addItem(withTitle title: String, representedObject: Any) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.representedObject = representedObject
            menu?.addItem(item)
        }

        func selectRepresentedObject(_ object: String) {
            if let index = itemArray.firstIndex(where: { ($0.representedObject as? String) == object }) {
                selectItem(at: index)
            }
        }

        @objc private func selectionChanged(_ sender: Any?) { onSelection?() }
    }

    private final class CommitTextField: NSTextField, NSTextFieldDelegate {
        private var commitHandler: ((String) -> Bool)?
        private(set) var isCurrentValueValid = true
        private var hasUserEdited = false

        init(_ value: String, commit: ((String) -> Bool)? = nil) {
            commitHandler = commit
            super.init(frame: .zero)
            stringValue = value
            delegate = self
            target = self
            action = #selector(commitAction(_:))
            widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        func setCommitHandler(_ handler: @escaping (String) -> Bool) {
            commitHandler = handler
        }

        func controlTextDidChange(_ obj: Notification) {
            hasUserEdited = true
            _ = validateCurrentValue()
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            _ = validateCurrentValue()
        }

        @objc private func commitAction(_ sender: Any?) {
            _ = validateCurrentValue()
        }

        @discardableResult
        func validateCurrentValue() -> Bool {
            guard hasUserEdited else { return true }
            isCurrentValueValid = commitHandler?(stringValue) ?? true
            backgroundColor = isCurrentValueValid ? .textBackgroundColor : .systemRed.withAlphaComponent(0.16)
            return isCurrentValueValid
        }
    }

    private final class GrowingTextEditor: NSScrollView, NSTextViewDelegate {
        var onTextChange: ((String) -> Void)?
        var onHeightChange: ((CGFloat) -> Void)?

        private let editor = NSTextView(frame: .zero)
        private var lastReportedHeight: CGFloat = 0

        init(_ value: String) {
            super.init(frame: .zero)
            borderType = .noBorder
            hasVerticalScroller = false
            hasHorizontalScroller = false
            autohidesScrollers = true
            drawsBackground = true
            backgroundColor = .textBackgroundColor
            wantsLayer = true
            layer?.cornerRadius = 5
            layer?.borderWidth = 1
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.masksToBounds = true

            editor.string = value
            editor.font = .systemFont(ofSize: NSFont.systemFontSize)
            editor.isRichText = false
            editor.importsGraphics = false
            editor.allowsUndo = true
            editor.isVerticallyResizable = true
            editor.isHorizontallyResizable = false
            editor.autoresizingMask = [.width]
            editor.minSize = .zero
            editor.maxSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            editor.textContainerInset = NSSize(width: 4, height: 4)
            editor.textContainer?.widthTracksTextView = true
            editor.delegate = self
            documentView = editor
            widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func layout() {
            super.layout()
            reportRequiredHeight()
        }

        func textDidChange(_ notification: Notification) {
            onTextChange?(editor.string)
            reportRequiredHeight()
        }

        private func reportRequiredHeight() {
            let width = contentSize.width
            guard width > 1,
                  let textContainer = editor.textContainer,
                  let layoutManager = editor.layoutManager
            else { return }

            editor.frame.size.width = width
            textContainer.containerSize = NSSize(
                width: width,
                height: CGFloat.greatestFiniteMagnitude
            )
            layoutManager.ensureLayout(for: textContainer)
            let usedHeight = layoutManager.usedRect(for: textContainer).height
            let requiredHeight = max(
                Layout.labeledRowHeight,
                ceil(usedHeight + editor.textContainerInset.height * 2 + 2)
            )
            editor.frame.size.height = max(requiredHeight - 2, contentSize.height)
            guard abs(requiredHeight - lastReportedHeight) >= 0.5 else { return }
            lastReportedHeight = requiredHeight
            onHeightChange?(requiredHeight)
        }
    }

    private final class FlippedStackView: NSStackView {
        override var isFlipped: Bool { true }
    }

    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }
}
