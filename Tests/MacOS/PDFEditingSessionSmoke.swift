import Foundation

@main
struct PDFEditingSessionSmoke {
    @MainActor
    static func waitForInspection(_ session: PDFEditingSession) async throws {
        let deadline = Date().addingTimeInterval(15)
        while session.isLoading || session.inspection?.isReading == true {
            guard Date() < deadline else { throw CocoaError(.coderReadCorrupt) }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(session.errorMessage == nil && session.inspection?.errorMessage == nil)
    }

    @MainActor
    static func main() async throws {
        let jobs = FileManager.default.temporaryDirectory.appendingPathComponent("PDFJobSmoke-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: jobs) }
        var sender: PDFProcessingJobDirectory? = try .create(root: jobs)
        let jobURL = sender!.url
        let inputURL = sender!.inputURL
        try Data("private job input".utf8).write(to: inputURL)
        var helper: PDFProcessingJobDirectory? = try .open(id: sender!.id, root: jobs)
        precondition(helper?.url == jobURL)
        sender = nil
        precondition(FileManager.default.fileExists(atPath: inputURL.path), "Sender cleanup removed a running helper's input")
        try PDFProcessingJobDirectory.removeStaleJobs(root: jobs, now: Date().addingTimeInterval(24 * 60 * 60))
        precondition(FileManager.default.fileExists(atPath: inputURL.path), "Stale cleanup removed an active job")
        helper = nil
        precondition(!FileManager.default.fileExists(atPath: jobURL.path), "Finished job directory was retained")
        print("PASS processing job leases: sender/helper lifetime and cleanup exclusion")
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[1])
        let originalURL = fixtures.appendingPathComponent("InfoEncrypted-AES-256.pdf")
        let originalBytes = try Data(contentsOf: originalURL)
        let session = PDFEditingSession(url: originalURL)
        try await waitForInspection(session)
        precondition(session.inspection?.report.isLocked == true)
        session.inspection?.unlock("user-test")
        try await waitForInspection(session)
        precondition(session.inspection?.report.isLocked == false)
        let original = session.current!
        let input = try PDFInspectionInput(sourceURL: fixtures.appendingPathComponent("InfoPlain.pdf"), displayFileName: session.fileName)
        let candidate = try PDFEditingRevision(input: input, warnings: [.protectionRemoved])
        let observer = session.inspection
        precondition(session.accept(candidate, basedOn: original.id))
        precondition(session.inspection === observer)
        precondition(session.inspection?.report.sections.isEmpty == true, "Stale metadata appeared after revision change")
        precondition(session.current?.id == candidate.id && session.isEdited && session.canUndo)
        precondition(!session.accept(original, basedOn: original.id), "Late processing result replaced a newer revision")
        try await waitForInspection(session)
        precondition(session.inspection?.report.fileName == originalURL.lastPathComponent)
        session.undo()
        try await waitForInspection(session)
        precondition(session.current?.id == original.id && !session.isEdited && session.canRedo)
        precondition(session.inspection?.report.isLocked == false, "Undo lost the opening password")
        session.redo()
        precondition(session.current?.id == candidate.id)
        let bytesAfterEditing = try Data(contentsOf: originalURL)
        precondition(bytesAfterEditing == originalBytes, "The original file was modified")
        let retainedURL = candidate.input.url
        session.cancel()
        precondition(session.current == nil && session.inspection == nil)
        precondition(FileManager.default.fileExists(atPath: retainedURL.path), "Closing the editor invalidated an active reader")
        print("PASS editing session: atomic info replacement, stale-result rejection, undo/redo, password retention and original-file preservation")
    }
}
