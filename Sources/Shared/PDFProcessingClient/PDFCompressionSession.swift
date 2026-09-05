import Combine
import Foundation

@MainActor
final class PDFCompressionSession: ObservableObject, Identifiable {
    typealias Processor = @Sendable (PDFEditingRevision, PDFCompressionOptions, String?, Int?) async throws -> PDFEditingRevision
    let id = UUID()
    let editing: PDFEditingSession
    let input: PDFEditingRevision
    private(set) var password: String?
    @Published var options = PDFCompressionOptions() { didSet { if options != oldValue { scheduleAfterViewUpdate() } } }
    @Published private(set) var candidate: PDFEditingRevision?
    @Published private(set) var pagePreview: PDFEditingRevision?
    @Published private(set) var previewPageIndex: Int?
    @Published private(set) var isProcessing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var passwordRequired = false
    @Published var currentPage = 0
    private var task: Task<Void, Never>?
    private var pendingSchedule: Task<Void, Never>?
    private var generation = UUID()
    private var editingObservation: AnyCancellable?
    private let processor: Processor

    init(editing: PDFEditingSession, processor: @escaping Processor = { input, options, password, page in
        try await PDFProcessingClient().process(input, operation: .compress, preserveConformity: false,
                                               compression: options, password: password, previewPage: page)
    }) throws {
        guard let input = editing.current else { throw PDFProcessingError.failed }
        self.editing = editing
        self.input = input
        self.processor = processor
        password = editing.passwordForProcessing
        editingObservation = editing.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, editing.current?.id != input.id else { return }
                cancel()
                candidate = nil
                pagePreview = nil
                errorMessage = String(localized: "The PDF changed while the preview was being prepared. Open compression again.")
            }
        }
    }

    var canAccept: Bool { candidate != nil && !isProcessing && editing.current?.id == input.id }
    var originalSize: String { ByteCountFormatter.string(fromByteCount: input.byteCount, countStyle: .file) }
    var resultSize: String? {
        guard let candidate else { return nil }
        return ByteCountFormatter.string(fromByteCount: candidate.byteCount, countStyle: .file)
    }
    var sizeDifference: String? {
        guard let candidate, input.byteCount > 0 else { return nil }
        let difference = 100 * (Double(candidate.byteCount) / Double(input.byteCount) - 1)
        return String.localizedStringWithFormat(String(localized: "%+.1f%% compared with the original"), difference)
    }

    func start() { if task == nil && candidate == nil { schedule() } }
    func retry() { schedule() }
    func unlock(_ value: String) {
        password = value
        editing.inspection?.unlock(value)
        passwordRequired = false
        schedule()
    }
    func cancel() {
        pendingSchedule?.cancel()
        pendingSchedule = nil
        generation = UUID()
        task?.cancel()
        task = nil
        isProcessing = false
    }
    @discardableResult
    func accept() -> Bool {
        guard canAccept, let candidate else { return false }
        return editing.accept(candidate, basedOn: input.id)
    }
    private func scheduleAfterViewUpdate() {
        pendingSchedule?.cancel()
        pendingSchedule = Task { @MainActor [weak self] in
            // A Picker or Slider can mutate options while SwiftUI is updating
            // the view. Publish the dependent state on the next actor turn.
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            pendingSchedule = nil
            schedule()
        }
    }
    private func schedule() {
        cancel()
        // An old size or preview must never describe the newly selected
        // options. Every candidate starts from this dialog's frozen input.
        candidate = nil
        pagePreview = nil
        previewPageIndex = nil
        errorMessage = nil
        isProcessing = true
        let token = generation
        let settings = options
        let page = currentPage
        let fullDeadline = ContinuousClock.now.advanced(by: .milliseconds(400))
        task = Task { [weak self] in
            guard let self else { return }
            do {
                // Coalesce slider events before the native page job. The full
                // document follows after the agreed 400 ms quiet interval.
                try await Task.sleep(for: .milliseconds(70))
                let preview = try await processor(input, settings, password, page)
                guard generation == token, !Task.isCancelled else { return }
                pagePreview = preview
                previewPageIndex = page
                try await ContinuousClock().sleep(until: fullDeadline)
                let finished = try await processor(input, settings, password, nil)
                guard generation == token, !Task.isCancelled else { return }
                candidate = finished
                pagePreview = nil
                previewPageIndex = nil
                isProcessing = false
                task = nil
            } catch {
                guard generation == token else { return }
                isProcessing = false
                task = nil
                if let error = error as? PDFProcessingError, case .passwordRequired = error {
                    passwordRequired = true
                } else if !(error is CancellationError) { errorMessage = error.localizedDescription }
            }
        }
    }
}
