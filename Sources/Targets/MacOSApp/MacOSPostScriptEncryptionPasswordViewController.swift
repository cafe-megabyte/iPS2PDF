import AppKit

@MainActor
final class MacOSPostScriptEncryptionPasswordViewController: NSViewController, NSTextFieldDelegate {
    private let sourceName: String
    private let cancelAction: () -> Void
    private let encryptAction: (String) -> Void
    private let passwordField = NSSecureTextField()
    private let confirmationField = NSSecureTextField()
    private let validationLabel = NSTextField(wrappingLabelWithString: "")
    private let encryptButton = NSButton(
        title: String(localized: "Encrypt"),
        target: nil,
        action: nil
    )

    init(
        sourceName: String,
        cancelAction: @escaping () -> Void,
        encryptAction: @escaping (String) -> Void
    ) {
        self.sourceName = sourceName
        self.cancelAction = cancelAction
        self.encryptAction = encryptAction
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView()

        let title = NSTextField(labelWithString: String(localized: "Encrypt PostScript"))
        title.font = .preferredFont(forTextStyle: .title2)

        let fileLabel = NSTextField(labelWithString: sourceName)
        fileLabel.lineBreakMode = .byTruncatingMiddle
        fileLabel.toolTip = sourceName
        fileLabel.textColor = .secondaryLabelColor

        passwordField.placeholderString = String(localized: "Password")
        confirmationField.placeholderString = String(localized: "Confirm password")
        passwordField.delegate = self
        confirmationField.delegate = self
        passwordField.nextKeyView = confirmationField
        confirmationField.nextKeyView = passwordField
        passwordField.setAccessibilityLabel(String(localized: "Password"))
        confirmationField.setAccessibilityLabel(String(localized: "Confirm password"))

        validationLabel.textColor = .systemRed
        validationLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        validationLabel.maximumNumberOfLines = 2

        let passwordHint = NSTextField(
            wrappingLabelWithString: String(
                localized: "Use printable ASCII characters except parentheses and backslashes."
            )
        )
        passwordHint.textColor = .secondaryLabelColor
        passwordHint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let placeholderHint = NSTextField(
            wrappingLabelWithString: String(
                localized: "The encrypted file contains a password placeholder. Replace it with this password before opening or converting the file."
            )
        )
        placeholderHint.textColor = .secondaryLabelColor
        placeholderHint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let cancelButton = NSButton(
            title: String(localized: "Cancel"),
            target: self,
            action: #selector(cancel)
        )
        cancelButton.keyEquivalent = "\u{1b}"
        encryptButton.target = self
        encryptButton.action = #selector(encrypt)
        encryptButton.keyEquivalent = "\r"
        encryptButton.isEnabled = false

        let buttonSpacer = NSView()
        let buttons = NSStackView(views: [buttonSpacer, cancelButton, encryptButton])
        buttons.spacing = 8

        let stack = NSStackView(
            views: [
                title,
                fileLabel,
                passwordField,
                confirmationField,
                validationLabel,
                passwordHint,
                placeholderHint,
                buttons
            ]
        )
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            fileLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            passwordField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            confirmationField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            validationLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            passwordHint.widthAnchor.constraint(equalTo: stack.widthAnchor),
            placeholderHint.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        preferredContentSize = NSSize(width: 480, height: 300)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.initialFirstResponder = passwordField
        view.window?.makeFirstResponder(passwordField)
    }

    func controlTextDidChange(_ notification: Notification) {
        refreshValidation()
    }

    @objc private func cancel() {
        cancelAction()
    }

    @objc private func encrypt() {
        do {
            try PostScriptEncryptor.validatePassword(passwordField.stringValue)
            guard passwordField.stringValue == confirmationField.stringValue else {
                validationLabel.stringValue = String(localized: "The passwords do not match.")
                NSSound.beep()
                return
            }
            encryptAction(passwordField.stringValue)
            passwordField.stringValue = ""
            confirmationField.stringValue = ""
        } catch {
            validationLabel.stringValue = error.localizedDescription
            NSSound.beep()
        }
    }

    private func refreshValidation() {
        let password = passwordField.stringValue
        let confirmation = confirmationField.stringValue
        guard !password.isEmpty else {
            validationLabel.stringValue = ""
            encryptButton.isEnabled = false
            return
        }
        do {
            try PostScriptEncryptor.validatePassword(password)
            if !confirmation.isEmpty, password != confirmation {
                validationLabel.stringValue = String(localized: "The passwords do not match.")
            } else {
                validationLabel.stringValue = ""
            }
            encryptButton.isEnabled = !confirmation.isEmpty && password == confirmation
        } catch {
            validationLabel.stringValue = error.localizedDescription
            encryptButton.isEnabled = false
        }
    }
}
