import Combine
import Foundation

@MainActor
final class PDFCompressionSession: ObservableObject, Identifiable {
    typealias Processor = @Sendable (
        PDFEditingRevision, PDFCompressionOptions, [PDFPageCompressionOverride], String?, Int?
    ) async throws -> PDFEditingRevision

    let id = UUID()
    let editing: PDFEditingSession
    let input: PDFEditingRevision
    private(set) var password: String?

    @Published var options = PDFCompressionOptions() {
        didSet { if options != oldValue { scheduleAfterViewUpdate() } }
    }
    @Published private(set) var pageOverrides: [Int: PDFCompressionOptions] = [:]
    @Published private(set) var candidate: PDFEditingRevision?
    @Published private(set) var pagePreview: PDFEditingRevision?
    @Published private(set) var previewPageIndex: Int?
    @Published private(set) var isProcessing = false
    @Published private(set) var isCalculatingPageDifference = false
    @Published private(set) var standardComparisonBytes: Int64?
    @Published private(set) var sharedResourcesFromEarlierPages = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var passwordRequired = false
    @Published private(set) var availableMonochromeLevels = Set(PDFCompressionOptions.Level.allCases)
    @Published private(set) var pageCount = 1
    @Published var currentPage = 0 {
        didSet {
            if currentPage != oldValue { schedulePageAnalysisAfterViewUpdate() }
        }
    }

    private var task: Task<Void, Never>?
    private var pageAnalysisTask: Task<Void, Never>?
    private var pendingViewMutation: Task<Void, Never>?
    private var pendingSchedule: Task<Void, Never>?
    private var pendingPageSchedule: Task<Void, Never>?
    private var generation = UUID()
    private var pageAnalysisGeneration = UUID()
    private var editingObservation: AnyCancellable?
    private var inspectionObservation: AnyCancellable?
    private let processor: Processor

    init(editing: PDFEditingSession, processor: @escaping Processor = { input, options, overrides, password, page in
        try await PDFProcessingClient().process(
            input, operation: .compress, preserveConformity: false, compression: options,
            pageCompressionOverrides: overrides, password: password, previewPage: page
        )
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
        inspectionObservation = editing.inspection?.$report.sink { [weak self] report in
            Task { @MainActor [weak self] in
                guard let self else { return }
                pageCount = max(1, report.pageCount)
                if currentPage >= pageCount { currentPage = pageCount - 1 }
                updateMonochromeLevels(from: report)
            }
        }
    }

    var canAccept: Bool {
        candidate != nil && !isProcessing && pendingViewMutation == nil &&
            pendingSchedule == nil && pendingPageSchedule == nil &&
            (!currentPageUsesIndividualSettings ||
                (!isCalculatingPageDifference && standardComparisonBytes != nil)) &&
            editing.current?.id == input.id
    }
    var currentPageUsesIndividualSettings: Bool { pageOverrides[currentPage] != nil }
    var currentPageOptions: PDFCompressionOptions { pageOverrides[currentPage] ?? options }
    var individualPageCount: Int { pageOverrides.count }
    var currentPageNumber: Int { min(currentPage + 1, pageCount) }
    var originalSize: String { formatted(input.byteCount) }
    var resultSize: String? { candidate.map { formatted($0.byteCount) } }
    var standardComparisonSize: String? { standardComparisonBytes.map(formatted) }
    var sizeDifference: String? {
        guard let candidate, input.byteCount > 0 else { return nil }
        let difference = 100 * (Double(candidate.byteCount) / Double(input.byteCount) - 1)
        return String.localizedStringWithFormat(String(localized: "%+.1f%% compared with the original"), difference)
    }
    var currentPageSizeImpact: String? {
        guard let candidate, let standardComparisonBytes else { return nil }
        let difference = candidate.byteCount - standardComparisonBytes
        guard difference != 0 else { return String(localized: "No file-size difference") }
        let size = formatted(abs(difference))
        return String.localizedStringWithFormat(
            String(localized: "%@%@ with individual page settings"),
            difference > 0 ? "+" : "−", size
        )
    }

    func isLevelEnabled(_ level: PDFCompressionOptions.Level, for settings: PDFCompressionOptions) -> Bool {
        settings.colorMode == .color || availableMonochromeLevels.contains(level)
    }

    func setCurrentPageUsesIndividualSettings(_ enabled: Bool) {
        if enabled {
            guard pageOverrides[currentPage] == nil else { return }
            pageOverrides[currentPage] = normalized(options)
        } else {
            guard pageOverrides.removeValue(forKey: currentPage) != nil else { return }
        }
        scheduleAfterViewUpdate(normalizeSettings: false)
    }

    func setCurrentPageUsesIndividualSettingsFromView(_ enabled: Bool) {
        pendingViewMutation?.cancel()
        pendingViewMutation = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            pendingViewMutation = nil
            setCurrentPageUsesIndividualSettings(enabled)
        }
    }

    func updateCurrentPageOptions(_ settings: PDFCompressionOptions) {
        let previous = currentPageOptions
        var value = settings
        if value.colorMode != previous.colorMode {
            switch value.colorMode {
            case .blackAndWhite:
                value.threshold = 75
            case .color:
                // Each color override starts at the shared color default.
                value.contrast = 25
            }
        }
        value = normalized(value)
        if value == options {
            guard pageOverrides.removeValue(forKey: currentPage) != nil else { return }
        } else {
            guard pageOverrides[currentPage] != value else { return }
            pageOverrides[currentPage] = value
        }
        scheduleAfterViewUpdate(normalizeSettings: false)
    }

    func updateCurrentPageOptionsFromView(_ settings: PDFCompressionOptions) {
        pendingViewMutation?.cancel()
        pendingViewMutation = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            pendingViewMutation = nil
            updateCurrentPageOptions(settings)
        }
    }

    func resetCurrentPage() {
        setCurrentPageUsesIndividualSettings(false)
    }

    func resetAllPages() {
        guard !pageOverrides.isEmpty else { return }
        pageOverrides.removeAll()
        scheduleAfterViewUpdate(normalizeSettings: false)
    }

    func start() {
        if task == nil && candidate == nil { schedule() }
    }

    func retry() { schedule() }

    func unlock(_ value: String) {
        password = value
        editing.inspection?.unlock(value)
        passwordRequired = false
        schedule()
    }

    func cancel() {
        pendingViewMutation?.cancel()
        pendingViewMutation = nil
        pendingSchedule?.cancel()
        pendingSchedule = nil
        pendingPageSchedule?.cancel()
        pendingPageSchedule = nil
        generation = UUID()
        pageAnalysisGeneration = UUID()
        task?.cancel()
        task = nil
        pageAnalysisTask?.cancel()
        pageAnalysisTask = nil
        isProcessing = false
        isCalculatingPageDifference = false
    }

    @discardableResult
    func accept() -> Bool {
        guard canAccept, let candidate else { return false }
        return editing.accept(candidate, basedOn: input.id)
    }

    private func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func wireOverrides(excluding page: Int? = nil) -> [PDFPageCompressionOverride] {
        pageOverrides
            .filter { $0.key != page }
            .sorted { $0.key < $1.key }
            .map { PDFPageCompressionOverride(pageIndex: $0.key, options: $0.value) }
    }

    private func normalized(_ value: PDFCompressionOptions) -> PDFCompressionOptions {
        guard value.colorMode == .blackAndWhite, !availableMonochromeLevels.contains(value.level) else { return value }
        var result = value
        result.level = PDFCompressionOptions.Level.allCases.reversed().first {
            availableMonochromeLevels.contains($0)
        } ?? .strong
        return result
    }

    private func scheduleAfterViewUpdate(normalizeSettings: Bool = true) {
        pendingSchedule?.cancel()
        pendingSchedule = Task { @MainActor [weak self] in
            // Pickers and sliders can mutate settings while SwiftUI is updating.
            // Publish dependent state on the next actor turn.
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            pendingSchedule = nil
            if normalizeSettings {
                let value = normalized(options)
                if value != options {
                    options = value
                    return
                }
                let redundant = pageOverrides.filter { $0.value == options }.map(\.key)
                if !redundant.isEmpty {
                    for page in redundant { pageOverrides.removeValue(forKey: page) }
                }
            }
            schedule()
        }
    }

    private func schedulePageAnalysisAfterViewUpdate() {
        pendingPageSchedule?.cancel()
        pendingPageSchedule = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            pendingPageSchedule = nil
            schedulePageAnalysis()
        }
    }

    private func updateMonochromeLevels(from report: PDFInspectionReport) {
        guard report.imagePlacementAnalysisComplete else {
            availableMonochromeLevels = Set(PDFCompressionOptions.Level.allCases)
            return
        }
        let ppi = report.imageMinimumPlacementPPI.values.sorted()
        let levels = PDFCompressionOptions.Level.allCases
        func signature(_ level: PDFCompressionOptions.Level) -> [Double] {
            let maximum = Double([600, 450, 300][level.rawValue])
            return ppi.map { value in value <= maximum * 1.25 ? 1 : maximum / value }
        }
        func equal(_ left: [Double], _ right: [Double]) -> Bool {
            left.count == right.count && zip(left, right).allSatisfy { abs($0 - $1) < 0.000_000_1 }
        }
        var available = Set<PDFCompressionOptions.Level>()
        for index in levels.indices {
            if index == levels.index(before: levels.endIndex) ||
                !equal(signature(levels[index]), signature(levels[levels.index(after: index)])) {
                available.insert(levels[index])
            }
        }
        availableMonochromeLevels = available
        let documentNeedsNormalization = normalized(options) != options
        let pagesNeedNormalization = pageOverrides.values.contains { normalized($0) != $0 }
        if documentNeedsNormalization || pagesNeedNormalization {
            if documentNeedsNormalization { options = normalized(options) }
            var updated = pageOverrides
            for (page, value) in updated { updated[page] = normalized(value) }
            updated = updated.filter { $0.value != options }
            pageOverrides = updated
            scheduleAfterViewUpdate(normalizeSettings: false)
        }
    }

    private func schedule() {
        cancel()
        candidate = nil
        pagePreview = nil
        previewPageIndex = nil
        standardComparisonBytes = nil
        sharedResourcesFromEarlierPages = 0
        errorMessage = nil
        isProcessing = true
        let token = generation
        let settings = options
        let overrides = wireOverrides()
        let page = currentPage
        let fullDeadline = ContinuousClock.now.advanced(by: .milliseconds(400))
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(70))
                let preview = try await processor(input, settings, overrides, password, page)
                guard generation == token, !Task.isCancelled else { return }
                if currentPage == page {
                    pagePreview = preview
                    previewPageIndex = page
                    sharedResourcesFromEarlierPages = preview.sharedResourcesFromEarlierPages
                }
                try await ContinuousClock().sleep(until: fullDeadline)
                let finished = try await processor(input, settings, overrides, password, nil)
                guard generation == token, !Task.isCancelled else { return }
                candidate = finished
                pagePreview = nil
                previewPageIndex = nil
                if pageOverrides[page] != nil, currentPage == page {
                    isCalculatingPageDifference = true
                    let standard = try await processor(input, settings, wireOverrides(excluding: page), password, nil)
                    guard generation == token, !Task.isCancelled else { return }
                    if currentPage == page { standardComparisonBytes = standard.byteCount }
                    isCalculatingPageDifference = false
                }
                guard generation == token, !Task.isCancelled else { return }
                isProcessing = false
                task = nil
                if currentPage != page { schedulePageAnalysis() }
            } catch {
                guard generation == token else { return }
                isProcessing = false
                isCalculatingPageDifference = false
                task = nil
                if let error = error as? PDFProcessingError, case .passwordRequired = error {
                    passwordRequired = true
                } else if !(error is CancellationError) {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func schedulePageAnalysis() {
        pageAnalysisGeneration = UUID()
        pageAnalysisTask?.cancel()
        pageAnalysisTask = nil
        guard candidate != nil, !isProcessing else { return }
        standardComparisonBytes = nil
        sharedResourcesFromEarlierPages = 0
        isCalculatingPageDifference = currentPageUsesIndividualSettings
        let token = pageAnalysisGeneration
        let page = currentPage
        let settings = options
        let overrides = wireOverrides()
        pageAnalysisTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(120))
                let preview = try await processor(input, settings, overrides, password, page)
                guard pageAnalysisGeneration == token, currentPage == page, !Task.isCancelled else { return }
                sharedResourcesFromEarlierPages = preview.sharedResourcesFromEarlierPages
                if pageOverrides[page] != nil {
                    let standard = try await processor(input, settings, wireOverrides(excluding: page), password, nil)
                    guard pageAnalysisGeneration == token, currentPage == page, !Task.isCancelled else { return }
                    standardComparisonBytes = standard.byteCount
                }
                isCalculatingPageDifference = false
                pageAnalysisTask = nil
            } catch {
                guard pageAnalysisGeneration == token else { return }
                isCalculatingPageDifference = false
                pageAnalysisTask = nil
                if !(error is CancellationError) { errorMessage = error.localizedDescription }
            }
        }
    }
}
