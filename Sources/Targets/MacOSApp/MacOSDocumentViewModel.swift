import Foundation
import Combine

@MainActor
final class MacOSDocumentViewModel {
    enum Phase {
        case preparing
        case converting
        case awaitingPassword
        case cancelled
        case pdf(URL)
        case importedJoboptions
        case failed(String)
    }

    private(set) var phase: Phase = .preparing
    {
        didSet {
            onPhaseChange?(phase)
        }
    }
    private(set) var showsSpinner = false
    {
        didSet {
            onSpinnerVisibilityChange?(showsSpinner)
        }
    }

    var onPhaseChange: ((Phase) -> Void)?
    var onSpinnerVisibilityChange: ((Bool) -> Void)?
    var onPDFReady: ((URL) -> Void)?
    var onPDFEdited: ((PDFEditingRevision, Bool) -> Void)?
    var onTerminalState: (() -> Void)?
    var onJoboptionsImported: (() -> Void)?
    var onShouldShowWindow: (() -> Void)?

    let passwordController = PDFPasswordController()

    private let workspace = MacOSDocumentWorkspace()
    private let repository: JoboptionsRepository
    private let coordinator: MacOSConversionCoordinator
    private let router = IncomingDocumentRouter()
    private var didStart = false
    private var conversionTask: Task<Void, Never>?
    private(set) var editingSession: PDFEditingSession?
    private var editingObservation: AnyCancellable?

    init(
        repository: JoboptionsRepository = MacOSApplicationModel.shared.joboptionsRepository,
        coordinator: MacOSConversionCoordinator = MacOSApplicationModel.shared.conversionCoordinator
    ) {
        self.repository = repository
        self.coordinator = coordinator
    }

    var pdfURL: URL? {
        guard case let .pdf(url) = phase else { return nil }
        return url
    }

    func start(sourceURL: URL) {
        guard !didStart else { return }
        didStart = true
        phase = .preparing
        startSpinnerDelay()

        conversionTask = Task { [weak self] in
            guard let self else { return }
            let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess { sourceURL.stopAccessingSecurityScopedResource() }
            }
            do {
                let stagedURL = try await workspace.stageInput(from: sourceURL)
                await repository.waitUntilReady()

                switch try router.classify(stagedURL, purpose: .conversion) {
                case let .joboptions(joboptionsURL, _):
                    phase = .converting
                    try await coordinator.validate(joboptionsURL: joboptionsURL)
                    _ = try repository.importJoboptions(from: joboptionsURL)
                    finish(with: .importedJoboptions)
                    onJoboptionsImported?()

                case let .conversionInput(inputURL), let .pdfInformation(inputURL):
                    phase = .converting
                    let settings = try repository.snapshot()
                    let joboptionsURL = try await workspace.writeJoboptions(
                        settings.effectiveJoboptionsData
                    )
                    let outputURL = await workspace.outputURL(
                        sourceName: sourceURL.lastPathComponent
                    )
                    var inputPassword: String?
                    if !(await PDFPasswordController.canOpen(inputURL, password: nil)) {
                        phase = .awaitingPassword
                        showsSpinner = false
                        onShouldShowWindow?()
                        inputPassword = try await passwordController.password(for: inputURL)
                    }
                    while true {
                        phase = .converting
                        startSpinnerDelay()
                        do {
                            try await coordinator.convert(
                                inputURL: inputURL,
                                outputURL: outputURL,
                                joboptionsURL: joboptionsURL,
                                settings: settings,
                                inputPassword: inputPassword
                            )
                            break
                        } catch ConversionFailure.inputPasswordRequired {
                            phase = .awaitingPassword
                            showsSpinner = false
                            onShouldShowWindow?()
                            inputPassword = try await passwordController.password(for: inputURL, force: true)
                        }
                    }
                    inputPassword = nil
                    try await workspace.validatePDF(at: outputURL)
                    let snapshot = try await Task.detached(priority: .userInitiated) {
                        try PDFInspectionInput(sourceURL: outputURL)
                    }.value
                    let editing = try PDFEditingSession(input: snapshot)
                    editingSession = editing
                    let originalID = editing.current?.id
                    editingObservation = editing.$current.dropFirst().sink { [weak self] revision in
                        guard let self, let revision else { return }
                        phase = .pdf(revision.input.url)
                        onPDFEdited?(revision, revision.id != originalID)
                    }
                    onPDFReady?(snapshot.url)
                    finish(with: .pdf(snapshot.url))
                }
            } catch is CancellationError {
                finish(with: .cancelled)
            } catch let failure as ConversionFailure {
                finish(with: .failed(Self.message(for: failure)))
            } catch {
                finish(with: .failed(error.localizedDescription))
            }
        }
    }

    func clearWorkspace() {
        conversionTask?.cancel()
        passwordController.cancel()
        Task { try? await workspace.clear() }
    }

    private func startSpinnerDelay() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, pdfURL == nil else { return }
            switch phase {
            case .preparing, .converting:
                showsSpinner = true
                onShouldShowWindow?()
            case .pdf, .importedJoboptions, .failed, .awaitingPassword, .cancelled:
                break
            }
        }
    }

    private func finish(with phase: Phase) {
        self.phase = phase
        showsSpinner = false
        if case .failed = phase {
            onShouldShowWindow?()
        }
        onTerminalState?()
    }

    private static func message(for failure: ConversionFailure) -> String {
        var parts = [failure.localizedMessage]
        if let code = failure.returnCode {
            parts.append(
                String.localizedStringWithFormat(
                    String(localized: "Ghostscript return code: %lld"),
                    code
                )
            )
        }
        if let diagnostics = failure.diagnostics {
            parts.append(String(diagnostics.suffix(8_000)))
        }
        return parts.joined(separator: "\n\n")
    }
}
