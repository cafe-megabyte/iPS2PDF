import AppKit
import UniformTypeIdentifiers

@MainActor
final class MacOSPostScriptExportController {
    private let coordinator: MacOSConversionCoordinator
    private let runtimeSettings: GhostscriptRuntimeSettings
    private var providers: [MacOSPostScriptExportProviderReference] = []
    private var keyWindowObservation: NSObjectProtocol?
    private var conversionTask: Task<Void, Never>?
    private var progressDelayTask: Task<Void, Never>?
    private var progressWindowController: NSWindowController?
    private weak var progressParentWindow: NSWindow?
    private var passwordWindowController: NSWindowController?
    private weak var passwordParentWindow: NSWindow?
    private let passwordController = PDFPasswordController()

    private(set) var isProcessing = false

    init(
        coordinator: MacOSConversionCoordinator,
        runtimeSettings: GhostscriptRuntimeSettings
    ) {
        self.coordinator = coordinator
        self.runtimeSettings = runtimeSettings
        keyWindowObservation = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            Task { @MainActor [weak self] in self?.noteActiveWindow(window) }
        }
    }

    isolated deinit {
        if let keyWindowObservation {
            NotificationCenter.default.removeObserver(keyWindowObservation)
        }
    }

    var canExportCurrent: Bool {
        !isProcessing && currentProvider?.postScriptExportInput != nil
    }

    func register(_ provider: any MacOSPostScriptExportProviding) {
        providers.removeAll { reference in
            guard let current = reference.provider else { return true }
            return current === provider
        }
        providers.append(MacOSPostScriptExportProviderReference(provider))
    }

    func unregister(_ provider: any MacOSPostScriptExportProviding) {
        providers.removeAll { reference in
            guard let current = reference.provider else { return true }
            return current === provider
        }
    }

    func presentOpenPanel() {
        guard !isProcessing else { NSSound.beep(); return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.item]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = String(localized: "Select a file to convert to PostScript.")
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                self?.presentSavePanel(
                    input: MacOSPostScriptExportInput(
                        url: url,
                        sourceName: url.lastPathComponent,
                        inputPassword: nil,
                        retainedInput: nil
                    ),
                    parentWindow: nil
                )
            }
        }
    }

    func exportCurrent() {
        guard let provider = currentProvider,
              let input = provider.postScriptExportInput
        else { NSSound.beep(); return }
        presentSavePanel(input: input, parentWindow: provider.postScriptExportWindow)
    }

    func export(using provider: any MacOSPostScriptExportProviding) {
        register(provider)
        guard let input = provider.postScriptExportInput else { NSSound.beep(); return }
        presentSavePanel(input: input, parentWindow: provider.postScriptExportWindow)
    }

    private var currentProvider: (any MacOSPostScriptExportProviding)? {
        providers.removeAll { $0.provider == nil }
        return providers.reversed().compactMap(\.provider).first {
            $0.postScriptExportWindow?.isVisible == true && $0.postScriptExportInput != nil
        }
    }

    private func noteActiveWindow(_ window: NSWindow) {
        guard let provider = providers.compactMap(\.provider).first(where: {
            $0.postScriptExportWindow === window
        }) else { return }
        register(provider)
    }

    private func presentSavePanel(
        input: MacOSPostScriptExportInput,
        parentWindow: NSWindow?
    ) {
        guard !isProcessing else { NSSound.beep(); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ps") ?? .data]
        panel.nameFieldStringValue = PostScriptOutputNaming.filename(for: input.sourceName)
        panel.canCreateDirectories = true
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let destinationURL = panel.url else { return }
            Task { @MainActor [weak self] in
                self?.startConversion(
                    input: input,
                    destinationURL: destinationURL,
                    parentWindow: parentWindow
                )
            }
        }
        if let parentWindow {
            panel.beginSheetModal(for: parentWindow, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    private func startConversion(
        input: MacOSPostScriptExportInput,
        destinationURL: URL,
        parentWindow: NSWindow?
    ) {
        guard !isProcessing else { NSSound.beep(); return }
        isProcessing = true
        MacOSApplicationModel.shared.conversionDidStart()
        let workspace = MacOSDocumentWorkspace()
        let runtimeSnapshot = runtimeSettings.snapshot()
        conversionTask = Task { [weak self] in
            guard let self else { return }
            let sourceAccess = input.url.startAccessingSecurityScopedResource()
            defer {
                if sourceAccess { input.url.stopAccessingSecurityScopedResource() }
                Task { try? await workspace.clear() }
                finishConversion()
            }
            do {
                let sourceURL = try await workspace.stageInput(from: input.url)
                let outputURL = try await workspace.postScriptOutputURL(
                    sourceName: input.sourceName
                )
                var inputPassword = input.inputPassword
                if inputPassword == nil,
                   !(await PDFPasswordController.canOpen(sourceURL, password: nil)) {
                    inputPassword = try await requestPassword(
                        for: sourceURL,
                        force: false,
                        parentWindow: parentWindow
                    )
                }
                while true {
                    startProgressDelay(parentWindow: parentWindow)
                    do {
                        try await coordinator.convertToPostScript(
                            inputURL: sourceURL,
                            outputURL: outputURL,
                            runtimeSettings: runtimeSnapshot,
                            inputPassword: inputPassword
                        )
                        break
                    } catch ConversionFailure.inputPasswordRequired {
                        stopProgress()
                        inputPassword = try await requestPassword(
                            for: sourceURL,
                            force: true,
                            parentWindow: parentWindow
                        )
                    }
                }
                inputPassword = nil
                stopProgress()
                try await Task.detached(priority: .userInitiated) {
                    try MacOSPostScriptDestinationWriter.publish(
                        sourceURL: outputURL,
                        destinationURL: destinationURL
                    )
                }.value
            } catch is CancellationError {
                stopProgress()
            } catch let failure as ConversionFailure {
                stopProgress()
                present(failure.macOSPresentation, parentWindow: parentWindow)
            } catch {
                stopProgress()
                present(error.localizedDescription, parentWindow: parentWindow)
            }
        }
    }

    private func requestPassword(
        for sourceURL: URL,
        force: Bool,
        parentWindow: NSWindow?
    ) async throws -> String? {
        let task = Task { [passwordController] in
            try await passwordController.password(for: sourceURL, force: force)
        }
        await Task.yield()
        showPasswordWindow(parentWindow: parentWindow)
        defer { closePasswordWindow() }
        return try await task.value
    }

    private func showPasswordWindow(parentWindow: NSWindow?) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 260),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Password required")
        window.contentView = MacOSPDFPasswordView(controller: passwordController)
        window.isReleasedWhenClosed = false
        let controller = NSWindowController(window: window)
        passwordWindowController = controller
        if let parentWindow {
            passwordParentWindow = parentWindow
            parentWindow.beginSheet(window)
        } else {
            window.center()
            controller.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func closePasswordWindow() {
        guard let window = passwordWindowController?.window else { return }
        if let passwordParentWindow, window.sheetParent === passwordParentWindow {
            passwordParentWindow.endSheet(window)
        } else {
            window.orderOut(nil)
        }
        passwordWindowController = nil
        passwordParentWindow = nil
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
            labelWithString: String(localized: "Converting with Ghostscript...")
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
        window.title = String(localized: "PostScript conversion")
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

    private func finishConversion() {
        stopProgress()
        conversionTask = nil
        isProcessing = false
        MacOSApplicationModel.shared.conversionDidFinish()
    }

    private func present(_ message: String, parentWindow: NSWindow?) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = String(localized: "Conversion failed")
        alert.informativeText = message
        if let parentWindow, parentWindow.isVisible {
            alert.beginSheetModal(for: parentWindow)
        } else {
            alert.runModal()
        }
    }
}
