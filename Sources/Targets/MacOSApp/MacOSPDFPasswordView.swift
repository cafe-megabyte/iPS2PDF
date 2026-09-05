import AppKit
import Combine

@MainActor
final class MacOSPDFPasswordView: NSView {
    private let controller: PDFPasswordController
    private let field = NSSecureTextField()
    private let name = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private var observation: AnyCancellable?
    private let openButton = NSButton(title: String(localized: "Open"), target: nil, action: nil)
    init(controller: PDFPasswordController) {
        self.controller = controller
        super.init(frame: .zero)
        let heading = NSTextField(labelWithString: String(localized: "Password required"))
        heading.font = .preferredFont(forTextStyle: .title2)
        field.placeholderString = String(localized: "Password")
        field.target = self; field.action = #selector(submit)
        openButton.target = self; openButton.action = #selector(submit); openButton.keyEquivalent = "\r"
        let cancel = NSButton(title: String(localized: "Cancel"), target: self, action: #selector(cancelPassword))
        cancel.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [cancel, openButton])
        status.textColor = .systemRed
        let stack = NSStackView(views: [heading, name, NSTextField(wrappingLabelWithString: String(localized: "Enter the PDF opening password.")), field, status, buttons])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: centerXAnchor), stack.centerYAnchor.constraint(equalTo: centerYAnchor), stack.widthAnchor.constraint(equalToConstant: 340), field.widthAnchor.constraint(equalTo: stack.widthAnchor)])
        observation = controller.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        refresh()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); window?.makeFirstResponder(field) }
    private func refresh() {
        name.stringValue = controller.request?.fileName ?? ""
        status.stringValue = controller.request?.wasIncorrect == true ? String(localized: "The password is incorrect. Please try again.") : ""
        openButton.isEnabled = !controller.isChecking
        field.isEnabled = !controller.isChecking
        if controller.request?.wasIncorrect == true, !controller.isChecking { window?.makeFirstResponder(field) }
    }
    @objc private func submit() { let password = field.stringValue; field.stringValue = ""; controller.submit(password) }
    @objc private func cancelPassword() { field.stringValue = ""; controller.cancel() }
}
