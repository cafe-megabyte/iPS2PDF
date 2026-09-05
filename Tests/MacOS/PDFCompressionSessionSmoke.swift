import Foundation

private actor ProcessingQueue {
    struct Call {
        let inputID: UUID
        let options: PDFCompressionOptions
        let page: Int?
        let continuation: CheckedContinuation<PDFEditingRevision, any Error>
    }
    var calls: [Call] = []
    func process(_ input: PDFEditingRevision, _ options: PDFCompressionOptions, _ page: Int?) async throws -> PDFEditingRevision {
        // Deliberately ignore cancellation to simulate a late helper response.
        try await withCheckedThrowingContinuation { continuation in
            calls.append(Call(inputID: input.id, options: options, page: page, continuation: continuation))
        }
    }
    func count() -> Int { calls.count }
    func finish(_ index: Int, with revision: PDFEditingRevision) { calls[index].continuation.resume(returning: revision) }
    func inputs() -> [UUID] { calls.map(\.inputID) }
    func pages() -> [Int?] { calls.map(\.page) }
}

@main @MainActor
struct PDFCompressionSessionSmoke {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "PDFCompressionSessionSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func wait(_ condition: @escaping () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !(await condition()) {
            try require(ContinuousClock.now < deadline, "Timed out waiting for a compression model transition")
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    static func main() async throws {
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[1])
        let source = fixtures.appendingPathComponent("InfoPlain.pdf")
        let unchanged = try Data(contentsOf: source)
        let editing = try PDFEditingSession(input: PDFInspectionInput(sourceURL: source))
        let preview = try PDFEditingRevision(input: PDFInspectionInput(sourceURL: source))
        let larger = try PDFEditingRevision(input: PDFInspectionInput(sourceURL: fixtures.appendingPathComponent("InfoEmbeddedFull.pdf")))
        let queue = ProcessingQueue()
        let model = try PDFCompressionSession(editing: editing) { input, options, _, page in
            try await queue.process(input, options, page)
        }
        model.start()
        try await wait { await queue.count() == 1 }
        model.options.level = .strong
        try await wait { await queue.count() == 2 }
        await queue.finish(0, with: preview)
        try await Task.sleep(for: .milliseconds(25))
        try require(model.pagePreview == nil && model.candidate == nil, "An obsolete page preview was published")
        await queue.finish(1, with: preview)
        try await wait { await queue.count() == 3 }
        try require(model.pagePreview?.id == preview.id && model.resultSize == nil && !model.canAccept,
                    "A page-only preview acquired a file size or could be accepted")
        model.options.colorMode = .blackAndWhite
        try await wait { model.pagePreview == nil && model.candidate == nil }
        try await wait { await queue.count() == 4 }
        await queue.finish(2, with: larger)
        try await Task.sleep(for: .milliseconds(25))
        try require(model.candidate == nil, "A late full result replaced newer options")
        await queue.finish(3, with: preview)
        try await wait { await queue.count() == 5 }
        await queue.finish(4, with: larger)
        try await wait { model.canAccept }
        try require(larger.byteCount > model.input.byteCount && model.resultSize != nil, "A larger valid result was suppressed")
        try require(await queue.inputs().allSatisfy { $0 == model.input.id }, "Compression reused a lossy candidate as its input")
        try require(await queue.pages() == [0, 0, nil, 0, nil], "Preview and full-document operations were confused")
        try require(model.accept() && editing.current?.id == larger.id && editing.canUndo, "Accept did not install one undoable revision")
        editing.undo()
        try require(editing.current?.id == model.input.id, "Undo did not restore the frozen source")
        try require(try Data(contentsOf: source) == unchanged, "Compression model changed the original file")
        let second = try PDFCompressionSession(editing: editing) { _, _, _, _ in larger }
        second.start()
        try await wait { second.canAccept }
        try require(editing.accept(preview, basedOn: second.input.id), "Could not simulate an edit in another window")
        try await wait { second.errorMessage != nil }
        try require(!second.canAccept && second.candidate == nil, "A dialog based on an obsolete document remained adoptable")
        model.cancel(); second.cancel(); editing.cancel()
        print("PASS compression model: frozen input, stale page/full responses, preview-only isolation, current sizes, larger results, acceptance, undo and concurrent document edits")
    }
}
