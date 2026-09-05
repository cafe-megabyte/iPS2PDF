import Combine
import Foundation

@MainActor
final class ConversionViewModel: ObservableObject {
    @Published var selectedPDFVersion: PDFVersion
    @Published private(set) var isPDFVersionConstrained = false
    @Published var selectedPDFACompatibility: PDFACompatibility
    @Published var isFileImporterPresented = false
    @Published private(set) var isProcessing = false
    @Published private(set) var showsProgressOverlay = false
    @Published private(set) var preservesFileImporterSelectionAppearance = false
    @Published var presentedPDF: PDFPresentation?
    @Published var isShareSheetPresented = false
    @Published var alert: AppAlert?
    @Published var diagnosticDetails: DiagnosticPresentation?
    @Published private(set) var settingsPresentationToken = UUID()

    let joboptionsRepository: JoboptionsRepository

    private let workingDirectoryService: WorkingDirectoryService
    private let converter: any FileConverting
    private let documentRouter: IncomingDocumentRouter
    private let startupCleanupTask: Task<Void, Error>
    private var repositoryObservation: AnyCancellable?

    private var progressTask: Task<Void, Never>?
    private var deferredNotice: AppAlert?
    private var viewerDismissalPending = false
    private var clearAfterViewerDismissal = true
    private var viewerDismissalWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        joboptionsRepository: JoboptionsRepository? = nil,
        workingDirectoryService: WorkingDirectoryService = WorkingDirectoryService(),
        converter: any FileConverting = GhostscriptConverter(),
        documentRouter: IncomingDocumentRouter = IncomingDocumentRouter()
    ) {
        let joboptionsRepository = joboptionsRepository ?? JoboptionsRepository()
        self.joboptionsRepository = joboptionsRepository
        self.workingDirectoryService = workingDirectoryService
        self.converter = converter
        self.documentRouter = documentRouter
        selectedPDFVersion = .v13
        selectedPDFACompatibility = .none
        startupCleanupTask = Task.detached(priority: .utility) {
            try await workingDirectoryService.clearWorkingDirectory()
            try AppGroupWorkspace.clearStaleDataPreservingShareInbox()
        }
        repositoryObservation = joboptionsRepository.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.synchronizeFrontSettings()
            }
        }
        Task { [weak self, joboptionsRepository] in
            await joboptionsRepository.waitUntilReady()
            self?.synchronizeFrontSettings()
        }
    }

    var controlsAreDisabled: Bool {
        isProcessing || isShareSheetPresented || alert != nil
    }

    var controlsAppearDisabled: Bool {
        controlsAreDisabled && !preservesFileImporterSelectionAppearance
    }

    func setPDFVersion(_ version: PDFVersion) {
        guard !controlsAreDisabled,
              JoboptionsConsistencyEngine.pdfAConstrainedCompatibilityLevel(
                in: joboptionsRepository.activeDocument
              ) == nil else { return }
        do {
            try joboptionsRepository.update(
                key: "CompatibilityLevel",
                value: .number(Double(version.rawValue) ?? 1.3, original: version.rawValue)
            )
            synchronizeFrontSettings()
        } catch {
            joboptionsRepository.lastError = error.localizedDescription
        }
    }

    func setPDFACompatibility(_ compatibility: PDFACompatibility) {
        guard !controlsAreDisabled else { return }
        do {
            let standard: PDFStandard
            switch compatibility {
            case .none: standard = .none
            case .pdfa1b: standard = .pdfa1b
            case .pdfa2b: standard = .pdfa2b
            case .pdfa3b: standard = .pdfa3b
            }
            try joboptionsRepository.setStandard(standard)
            synchronizeFrontSettings()
        } catch {
            joboptionsRepository.lastError = error.localizedDescription
        }
    }

    func importJoboptions(_ url: URL) {
        acceptFiles([url])
    }

    func handleSelectedFile(_ url: URL) {
        acceptFiles([url], preservesSelectionAppearance: true)
    }

    func handleIncomingFiles(_ urls: [URL]) {
        isFileImporterPresented = false
        acceptFiles(urls)
    }

    func handleOpenURL(_ url: URL) {
        isFileImporterPresented = false
        guard PendingShareDocument.isTriggerURL(url) else {
            acceptFiles([url])
            return
        }
        handlePendingShareDocumentIfAvailable()
    }

    func handleDroppedFile(_ url: URL) {
        let cleanupDirectory = url.deletingLastPathComponent()
        guard acceptFiles([url], cleanupDirectory: cleanupDirectory) else {
            Task { [workingDirectoryService] in
                await workingDirectoryService.removeStagingDirectory(cleanupDirectory)
            }
            return
        }
    }

    func handleDroppedFileLoadFailure() {
        guard !controlsAreDisabled else { return }
        alert = makeErrorAlert(for: .inputCannotBeRead)
    }

    func dismissAlert() {
        alert = nil
        presentDeferredNoticeIfPossible()
    }

    func showDetails(for alert: AppAlert) {
        guard let details = alert.details else { return }
        self.alert = nil
        diagnosticDetails = DiagnosticPresentation(title: alert.title, text: details)
    }

    func diagnosticDetailsDidDismiss() {
        presentDeferredNoticeIfPossible()
    }

    func handlePendingShareDocumentIfAvailable() {
        if isProcessing {
            PendingShareDocument.remove()
            return
        }
        guard !controlsAreDisabled else { return }
        do {
            guard let sourceURL = try PendingShareDocument.claimPendingSourceURL() else {
                PendingShareDocument.remove()
                return
            }
            let cleanupDirectory = sourceURL.deletingLastPathComponent()
            _ = acceptFiles([sourceURL], cleanupDirectory: cleanupDirectory)
        } catch {
            alert = makeErrorAlert(for: .inputCannotBeRead)
        }
    }

    func beginSharing() {
        isShareSheetPresented = true
    }

    func endSharing() {
        isShareSheetPresented = false
        presentDeferredNoticeIfPossible()
    }

    func closePDFViewer() {
        guard presentedPDF != nil else { return }
        clearAfterViewerDismissal = true
        viewerDismissalPending = true
        presentedPDF = nil
    }

    func pdfViewerDidDismiss() {
        viewerDismissalPending = false
        let shouldClear = clearAfterViewerDismissal
        clearAfterViewerDismissal = true

        let waiters = viewerDismissalWaiters
        viewerDismissalWaiters.removeAll()
        waiters.forEach { $0.resume() }

        preservesFileImporterSelectionAppearance = false

        if shouldClear {
            Task.detached(priority: .utility) { [workingDirectoryService] in
                try? await workingDirectoryService.clearWorkingDirectory()
            }
        }
    }

    @discardableResult
    private func acceptFiles(
        _ urls: [URL],
        cleanupDirectory: URL? = nil,
        preservesSelectionAppearance: Bool = false
    ) -> Bool {
        guard urls.count == 1, let url = urls.first else {
            presentNotice(
                title: String(localized: "notice_multiple_files_title"),
                message: String(localized: "notice_multiple_files_message")
            )
            return false
        }

        guard !controlsAreDisabled else {
            presentNotice(
                title: String(localized: "notice_busy_title"),
                message: String(localized: "notice_busy_message")
            )
            return false
        }

        isProcessing = true
        preservesFileImporterSelectionAppearance = preservesSelectionAppearance
        showsProgressOverlay = false
        startProgressDelay()

        Task { [weak self, workingDirectoryService] in
            await self?.runConversion(
                sourceURL: url
            )
            if let cleanupDirectory {
                await workingDirectoryService.removeStagingDirectory(cleanupDirectory)
            }
        }
        return true
    }

    private func runConversion(sourceURL: URL) async {
        do {
            await dismissViewerForReplacementIfNeeded()

            do {
                try await startupCleanupTask.value
            } catch {
                throw ConversionFailure.startupCleanup
            }

            try await workingDirectoryService.clearWorkingDirectory()
            let localSourceURL = try await workingDirectoryService.copySourceFile(from: sourceURL)
            await joboptionsRepository.waitUntilReady()

            switch try documentRouter.classify(localSourceURL) {
            case let .joboptions(joboptionsURL, _):
                try await converter.validateJoboptions(at: joboptionsURL)
                _ = try joboptionsRepository.importJoboptions(from: joboptionsURL)
                try? AppGroupWorkspace.clearAll()
                finishProcessing()
                synchronizeFrontSettings()
                settingsPresentationToken = UUID()
            case let .conversionInput(inputURL):
                // Capture only after the readiness gate, and keep this immutable
                // for the lifetime of the conversion.
                let settingsSnapshot = try joboptionsRepository.snapshot()
                let outputURL = try await workingDirectoryService.outputURL(for: inputURL)
                let snapshotURL = try await workingDirectoryService.writeJoboptionsSnapshot(
                    settingsSnapshot.effectiveJoboptionsData
                )
                try await converter.convert(
                    sourceURL: inputURL,
                    outputURL: outputURL,
                    joboptionsURL: snapshotURL,
                    standard: settingsSnapshot.standard,
                    securityLimitsEnabled: settingsSnapshot.securityLimitsEnabled,
                    postScriptRandomSeed: settingsSnapshot.postScriptRandomSeed
                )
                try await workingDirectoryService.validatePDF(at: outputURL)

                try? AppGroupWorkspace.clearAll()
                presentedPDF = PDFPresentation(url: outputURL)
                finishProcessing(preservesSelectionAppearance: true)
            }
        } catch let failure as ConversionFailure {
            await finishWithFailure(failure)
        } catch {
            await finishWithFailure(.joboptions(diagnostics: error.localizedDescription))
        }
    }

    private func dismissViewerForReplacementIfNeeded() async {
        guard presentedPDF != nil || viewerDismissalPending else { return }

        clearAfterViewerDismissal = false
        if presentedPDF != nil {
            viewerDismissalPending = true
            presentedPDF = nil
        }

        await withCheckedContinuation { continuation in
            viewerDismissalWaiters.append(continuation)
        }
    }

    private func finishWithFailure(_ failure: ConversionFailure) async {
        try? await workingDirectoryService.clearWorkingDirectory()
        try? AppGroupWorkspace.clearAll()
        finishProcessing()
        alert = makeErrorAlert(for: failure)
    }

    private func finishProcessing(preservesSelectionAppearance: Bool = false) {
        progressTask?.cancel()
        progressTask = nil
        showsProgressOverlay = false
        if !preservesSelectionAppearance {
            preservesFileImporterSelectionAppearance = false
        }
        isProcessing = false
    }

    private func startProgressDelay() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, self?.isProcessing == true else { return }
            self?.showsProgressOverlay = true
        }
    }

    private func presentNotice(title: String, message: String) {
        let notice = AppAlert(
            kind: .notice,
            title: title,
            message: message
        )

        if alert != nil || isShareSheetPresented {
            deferredNotice = notice
        } else {
            alert = notice
        }
    }

    private func presentDeferredNoticeIfPossible() {
        guard alert == nil, !isShareSheetPresented, let deferredNotice else { return }
        self.deferredNotice = nil
        alert = deferredNotice
    }

    private func makeErrorAlert(for failure: ConversionFailure) -> AppAlert {
        var messageParts = [failure.localizedMessage]
        var detailsParts: [String] = []
        if let diagnostics = failure.diagnostics {
            let format = String(localized: "error_diagnostics_format")
            let tail = String(diagnostics.suffix(8_000))
            messageParts.append(String(format: format, tail))
            detailsParts.append(diagnostics)
        }
        if let returnCode = failure.returnCode {
            let format = String(localized: "error_return_code_format")
            messageParts.append(String(format: format, returnCode))
            detailsParts.insert(String(format: format, returnCode), at: 0)
        }

        return AppAlert(
            kind: .error,
            title: String(localized: "conversion_failed"),
            message: messageParts.joined(separator: "\n\n"),
            details: detailsParts.isEmpty ? nil : detailsParts.joined(separator: "\n\n")
        )
    }

    private func synchronizeFrontSettings() {
        let compatibility: PDFACompatibility = switch joboptionsRepository.activeStandard {
        case .pdfa1b: .pdfa1b
        case .pdfa2b: .pdfa2b
        case .pdfa3b: .pdfa3b
        default: .none
        }
        selectedPDFACompatibility = compatibility
        let constrainedVersion = JoboptionsConsistencyEngine.pdfAConstrainedCompatibilityLevel(
            in: joboptionsRepository.activeDocument
        )
        isPDFVersionConstrained = constrainedVersion != nil
        selectedPDFVersion = PDFVersion(rawValue: constrainedVersion ?? joboptionsRepository.compatibilityLevel)
            ?? .v13
    }

}
