import Foundation

@MainActor
final class PostScriptEncryptionSession: ObservableObject {
    @Published var isPasswordPromptPresented = false
    @Published var isFileExporterPresented = false
    @Published private(set) var sourceURL: URL?
    @Published private(set) var artifact: PostScriptExportArtifact?
    @Published private(set) var isProcessing = false
    @Published private(set) var showsProgress = false
    @Published var alert: AppAlert?

    private let runtimeSettings: GhostscriptRuntimeSettings
    private let converter: any FileConverting
    private var source: Source?
    private var encryptionTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?

    init(
        runtimeSettings: GhostscriptRuntimeSettings,
        converter: any FileConverting = GhostscriptConverter()
    ) {
        self.runtimeSettings = runtimeSettings
        self.converter = converter
    }

    var sourceName: String {
        source?.sourceName ?? sourceURL?.lastPathComponent ?? ""
    }

    func selectPostScriptSource(_ url: URL) {
        guard canStart else { return }
        do {
            try PostScriptEncryptor.validateInput(at: url)
            source = .postScript(url: url, sourceName: url.lastPathComponent)
            sourceURL = url
            isPasswordPromptPresented = true
        } catch {
            present(error)
        }
    }

    func preparePDFExport(
        sourceURL: URL,
        sourceName: String,
        inputPassword: String?
    ) {
        guard canStart else { return }
        source = .pdf(
            url: sourceURL,
            sourceName: sourceName,
            inputPassword: inputPassword
        )
        self.sourceURL = sourceURL
        isPasswordPromptPresented = true
    }

    func dismissPasswordPrompt() {
        isPasswordPromptPresented = false
        source = nil
        sourceURL = nil
    }

    func encrypt(password: String) {
        guard let source, !isProcessing else { return }
        do {
            try PostScriptEncryptor.validatePassword(password)
        } catch {
            present(error)
            return
        }

        isPasswordPromptPresented = false
        isProcessing = true
        showsProgress = false
        startProgressDelay()
        let sourceName = source.sourceName
        let settings = runtimeSettings.snapshot()
        let converter = converter
        encryptionTask = Task { [weak self] in
            guard let self else { return }
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("PostScript Encryption Exports", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            do {
                try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.createDirectory(
                        at: directory,
                        withIntermediateDirectories: true
                    )
                }.value
                let postScriptURL: URL
                switch source {
                case .postScript(let url, _):
                    postScriptURL = url
                case .pdf(let url, let name, let inputPassword):
                    postScriptURL = directory.appendingPathComponent(
                        PostScriptOutputNaming.filename(for: name)
                    )
                    try await converter.convertToPostScript(
                        sourceURL: url,
                        outputURL: postScriptURL,
                        securityLimitsEnabled: settings.securityLimitsEnabled,
                        postScriptRandomSeed: settings.postScriptRandomSeed,
                        inputPassword: inputPassword
                    )
                }
                try Task.checkCancellation()
                let outputURL = directory.appendingPathComponent(
                    PostScriptEncryptor.outputFilename(for: sourceName)
                )
                try await Task.detached(priority: .userInitiated) {
                    try PostScriptEncryptor.encrypt(
                        inputURL: postScriptURL,
                        outputURL: outputURL,
                        password: password
                    )
                }.value
                try Task.checkCancellation()
                artifact = PostScriptExportArtifact(url: outputURL)
                finishProcessing()
                isFileExporterPresented = true
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: directory)
                finishProcessing()
                self.source = nil
                self.sourceURL = nil
            } catch {
                try? FileManager.default.removeItem(at: directory)
                finishProcessing()
                self.source = nil
                self.sourceURL = nil
                present(error)
            }
        }
    }

    func fileExporterDidFinish(_ result: Result<URL, Error>) {
        isFileExporterPresented = false
        let outputURL = artifact?.url
        artifact = nil
        source = nil
        sourceURL = nil
        if case .failure(let error) = result,
           (error as NSError).code != CocoaError.userCancelled.rawValue {
            present(error)
        }
        if let outputURL {
            removeExport(at: outputURL)
        }
    }

    func cancel() {
        encryptionTask?.cancel()
        encryptionTask = nil
        progressTask?.cancel()
        progressTask = nil
        let outputURL = artifact?.url
        artifact = nil
        source = nil
        sourceURL = nil
        isPasswordPromptPresented = false
        isFileExporterPresented = false
        isProcessing = false
        showsProgress = false
        if let outputURL {
            removeExport(at: outputURL)
        }
    }

    private func startProgressDelay() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            try? await Task.sleep(for: ConversionProgressDelay.duration)
            guard !Task.isCancelled, self?.isProcessing == true else { return }
            self?.showsProgress = true
        }
    }

    private func finishProcessing() {
        progressTask?.cancel()
        progressTask = nil
        encryptionTask = nil
        isProcessing = false
        showsProgress = false
    }

    private func present(_ error: Error) {
        alert = AppAlert(
            kind: .error,
            title: String(localized: "PostScript encryption failed"),
            message: error.localizedDescription
        )
    }

    private func removeExport(at outputURL: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PostScript Encryption Exports", isDirectory: true)
            .standardizedFileURL
        let directory = outputURL.standardizedFileURL.deletingLastPathComponent()
        guard directory.deletingLastPathComponent() == root else { return }
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private var canStart: Bool {
        !isProcessing && !isPasswordPromptPresented && !isFileExporterPresented
    }

    private enum Source: Sendable {
        case postScript(url: URL, sourceName: String)
        case pdf(url: URL, sourceName: String, inputPassword: String?)

        var sourceName: String {
            switch self {
            case .postScript(_, let sourceName), .pdf(_, let sourceName, _):
                sourceName
            }
        }
    }
}
