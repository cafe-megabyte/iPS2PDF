import AppKit

@MainActor
final class MacOSPostScriptEncryptionController {
    private let coordinator: MacOSConversionCoordinator
    private let runtimeSettings: GhostscriptRuntimeSettings
    private var encryptionTask: Task<Void, Never>?
    private var progressDelayTask: Task<Void, Never>?
    private var progressWindowController: NSWindowController?
    private weak var progressParentWindow: NSWindow?
    private var passwordWindowController: NSWindowController?
    private weak var passwordParentWindow: NSWindow?
    private var isChoosingSource = false
    private var isChoosingDestination = false

    private(set) var isProcessing = false

    init(
        coordinator: MacOSConversionCoordinator,
        runtimeSettings: GhostscriptRuntimeSettings
    ) {
        self.coordinator = coordinator
        self.runtimeSettings = runtimeSettings
    }

    var canPresent: Bool {
        !isProcessing &&
            !isChoosingSource &&
            !isChoosingDestination &&
            passwordWindowController == nil
    }

    func presentOpenPanel(parentWindow: NSWindow?) {
        guard canPresent else {
            NSSound.beep()
            return
        }
        isChoosingSource = true
        let panel = NSOpenPanel()
        panel.allowedContentTypes = PostScriptEncryptor.supportedContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = String(localized: "Select a PostScript or EPS file to encrypt.")
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            self.isChoosingSource = false
            guard response == .OK, let sourceURL = panel.url else { return }
            do {
                try PostScriptEncryptor.validateInput(at: sourceURL)
                self.presentPasswordPrompt(
                    source: .postScript(url: sourceURL),
                    parentWindow: parentWindow
                )
            } catch {
                self.present(error, parentWindow: parentWindow)
            }
        }
        if let parentWindow, parentWindow.attachedSheet == nil {
            panel.beginSheetModal(for: parentWindow, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    func exportEncrypted(input: MacOSPostScriptExportInput, parentWindow: NSWindow?) {
        guard canPresent else {
            NSSound.beep()
            return
        }
        presentPasswordPrompt(source: .converted(input: input), parentWindow: parentWindow)
    }

    private func presentPasswordPrompt(source: Source, parentWindow: NSWindow?) {
        let viewController = MacOSPostScriptEncryptionPasswordViewController(
            sourceName: source.sourceName,
            cancelAction: { [weak self] in
                self?.closePasswordPrompt()
            },
            encryptAction: { [weak self] password in
                guard let self else { return }
                self.closePasswordPrompt()
                self.presentSavePanel(
                    source: source,
                    password: password,
                    parentWindow: parentWindow
                )
            }
        )
        let window = NSWindow(contentViewController: viewController)
        window.title = String(localized: "Encrypt PostScript")
        window.styleMask = [.titled]
        window.isReleasedWhenClosed = false
        window.setContentSize(viewController.preferredContentSize)
        let controller = NSWindowController(window: window)
        passwordWindowController = controller
        if let parentWindow, parentWindow.attachedSheet == nil {
            passwordParentWindow = parentWindow
            parentWindow.beginSheet(window)
        } else {
            window.center()
            controller.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func closePasswordPrompt() {
        guard let window = passwordWindowController?.window else { return }
        if let passwordParentWindow, window.sheetParent === passwordParentWindow {
            passwordParentWindow.endSheet(window)
        } else {
            window.orderOut(nil)
        }
        passwordWindowController = nil
        passwordParentWindow = nil
    }

    private func presentSavePanel(
        source: Source,
        password: String,
        parentWindow: NSWindow?
    ) {
        isChoosingDestination = true
        let panel = NSSavePanel()
        panel.allowedContentTypes = PostScriptEncryptor.supportedContentTypes
            .filter { $0.preferredFilenameExtension == "ps" }
        panel.nameFieldStringValue = PostScriptEncryptor.outputFilename(
            for: source.sourceName
        )
        panel.canCreateDirectories = true
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            self.isChoosingDestination = false
            guard response == .OK, let destinationURL = panel.url else { return }
            self.startEncryption(
                source: source,
                destinationURL: destinationURL,
                password: password,
                parentWindow: parentWindow
            )
        }
        if let parentWindow, parentWindow.attachedSheet == nil {
            panel.beginSheetModal(for: parentWindow, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    private func startEncryption(
        source: Source,
        destinationURL: URL,
        password: String,
        parentWindow: NSWindow?
    ) {
        guard !isProcessing else {
            NSSound.beep()
            return
        }
        isProcessing = true
        MacOSApplicationModel.shared.conversionDidStart()
        startProgressDelay(parentWindow: parentWindow)
        let workspace = MacOSDocumentWorkspace()
        let runtimeSnapshot = runtimeSettings.snapshot()
        let coordinator = coordinator
        encryptionTask = Task { [weak self] in
            guard let self else { return }
            let sourceAccess = source.url.startAccessingSecurityScopedResource()
            defer {
                if sourceAccess { source.url.stopAccessingSecurityScopedResource() }
                Task { try? await workspace.clear() }
                finishEncryption()
            }
            do {
                let postScriptURL: URL
                switch source {
                case .postScript(let url):
                    postScriptURL = url
                case .converted(let input):
                    let stagedURL = try await workspace.stageInput(from: input.url)
                    postScriptURL = try await workspace.postScriptOutputURL(
                        sourceName: input.sourceName
                    )
                    try await coordinator.convertToPostScript(
                        inputURL: stagedURL,
                        outputURL: postScriptURL,
                        runtimeSettings: runtimeSnapshot,
                        inputPassword: input.inputPassword
                    )
                }
                try Task.checkCancellation()
                let outputURL = try await workspace.postScriptEncryptionOutputURL(
                    sourceName: source.sourceName
                )
                try await Task.detached(priority: .userInitiated) {
                    try PostScriptEncryptor.encrypt(
                        inputURL: postScriptURL,
                        outputURL: outputURL,
                        password: password
                    )
                    try Task.checkCancellation()
                    try MacOSPostScriptDestinationWriter.publish(
                        sourceURL: outputURL,
                        destinationURL: destinationURL
                    )
                }.value
            } catch is CancellationError {
                return
            } catch {
                present(error, parentWindow: parentWindow)
            }
        }
    }

    private func startProgressDelay(parentWindow: NSWindow?) {
        progressDelayTask?.cancel()
        progressDelayTask = Task { [weak self] in
            try? await Task.sleep(for: ConversionProgressDelay.duration)
            guard !Task.isCancelled, let self, isProcessing else { return }
            showProgress(parentWindow: parentWindow)
        }
    }

    private func showProgress(parentWindow: NSWindow?) {
        guard progressWindowController == nil else { return }
        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.controlSize = .large
        indicator.startAnimation(nil)
        let label = NSTextField(
            labelWithString: String(localized: "Encrypting PostScript…")
        )
        label.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [indicator, label])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor)
        ])
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 180),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "PostScript encryption")
        window.contentView = content
        window.isReleasedWhenClosed = false
        let controller = NSWindowController(window: window)
        progressWindowController = controller
        if let parentWindow, parentWindow.attachedSheet == nil {
            progressParentWindow = parentWindow
            parentWindow.beginSheet(window)
        } else {
            window.center()
            controller.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func stopProgress() {
        progressDelayTask?.cancel()
        progressDelayTask = nil
        guard let window = progressWindowController?.window else { return }
        if let progressParentWindow, window.sheetParent === progressParentWindow {
            progressParentWindow.endSheet(window)
        } else {
            window.orderOut(nil)
        }
        progressWindowController = nil
        progressParentWindow = nil
    }

    private func finishEncryption() {
        stopProgress()
        encryptionTask = nil
        isProcessing = false
        MacOSApplicationModel.shared.conversionDidFinish()
    }

    private func present(_ error: Error, parentWindow: NSWindow?) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = String(localized: "PostScript encryption failed")
        alert.informativeText = error.localizedDescription
        if let parentWindow, parentWindow.isVisible, parentWindow.attachedSheet == nil {
            alert.beginSheetModal(for: parentWindow)
        } else {
            alert.runModal()
        }
    }

    private enum Source {
        case postScript(url: URL)
        case converted(input: MacOSPostScriptExportInput)

        var url: URL {
            switch self {
            case .postScript(let url):
                url
            case .converted(let input):
                input.url
            }
        }

        var sourceName: String {
            switch self {
            case .postScript(let url):
                url.lastPathComponent
            case .converted(let input):
                input.sourceName
            }
        }
    }
}
