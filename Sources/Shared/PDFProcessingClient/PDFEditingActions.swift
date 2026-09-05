import Combine
import Foundation

@MainActor
final class PDFEditingActions: ObservableObject {
    let inspection: PDFInspectionSession
    @Published private(set) var editing: PDFEditingSession?
    @Published private(set) var isProcessing = false
    @Published var errorMessage: String?
    @Published var notice: String?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var observation: AnyCancellable?

    init(inspection: PDFInspectionSession, editing: PDFEditingSession? = nil) {
        self.inspection = inspection
        self.editing = editing
        observeEditing()
    }

    func editingSession() throws -> PDFEditingSession {
        if let editing { return editing }
        let session = try PDFEditingSession(inspection: inspection)
        editing = session
        observeEditing()
        return session
    }

    func removeMetadata(preserveConformity: Bool) {
        guard !isProcessing, !inspection.report.isLocked else { return }
        do {
            let editing = try editingSession()
            guard let input = editing.current else { throw PDFProcessingError.failed }
            isProcessing = true
            errorMessage = nil
            notice = nil
            generation = UUID()
            let token = generation
            let password = editing.passwordForProcessing
            task = Task { [weak self] in
                do {
                    let candidate = try await PDFProcessingClient().process(input, operation: .removeMetadata,
                                                                            preserveConformity: preserveConformity,
                                                                            password: password)
                    guard let self, generation == token, !Task.isCancelled else { return }
                    if editing.accept(candidate, basedOn: input.id) {
                        if !candidate.warnings.isEmpty { notice = candidate.warnings.map(\.message).joined(separator: "\n\n") }
                    }
                    isProcessing = false
                    task = nil
                } catch {
                    guard let self, generation == token else { return }
                    isProcessing = false
                    task = nil
                    if !(error is CancellationError) { errorMessage = error.localizedDescription }
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        isProcessing = false
    }

    private func observeEditing() {
        observation = editing?.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.objectWillChange.send() }
        }
    }
}
