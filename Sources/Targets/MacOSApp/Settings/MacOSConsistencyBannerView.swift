import AppKit

@MainActor
final class MacOSConsistencyBannerView: NSVisualEffectView {
    var onRepair: (() -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?

    private let summaryButton = NSButton()
    private let repairButton = NSButton()
    private let detailStack = NSStackView()
    private let detailScrollView = NSScrollView()
    private var issues: [JoboptionsConsistencyIssue] = []
    private var isExpanded = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .popover
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
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

        detailStack.orientation = .vertical
        detailStack.alignment = .leading
        detailStack.spacing = 8
        detailStack.edgeInsets = NSEdgeInsets(top: 6, left: 4, bottom: 4, right: 4)
        detailScrollView.documentView = detailStack
        detailScrollView.hasVerticalScroller = true
        detailScrollView.drawsBackground = false
        detailScrollView.isHidden = true

        let stack = NSStackView(views: [header, detailScrollView])
        stack.orientation = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            detailScrollView.heightAnchor.constraint(equalToConstant: 145),
            symbol.widthAnchor.constraint(equalToConstant: 18)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

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
        repairButton.isEnabled = issues.contains(where: { $0.isAutomaticallyRepairable })
        rebuildDetails()
    }

    @objc private func toggleDetails(_ sender: Any?) {
        isExpanded.toggle()
        detailScrollView.isHidden = !isExpanded
        summaryButton.setAccessibilityHelp(
            isExpanded
                ? String(localized: "Collapse consistency details")
                : String(localized: "Expand consistency details")
        )
        onHeightChange?(isExpanded ? 205 : 52)
    }

    @objc private func repair(_ sender: Any?) {
        onRepair?()
    }

    private func rebuildDetails() {
        detailStack.arrangedSubviews.forEach {
            detailStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for issue in issues {
            let summary = NSTextField(labelWithString: issue.summary)
            summary.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            summary.lineBreakMode = .byTruncatingMiddle
            summary.maximumNumberOfLines = 1

            let reason = NSTextField(labelWithString: issue.reason)
            reason.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            reason.textColor = issue.isAutomaticallyRepairable ? .secondaryLabelColor : .systemOrange
            reason.maximumNumberOfLines = 2
            reason.lineBreakMode = .byWordWrapping

            let row = NSStackView(views: [summary, reason])
            row.orientation = .vertical
            row.alignment = .leading
            row.spacing = 2
            detailStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: detailStack.widthAnchor, constant: -8).isActive = true
        }
    }
}
