import Combine
import Foundation

@MainActor
final class ConversionViewModel: ObservableObject {
    @Published var selectedPDFVersion: PDFVersion
    @Published var selectedPDFACompatibility: PDFACompatibility
    @Published var isFileImporterPresented = false
    @Published private(set) var isProcessing = false
    @Published private(set) var showsProgressOverlay = false
    @Published var presentedPDF: PDFPresentation?
    @Published var isShareSheetPresented = false
    @Published var alert: AppAlert?

    private let settingsStore: SettingsStore
    private let workingDirectoryService: WorkingDirectoryService
    private let converter: any FileConverting
    private let startupCleanupTask: Task<Void, Error>

    private var progressTask: Task<Void, Never>?
    private var deferredNotice: AppAlert?
    private var viewerDismissalPending = false
    private var clearAfterViewerDismissal = true
    private var viewerDismissalWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        settingsStore: SettingsStore = SettingsStore(),
        workingDirectoryService: WorkingDirectoryService = WorkingDirectoryService(),
        converter: any FileConverting = GhostscriptConverter()
    ) {
        self.settingsStore = settingsStore
        self.workingDirectoryService = workingDirectoryService
        self.converter = converter
        selectedPDFVersion = settingsStore.pdfVersion
        selectedPDFACompatibility = settingsStore.pdfaCompatibility
        startupCleanupTask = Task.detached(priority: .utility) {
            try await workingDirectoryService.clearWorkingDirectory()
        }
    }

    var controlsAreDisabled: Bool {
        isProcessing || isShareSheetPresented || alert != nil
    }

    func setPDFVersion(_ version: PDFVersion) {
        guard !controlsAreDisabled else { return }
        selectedPDFVersion = version
        settingsStore.pdfVersion = version

        if selectedPDFACompatibility.requiredPDFVersion != version {
            selectedPDFACompatibility = .none
            settingsStore.pdfaCompatibility = .none
        }
    }

    func setPDFACompatibility(_ compatibility: PDFACompatibility) {
        guard !controlsAreDisabled else { return }
        selectedPDFACompatibility = compatibility
        settingsStore.pdfaCompatibility = compatibility

        if let requiredPDFVersion = compatibility.requiredPDFVersion,
           selectedPDFVersion != requiredPDFVersion {
            selectedPDFVersion = requiredPDFVersion
            settingsStore.pdfVersion = requiredPDFVersion
        }
    }

    func handleSelectedFile(_ url: URL) {
        acceptFiles([url])
    }

    func handleIncomingFiles(_ urls: [URL]) {
        isFileImporterPresented = false
        acceptFiles(urls)
    }

    func handleDroppedFile(_ url: URL) {
        let cleanupDirectory = url.deletingLastPathComponent()
        guard acceptFiles([url], cleanupDirectory: cleanupDirectory) else {
            Task { [workingDirectoryService] in
                await workingDirectoryService.removeDropStagingDirectory(cleanupDirectory)
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

        if shouldClear {
            Task.detached(priority: .utility) { [workingDirectoryService] in
                try? await workingDirectoryService.clearWorkingDirectory()
            }
        }
    }

    @discardableResult
    private func acceptFiles(_ urls: [URL], cleanupDirectory: URL? = nil) -> Bool {
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

        let versionSnapshot = selectedPDFVersion
        let pdfaCompatibilitySnapshot = selectedPDFACompatibility
        isProcessing = true
        showsProgressOverlay = false
        startProgressDelay()

        Task { [weak self, workingDirectoryService] in
            await self?.runConversion(
                sourceURL: url,
                version: versionSnapshot,
                pdfaCompatibility: pdfaCompatibilitySnapshot
            )
            if let cleanupDirectory {
                await workingDirectoryService.removeDropStagingDirectory(cleanupDirectory)
            }
        }
        return true
    }

    private func runConversion(
        sourceURL: URL,
        version: PDFVersion,
        pdfaCompatibility: PDFACompatibility
    ) async {
        do {
            await dismissViewerForReplacementIfNeeded()

            do {
                try await startupCleanupTask.value
            } catch {
                throw ConversionFailure.startupCleanup
            }

            try await workingDirectoryService.clearWorkingDirectory()
            let localSourceURL = try await workingDirectoryService.copySourceFile(from: sourceURL)
            let outputURL = await workingDirectoryService.outputURL(for: localSourceURL)

            try await converter.convert(
                sourceURL: localSourceURL,
                outputURL: outputURL,
                pdfVersion: version,
                pdfaCompatibility: pdfaCompatibility
            )
            try await workingDirectoryService.validatePDF(at: outputURL)

            finishProcessing()
            presentedPDF = PDFPresentation(url: outputURL)
        } catch let failure as ConversionFailure {
            await finishWithFailure(failure)
        } catch {
            await finishWithFailure(.ghostscriptConversion(returnCode: 0, diagnostics: ""))
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
        finishProcessing()
        alert = makeErrorAlert(for: failure)
    }

    private func finishProcessing() {
        progressTask?.cancel()
        progressTask = nil
        showsProgressOverlay = false
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
        if let diagnostics = failure.diagnostics {
            let format = String(localized: "error_diagnostics_format")
            messageParts.append(String(format: format, diagnostics))
        }
        if let returnCode = failure.returnCode {
            let format = String(localized: "error_return_code_format")
            messageParts.append(String(format: format, returnCode))
        }

        return AppAlert(
            kind: .error,
            title: String(localized: "conversion_failed"),
            message: messageParts.joined(separator: "\n\n")
        )
    }
}
