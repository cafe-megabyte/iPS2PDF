import Foundation

@MainActor
final class PostScriptExportSession: ObservableObject {
    @Published private(set) var isProcessing = false
    @Published private(set) var showsProgress = false
    @Published private(set) var artifact: PostScriptExportArtifact?
    @Published var isFileExporterPresented = false
    @Published var alert: AppAlert?
    @Published var diagnosticDetails: DiagnosticPresentation?

    private let runtimeSettings: GhostscriptRuntimeSettings
    private let converter: any FileConverting
    private let workingDirectoryService: WorkingDirectoryService
    private var conversionTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?

    init(
        runtimeSettings: GhostscriptRuntimeSettings,
        converter: any FileConverting = GhostscriptConverter(),
        workingDirectoryService: WorkingDirectoryService = WorkingDirectoryService()
    ) {
        self.runtimeSettings = runtimeSettings
        self.converter = converter
        self.workingDirectoryService = workingDirectoryService
    }

    func start(sourceURL: URL, sourceName: String, inputPassword: String?) {
        guard !isProcessing, !isFileExporterPresented else { return }
        isProcessing = true
        showsProgress = false
        startProgressDelay()
        let settings = runtimeSettings.snapshot()
        conversionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let outputURL = try await workingDirectoryService.postScriptOutputURL(
                    sourceName: sourceName
                )
                try await converter.convertToPostScript(
                    sourceURL: sourceURL,
                    outputURL: outputURL,
                    securityLimitsEnabled: settings.securityLimitsEnabled,
                    postScriptRandomSeed: settings.postScriptRandomSeed,
                    inputPassword: inputPassword
                )
                try? AppGroupWorkspace.clearAll()
                artifact = PostScriptExportArtifact(url: outputURL)
                finishProcessing()
                isFileExporterPresented = true
            } catch is CancellationError {
                try? AppGroupWorkspace.clearAll()
                finishProcessing()
            } catch let failure as ConversionFailure {
                try? AppGroupWorkspace.clearAll()
                finishProcessing()
                alert = failure.appAlert
            } catch {
                try? AppGroupWorkspace.clearAll()
                finishProcessing()
                alert = ConversionFailure.ghostscriptConversion(
                    returnCode: 0,
                    diagnostics: error.localizedDescription
                ).appAlert
            }
        }
    }

    func fileExporterDidFinish(_ result: Result<URL, Error>) {
        isFileExporterPresented = false
        let outputURL = artifact?.url
        artifact = nil
        if case let .failure(error) = result,
           (error as NSError).code != CocoaError.userCancelled.rawValue {
            alert = AppAlert(
                kind: .error,
                title: String(localized: "conversion_failed"),
                message: error.localizedDescription
            )
        }
        if let outputURL {
            Task.detached(priority: .utility) { [workingDirectoryService] in
                await workingDirectoryService.removePostScriptExport(at: outputURL)
            }
        }
    }

    func showDetails(for alert: AppAlert) {
        guard let details = alert.details else { return }
        self.alert = nil
        diagnosticDetails = DiagnosticPresentation(title: alert.title, text: details)
    }

    func cancel() {
        conversionTask?.cancel()
        conversionTask = nil
        progressTask?.cancel()
        progressTask = nil
        let outputURL = artifact?.url
        artifact = nil
        isProcessing = false
        showsProgress = false
        if let outputURL {
            Task.detached(priority: .utility) { [workingDirectoryService] in
                await workingDirectoryService.removePostScriptExport(at: outputURL)
            }
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
        conversionTask = nil
        isProcessing = false
        showsProgress = false
    }
}
