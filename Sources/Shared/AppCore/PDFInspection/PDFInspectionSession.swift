import Combine
import Foundation

@MainActor
final class PDFInspectionSession: ObservableObject, Identifiable {
    let id = UUID()
    @Published private(set) var report: PDFInspectionReport
    @Published private(set) var isReading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var passwordWasIncorrect = false
    private(set) var unlockedPassword: String?
    private var input: PDFInspectionInput?
    private var worker: Task<Void, Never>?
    private var generation = UUID()

    var currentInput: PDFInspectionInput? { input }

    init(url: URL) {
        report = PDFInspectionReport(fileName: url.lastPathComponent)
        isReading = true
        let generation = generation
        worker = Task { [weak self] in
            do {
                let snapshot = try await Task.detached(priority: .userInitiated) { try PDFInspectionInput(sourceURL: url) }.value
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                input = snapshot
                read(password: nil)
            } catch {
                guard let self, self.generation == generation else { return }
                errorMessage = error.localizedDescription; isReading = false
            }
        }
    }

    init(input: PDFInspectionInput) {
        self.input = input
        report = PDFInspectionReport(fileName: input.fileName)
        read(password: nil)
    }

    func unlock(_ password: String) { read(password: password) }

    func replaceInput(_ input: PDFInspectionInput, password: String?) {
        worker?.cancel()
        generation = UUID()
        self.input = input
        unlockedPassword = nil
        // Never show metadata from a previous revision while the replacement
        // is being inspected. The same observable session updates every view.
        report = PDFInspectionReport(fileName: input.fileName)
        read(password: password)
    }

    func cancel() {
        generation = UUID()
        worker?.cancel(); worker = nil; input = nil; unlockedPassword = nil; isReading = false
    }

    private func read(password: String?) {
        guard let input else { return }
        worker?.cancel()
        generation = UUID()
        let generation = generation
        errorMessage = nil; isReading = true; passwordWasIncorrect = false
        worker = Task { [weak self] in
            let update: @Sendable (PDFInspectionReport) -> Void = { [weak self] report in
                guard let self else { return }
                Task { @MainActor in
                    guard self.generation == generation, self.isReading else { return }
                    self.report = report
                }
            }
            let task = Task.detached(priority: .userInitiated) {
                try PDFInspectionService.inspect(url: input.url, fileName: input.fileName, password: password, fileDates: input.fileDates) { report in
                    update(report)
                }
            }
            do {
                let result = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                report = result; passwordWasIncorrect = password != nil && result.isLocked; isReading = false
                if !result.isLocked { unlockedPassword = password }
            } catch is CancellationError {
                // The closing/replacement presentation owns cancellation state.
            } catch {
                guard let self, self.generation == generation else { return }
                errorMessage = error.localizedDescription; isReading = false
            }
        }
    }
}
