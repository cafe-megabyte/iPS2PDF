import Foundation

@MainActor
final class MacOSDocumentViewModel {
    enum Phase {
        case preparing
        case converting
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
    var onTerminalState: (() -> Void)?
    var onJoboptionsImported: (() -> Void)?
    var onShouldShowWindow: (() -> Void)?

    private let workspace = MacOSDocumentWorkspace()
    private let repository: JoboptionsRepository
    private let coordinator: MacOSConversionCoordinator
    private let router = IncomingDocumentRouter()
    private var didStart = false

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

        Task { [weak self] in
            guard let self else { return }
            do {
                let stagedURL = try await workspace.stageInput(from: sourceURL)
                await repository.waitUntilReady()

                switch try router.classify(stagedURL) {
                case let .joboptions(joboptionsURL, _):
                    phase = .converting
                    try await coordinator.validate(joboptionsURL: joboptionsURL)
                    _ = try repository.importJoboptions(from: joboptionsURL)
                    finish(with: .importedJoboptions)
                    onJoboptionsImported?()

                case let .conversionInput(inputURL):
                    phase = .converting
                    let settings = try repository.snapshot()
                    let joboptionsURL = try await workspace.writeJoboptions(
                        settings.effectiveJoboptionsData
                    )
                    let outputURL = await workspace.outputURL(
                        sourceName: sourceURL.lastPathComponent
                    )
                    try await coordinator.convert(
                        inputURL: inputURL,
                        outputURL: outputURL,
                        joboptionsURL: joboptionsURL,
                        settings: settings
                    )
                    try await workspace.validatePDF(at: outputURL)
                    onPDFReady?(outputURL)
                    finish(with: .pdf(outputURL))
                }
            } catch let failure as ConversionFailure {
                finish(with: .failed(Self.message(for: failure)))
            } catch {
                finish(with: .failed(error.localizedDescription))
            }
        }
    }

    func clearWorkspace() {
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
            case .pdf, .importedJoboptions, .failed:
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
            parts.append(String(diagnostics.suffix(4_000)))
        }
        return parts.joined(separator: "\n\n")
    }
}
