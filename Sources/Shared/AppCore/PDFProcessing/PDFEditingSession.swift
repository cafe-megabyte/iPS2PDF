import Combine
import Foundation

@MainActor
final class PDFEditingSession: ObservableObject, Identifiable {
    let id = UUID()
    let fileName: String
    @Published private(set) var current: PDFEditingRevision?
    @Published private(set) var inspection: PDFInspectionSession?
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    private var original: PDFEditingRevision?
    private var undoRevisions: [PDFEditingRevision] = []
    private var redoRevisions: [PDFEditingRevision] = []
    private var loadTask: Task<Void, Never>?
    private var generation = UUID()
    private var openingPassword: String?

    // Keep file-backed history small on mobile devices. Readers retain their
    // immutable input independently, so evicting a revision never removes a
    // file still in use by a preview, export, or processing operation.
    private static let maximumHistoryCount = 6
    private static let maximumHistoryBytes: Int64 = 256 * 1024 * 1024

    var isEdited: Bool { current?.id != original?.id }
    var passwordForProcessing: String? { inspection?.unlockedPassword ?? openingPassword }

    init(url: URL) {
        fileName = url.lastPathComponent
        let generation = generation
        loadTask = Task { [weak self] in
            do {
                let input = try await Task.detached(priority: .userInitiated) {
                    try PDFInspectionInput(sourceURL: url)
                }.value
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                let revision = try PDFEditingRevision(input: input)
                original = revision
                install(revision)
                isLoading = false
            } catch {
                guard let self, self.generation == generation else { return }
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    init(input: PDFInspectionInput) throws {
        fileName = input.fileName
        let revision = try PDFEditingRevision(input: input)
        original = revision
        install(revision)
        isLoading = false
    }

    init(inspection: PDFInspectionSession) throws {
        guard let input = inspection.currentInput else { throw CocoaError(.fileReadUnknown) }
        fileName = input.fileName
        let revision = try PDFEditingRevision(input: input)
        original = revision
        current = revision
        self.inspection = inspection
        openingPassword = inspection.unlockedPassword
        isLoading = false
    }

    // Compression variants must use this immutable dialog input, never the
    // previous lossy candidate. A late result cannot replace a newer revision.
    @discardableResult
    func accept(_ revision: PDFEditingRevision, basedOn inputID: UUID) -> Bool {
        guard let current, current.id == inputID else { return false }
        undoRevisions.append(current)
        redoRevisions.removeAll()
        install(revision)
        trimHistory()
        return true
    }

    func undo() {
        guard let previous = undoRevisions.popLast(), let current else { return }
        redoRevisions.append(current)
        install(previous)
        updateHistoryAvailability()
    }

    func redo() {
        guard let next = redoRevisions.popLast(), let current else { return }
        undoRevisions.append(current)
        install(next)
        trimHistory()
    }

    func cancel() {
        generation = UUID()
        loadTask?.cancel()
        loadTask = nil
        inspection?.cancel()
        inspection = nil
        current = nil
        original = nil
        openingPassword = nil
        undoRevisions.removeAll()
        redoRevisions.removeAll()
        isLoading = false
        updateHistoryAvailability()
    }

    private func install(_ revision: PDFEditingRevision) {
        current = revision
        if let inspection {
            openingPassword = inspection.unlockedPassword ?? openingPassword
            inspection.replaceInput(revision.input, password: openingPassword)
        } else {
            inspection = PDFInspectionSession(input: revision.input)
        }
        errorMessage = nil
    }

    private func trimHistory() {
        var bytes = undoRevisions.reduce(Int64(0)) { $0 + $1.byteCount }
        while undoRevisions.count > Self.maximumHistoryCount || bytes > Self.maximumHistoryBytes {
            guard !undoRevisions.isEmpty else { break }
            bytes -= undoRevisions.removeFirst().byteCount
        }
        updateHistoryAvailability()
    }

    private func updateHistoryAvailability() {
        canUndo = !undoRevisions.isEmpty
        canRedo = !redoRevisions.isEmpty
    }
}
