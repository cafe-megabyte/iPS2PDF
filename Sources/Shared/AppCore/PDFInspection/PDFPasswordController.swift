import Combine
import CoreGraphics
import Foundation

@MainActor
final class PDFPasswordController: ObservableObject {
    @Published private(set) var request: PDFPasswordRequest?
    @Published private(set) var isChecking = false
    private var cancellationGeneration = UUID()
    private var continuation: CheckedContinuation<String, Error>?

    func password(for url: URL, force: Bool = false) async throws -> String? {
        let generation = cancellationGeneration
        defer { request = nil; isChecking = false }
        if !force, await Self.canOpen(url, password: nil) { return nil }
        var incorrect = force
        while true {
            try Task.checkCancellation()
            let value = try await ask(fileName: url.lastPathComponent, incorrect: incorrect)
            let accepted = await Self.canOpen(url, password: value)
            try Task.checkCancellation()
            guard generation == cancellationGeneration else { throw CancellationError() }
            if accepted { return value }
            incorrect = true
        }
    }
    func ask(fileName: String, incorrect: Bool) async throws -> String {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                isChecking = false
                request = PDFPasswordRequest(fileName: fileName, wasIncorrect: incorrect)
            }
        } onCancel: { Task { @MainActor [weak self] in self?.cancel() } }
    }
    func submit(_ password: String) {
        let continuation = continuation; self.continuation = nil; isChecking = true
        continuation?.resume(returning: password)
    }
    func cancel() {
        cancellationGeneration = UUID()
        let continuation = continuation; self.continuation = nil; request = nil
        isChecking = false
        continuation?.resume(throwing: CancellationError())
    }
    nonisolated static func canOpen(_ url: URL, password: String?) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            // Non-PDF input remains accepted by the conversion path.
            guard let document = CGPDFDocument(url as CFURL), document.isEncrypted else { return true }
            if document.isUnlocked { return true }
            return document.unlockWithPassword(password ?? "")
        }.value
    }
}
