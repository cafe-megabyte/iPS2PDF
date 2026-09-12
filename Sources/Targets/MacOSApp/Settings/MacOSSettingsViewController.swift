import AppKit
import Combine

@MainActor
final class MacOSSettingsViewController: NSViewController {
    private let runtimeSettings: GhostscriptRuntimeSettings
    private let securityLimitsButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let automaticRandomButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let randomSeedField = NSTextField()
    private var runtimeObservation: AnyCancellable?

    init(runtimeSettings: GhostscriptRuntimeSettings) {
        self.runtimeSettings = runtimeSettings
        super.init(nibName: nil, bundle: nil)
        runtimeObservation = runtimeSettings.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.reloadRuntimeSettings()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView()

        securityLimitsButton.target = self
        securityLimitsButton.action = #selector(toggleSecurityLimits(_:))
        automaticRandomButton.target = self
        automaticRandomButton.action = #selector(toggleAutomaticRandomNumbers(_:))
        randomSeedField.target = self
        randomSeedField.action = #selector(changeRandomSeed(_:))
        randomSeedField.formatter = Self.randomSeedFormatter()
        randomSeedField.alignment = .right
        randomSeedField.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true

        let runtimeGrid = NSGridView(views: [
            [label(String(localized: "Security limits")), securityLimitsButton],
            [label(String(localized: "Automatic random seed")), automaticRandomButton],
            [label(String(localized: "Seed")), randomSeedField]
        ])
        runtimeGrid.rowSpacing = 10
        runtimeGrid.columnSpacing = 16
        runtimeGrid.column(at: 0).xPlacement = .trailing
        runtimeGrid.column(at: 1).xPlacement = .leading
        runtimeGrid.translatesAutoresizingMaskIntoConstraints = false

        let ghostscriptTitle = label(String(localized: "Ghostscript"))
        ghostscriptTitle.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        ghostscriptTitle.alignment = .left

        let runtimeDescription = NSTextField(
            wrappingLabelWithString: String(
                localized: "Enabled by default: 15 minutes, 1 GB input and 2 GB output. Process isolation, SAFER, diagnostics and cancellation always remain active."
            )
        )
        runtimeDescription.textColor = .secondaryLabelColor
        runtimeDescription.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let stack = NSStackView(views: [
            ghostscriptTitle,
            runtimeGrid,
            runtimeDescription
        ])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.setCustomSpacing(8, after: runtimeGrid)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24)
        ])

        securityLimitsButton.nextKeyView = automaticRandomButton
        automaticRandomButton.nextKeyView = randomSeedField
        randomSeedField.nextKeyView = securityLimitsButton
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reloadRuntimeSettings()
    }

    @objc private func toggleSecurityLimits(_ sender: NSButton) {
        runtimeSettings.securityLimitsEnabled = sender.state == .on
    }

    @objc private func toggleAutomaticRandomNumbers(_ sender: NSButton) {
        runtimeSettings.setAutomaticRandomSeed(sender.state == .on)
        reloadRuntimeSettings()
    }

    @objc private func changeRandomSeed(_ sender: NSTextField) {
        guard let value = Int(sender.stringValue) else {
            reloadRuntimeSettings()
            return
        }
        runtimeSettings.setManualRandomSeed(value)
        reloadRuntimeSettings()
    }

    private func reloadRuntimeSettings() {
        securityLimitsButton.state = runtimeSettings.securityLimitsEnabled ? .on : .off
        automaticRandomButton.state = runtimeSettings.automaticRandomSeed ? .on : .off
        randomSeedField.isEnabled = !runtimeSettings.automaticRandomSeed
        randomSeedField.stringValue = String(runtimeSettings.manualRandomSeed)
    }

    private func label(_ title: String) -> NSTextField {
        let field = NSTextField(labelWithString: title)
        field.alignment = .right
        return field
    }

    private static func randomSeedFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.allowsFloats = false
        formatter.minimum = NSNumber(value: PostScriptRandomSeedSettings.range.lowerBound)
        formatter.maximum = NSNumber(value: PostScriptRandomSeedSettings.range.upperBound)
        return formatter
    }
}
