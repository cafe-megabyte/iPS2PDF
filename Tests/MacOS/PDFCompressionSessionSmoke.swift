import Foundation

@main @MainActor
struct PDFCompressionSessionSmoke {
    private actor ProcessingQueue {
        struct Call {
            let inputID: UUID
            let options: PDFCompressionOptions
            let overrides: [PDFPageCompressionOverride]
            let page: Int?
            let continuation: CheckedContinuation<PDFEditingRevision, any Error>
        }
        var calls: [Call] = []
        func process(_ input: PDFEditingRevision, _ options: PDFCompressionOptions,
                     _ overrides: [PDFPageCompressionOverride], _ page: Int?) async throws -> PDFEditingRevision {
            // Deliberately ignore cancellation to simulate a late helper response.
            try await withCheckedThrowingContinuation { continuation in
                calls.append(Call(inputID: input.id, options: options, overrides: overrides,
                                  page: page, continuation: continuation))
            }
        }
        func count() -> Int { calls.count }
        func finish(_ index: Int, with revision: PDFEditingRevision) { calls[index].continuation.resume(returning: revision) }
        func inputs() -> [UUID] { calls.map(\.inputID) }
        func pages() -> [Int?] { calls.map(\.page) }
        func overrides() -> [[PDFPageCompressionOverride]] { calls.map(\.overrides) }
    }

    private actor PagePolicyQueue {
        struct Call {
            let overrides: [PDFPageCompressionOverride]
            let page: Int?
        }
        let standard: PDFEditingRevision
        let individual: PDFEditingRevision
        var calls: [Call] = []

        init(standard: PDFEditingRevision, individual: PDFEditingRevision) {
            self.standard = standard
            self.individual = individual
        }

        func process(_ overrides: [PDFPageCompressionOverride], _ page: Int?) -> PDFEditingRevision {
            calls.append(Call(overrides: overrides, page: page))
            return overrides.isEmpty ? standard : individual
        }

        func recorded() -> [Call] { calls }
    }

    private actor PageSwitchQueue {
        let standard: PDFEditingRevision
        let individual: PDFEditingRevision
        var armed = false
        var baselineContinuation: CheckedContinuation<PDFEditingRevision, Never>?

        init(standard: PDFEditingRevision, individual: PDFEditingRevision) {
            self.standard = standard
            self.individual = individual
        }

        func arm() { armed = true }
        func isWaitingForBaseline() -> Bool { baselineContinuation != nil }
        func finishBaseline() {
            baselineContinuation?.resume(returning: standard)
            baselineContinuation = nil
        }

        func process(_ overrides: [PDFPageCompressionOverride], _ page: Int?) async -> PDFEditingRevision {
            if armed, overrides.isEmpty, page == nil {
                armed = false
                return await withCheckedContinuation { baselineContinuation = $0 }
            }
            return overrides.isEmpty ? standard : individual
        }
    }

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
        let model = try PDFCompressionSession(editing: editing) { input, options, overrides, _, page in
            try await queue.process(input, options, overrides, page)
        }
        try require(model.options.level == .balanced && model.options.colorMode == .color &&
                    model.options.contrast == 25 && model.options.paperCleanup == 50,
                    "A fresh compression session did not start with Color, Balanced, 25 percent contrast and 50 percent paper cleanup")
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

        let freshModel = try PDFCompressionSession(editing: editing) { input, _, _, _, _ in input }
        try require(freshModel.options.level == .balanced && freshModel.options.colorMode == .color &&
                    freshModel.options.contrast == 25 && freshModel.options.paperCleanup == 50,
                    "A fresh compression session remembered settings from an earlier session")
        freshModel.cancel()

        let pageQueue = PagePolicyQueue(standard: preview, individual: larger)
        let pageModel = try PDFCompressionSession(editing: editing) { _, _, overrides, _, page in
            await pageQueue.process(overrides, page)
        }
        pageModel.start()
        try await wait { pageModel.canAccept }
        pageModel.setCurrentPageUsesIndividualSettings(true)
        try await wait {
            pageModel.canAccept && pageModel.candidate?.id == larger.id &&
                pageModel.standardComparisonBytes == preview.byteCount
        }
        try require(pageModel.individualPageCount == 1 && pageModel.currentPageUsesIndividualSettings,
                    "Current-page settings were not retained")
        try require(pageModel.currentPageSizeImpact != nil,
                    "Exact whole-document size comparison was not published")
        let pageCalls = await pageQueue.recorded()
        try require(pageCalls.suffix(3).map(\.page) == [0, nil, nil] &&
                    pageCalls.suffix(3).map { $0.overrides.count } == [1, 1, 0],
                    "Page preview, full result and document-standard comparison used the wrong plans")
        var monochromePage = pageModel.currentPageOptions
        monochromePage.threshold = 50
        monochromePage.colorMode = .blackAndWhite
        pageModel.updateCurrentPageOptions(monochromePage)
        try require(pageModel.currentPageOptions.threshold == 75,
                    "An individual page did not start S/W at the 75 percent threshold")
        var colorPage = pageModel.currentPageOptions
        colorPage.contrast = 0
        colorPage.colorMode = .color
        pageModel.updateCurrentPageOptions(colorPage)
        try require(pageModel.currentPageOptions.contrast == 25,
                    "An individual page did not start color contrast at 75 percent of the slider")
        pageModel.resetAllPages()
        try await wait {
            pageModel.canAccept && pageModel.individualPageCount == 0 &&
                pageModel.candidate?.id == preview.id
        }
        try require(pageModel.standardComparisonBytes == nil,
                    "Resetting all pages retained an obsolete comparison")
        pageModel.cancel()

        let switchQueue = PageSwitchQueue(standard: preview, individual: larger)
        let switchingModel = try PDFCompressionSession(editing: editing) { _, _, overrides, _, page in
            await switchQueue.process(overrides, page)
        }
        switchingModel.start()
        try await wait { switchingModel.canAccept }
        await switchQueue.arm()
        switchingModel.setCurrentPageUsesIndividualSettings(true)
        try await wait { await switchQueue.isWaitingForBaseline() }
        switchingModel.currentPage = 1
        await switchQueue.finishBaseline()
        try await wait { !switchingModel.isProcessing && switchingModel.canAccept }
        try require(switchingModel.standardComparisonBytes == nil,
                    "A page change retained the previous page's size comparison")
        switchingModel.cancel()

        let second = try PDFCompressionSession(editing: editing) { _, _, _, _, _ in larger }
        second.start()
        try await wait { second.canAccept }
        try require(editing.accept(preview, basedOn: second.input.id), "Could not simulate an edit in another window")
        try await wait { second.errorMessage != nil }
        try require(!second.canAccept && second.candidate == nil, "A dialog based on an obsolete document remained adoptable")
        model.cancel(); second.cancel(); editing.cancel()
        print("PASS compression model: frozen input, stale responses, page overrides, exact standard comparison, page switching, reset, acceptance, undo and concurrent document edits")
    }
}
