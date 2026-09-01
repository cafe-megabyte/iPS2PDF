import AppKit

@MainActor
final class MacOSConsistencyBannerView: NSView {
    var onRepair: (() -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?

    private let summaryButton = NSButton()
    private let repairButton = NSButton()
    private let detailTextField = NSTextField(labelWithString: "")
    private let detailScrollView = NSScrollView()
    private var detailScrollHeightConstraint: NSLayoutConstraint!
    private var issues: [JoboptionsConsistencyIssue] = []
    private var isExpanded = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        updateLayerColors()
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Inconsistent settings"))

        let symbol = NSImageView(
            image: NSImage(
                systemSymbolName: "wrench.and.screwdriver.fill",
                accessibilityDescription: nil
            ) ?? NSImage()
        )
        symbol.contentTintColor = .controlAccentColor

        summaryButton.bezelStyle = .inline
        summaryButton.isBordered = false
        summaryButton.alignment = .left
        summaryButton.target = self
        summaryButton.action = #selector(toggleDetails(_:))

        repairButton.title = String(localized: "Repair")
        repairButton.bezelStyle = .rounded
        repairButton.target = self
        repairButton.action = #selector(repair(_:))

        let header = NSStackView(views: [symbol, summaryButton, NSView(), repairButton])
        header.orientation = .horizontal
        header.spacing = 8
        header.views[2].setContentHuggingPriority(.defaultLow, for: .horizontal)

        detailTextField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detailTextField.lineBreakMode = .byWordWrapping
        detailTextField.maximumNumberOfLines = 0
        detailTextField.textColor = .secondaryLabelColor
        detailTextField.autoresizingMask = [.width]
        detailScrollView.documentView = detailTextField
        detailScrollView.hasVerticalScroller = true
        detailScrollView.autohidesScrollers = true
        detailScrollView.drawsBackground = false
        detailScrollView.borderType = .noBorder
        detailScrollView.isHidden = true

        let stack = NSStackView(views: [header, detailScrollView])
        stack.orientation = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        detailScrollHeightConstraint = detailScrollView.heightAnchor.constraint(equalToConstant: 145)
        detailScrollHeightConstraint.isActive = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            symbol.widthAnchor.constraint(equalToConstant: 18)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        updateDetailDocumentFrame()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayerColors()
    }

    func update(issues: [JoboptionsConsistencyIssue]) {
        self.issues = issues
        summaryButton.title = String.localizedStringWithFormat(
            String(localized: "%lld inconsistent settings"),
            Int64(issues.count)
        )
        summaryButton.setAccessibilityHelp(
            isExpanded
                ? String(localized: "Collapse consistency details")
                : String(localized: "Expand consistency details")
        )
        repairButton.isEnabled = !issues.isEmpty
        rebuildDetails()
        needsLayout = true
    }

    @objc private func toggleDetails(_ sender: Any?) {
        isExpanded.toggle()
        detailScrollHeightConstraint.isActive = isExpanded
        detailScrollView.isHidden = !isExpanded
        summaryButton.setAccessibilityHelp(
            isExpanded
                ? String(localized: "Collapse consistency details")
                : String(localized: "Expand consistency details")
        )
        onHeightChange?(isExpanded ? 205 : 52)
        needsLayout = true
    }

    @objc private func repair(_ sender: Any?) {
        onRepair?()
    }

    private func rebuildDetails() {
        detailTextField.stringValue = issues.map { issue in
            [issue.summary, issue.reason].joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    private func updateDetailDocumentFrame() {
        let width = max(detailScrollView.contentSize.width, 1)
        detailTextField.frame.size.width = width
        let height = max(detailTextField.fittingSize.height, detailScrollView.contentSize.height)
        detailTextField.frame = NSRect(
            origin: .zero,
            size: NSSize(width: width, height: height)
        )
    }

    private func updateLayerColors() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = NSColor.compatibilityBannerBackground(isDark: isDark).cgColor
        layer?.borderColor = NSColor.compatibilityBannerBorder(isDark: isDark).cgColor
    }

}

private extension NSColor {
    static func compatibilityBannerBackground(isDark: Bool) -> NSColor {
        isDark
            ? NSColor(calibratedRed: 0.27, green: 0.18, blue: 0.05, alpha: 1)
            : NSColor(calibratedRed: 1.0, green: 0.92, blue: 0.72, alpha: 1)
    }

    static func compatibilityBannerBorder(isDark: Bool) -> NSColor {
        isDark
            ? NSColor(calibratedRed: 0.78, green: 0.49, blue: 0.16, alpha: 1)
            : NSColor(calibratedRed: 0.86, green: 0.54, blue: 0.13, alpha: 1)
    }
}
