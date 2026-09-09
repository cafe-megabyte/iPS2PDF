import Combine
import Foundation
import PDFKit

@MainActor
final class PDFSignatureEditingSession: ObservableObject, Identifiable {
    let id = UUID()
    let editing: PDFEditingSession
    let input: PDFEditingRevision
    let font: PDFSignatureFont
    let pageBounds: [CGRect]

    @Published private(set) var placements: [PDFSignaturePlacement] = []
    @Published var selectedID: UUID?
    @Published private(set) var isProcessing = false
    @Published private(set) var didFinish = false
    @Published var errorMessage: String?
    @Published var notice: String?

    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var finishesAfterNotice = false

    init(editing: PDFEditingSession) throws {
        guard let input = editing.current else { throw PDFProcessingError.failed }
        let font = try PDFSignatureFont()
        guard let document = PDFDocument(url: input.input.url) else { throw PDFProcessingError.failed }
        if let password = editing.passwordForProcessing, document.isLocked { document.unlock(withPassword: password) }
        guard !document.isLocked, document.pageCount > 0 else { throw PDFProcessingError.passwordRequired }
        self.editing = editing
        self.input = input
        self.font = font
        pageBounds = (0..<document.pageCount).compactMap { document.page(at: $0)?.bounds(for: .cropBox) }
        guard pageBounds.count == document.pageCount else { throw PDFProcessingError.failed }
    }

    var canApply: Bool { !placements.isEmpty && !isProcessing }
    var selectedPlacement: PDFSignaturePlacement? { placements.first { $0.id == selectedID } }
    var selectedFontSize: Double { selectedPlacement?.fontSize ?? PDFSignaturePlacement.defaultFontSize }

    @discardableResult
    func add(pageIndex: Int, centeredAt point: CGPoint) -> UUID? {
        guard placements.count < 10_000, pageBounds.indices.contains(pageIndex) else { return nil }
        let size = PDFSignaturePlacement.defaultFontSize
        let relative = font.relativeGlyphBounds(size: size)
        var placement = PDFSignaturePlacement(pageIndex: pageIndex,
                                              x: point.x - relative.midX,
                                              y: point.y - relative.midY,
                                              fontSize: size)
        placement = clamped(placement)
        placements.append(placement)
        selectedID = placement.id
        return placement.id
    }

    func select(_ id: UUID?) { selectedID = id }

    func move(_ id: UUID, baseline: CGPoint) {
        guard let index = placements.firstIndex(where: { $0.id == id }) else { return }
        var placement = placements[index]
        placement.x = baseline.x
        placement.y = baseline.y
        placements[index] = clamped(placement)
    }

    func resizeSelected(to size: Double) {
        guard let id = selectedID, let index = placements.firstIndex(where: { $0.id == id }) else { return }
        let old = placements[index]
        let oldBounds = glyphBounds(for: old)
        var resized = old
        resized.fontSize = min(max(size, PDFSignaturePlacement.minimumFontSize), PDFSignaturePlacement.maximumFontSize)
        let relative = font.relativeGlyphBounds(size: resized.fontSize)
        resized.x = oldBounds.midX - relative.midX
        resized.y = oldBounds.midY - relative.midY
        placements[index] = clamped(resized)
    }

    func removeSelected() {
        guard let selectedID else { return }
        placements.removeAll { $0.id == selectedID }
        self.selectedID = nil
    }

    func placement(id: UUID) -> PDFSignaturePlacement? { placements.first { $0.id == id } }

    func glyphBounds(for placement: PDFSignaturePlacement) -> CGRect {
        font.relativeGlyphBounds(size: placement.fontSize)
            .offsetBy(dx: placement.x, dy: placement.y)
    }

    func apply() {
        guard canApply else { return }
        isProcessing = true
        errorMessage = nil
        notice = nil
        generation = UUID()
        let token = generation
        let placements = placements
        let password = editing.passwordForProcessing
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let candidate = try await PDFProcessingClient().process(
                    self.input, operation: .addSignatures, preserveConformity: false,
                    signaturePlacements: placements, password: password
                )
                guard self.generation == token, !Task.isCancelled else { return }
                guard self.editing.accept(candidate, basedOn: self.input.id) else {
                    throw PDFProcessingError.failed
                }
                self.isProcessing = false
                self.task = nil
                if candidate.warnings.isEmpty {
                    self.didFinish = true
                } else {
                    self.finishesAfterNotice = true
                    self.notice = candidate.warnings.map(\.message).joined(separator: "\n\n")
                }
            } catch {
                guard self.generation == token else { return }
                self.isProcessing = false
                self.task = nil
                if !(error is CancellationError) { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func acknowledgeNotice() {
        notice = nil
        if finishesAfterNotice {
            finishesAfterNotice = false
            didFinish = true
        }
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        isProcessing = false
    }

    private func clamped(_ placement: PDFSignaturePlacement) -> PDFSignaturePlacement {
        guard pageBounds.indices.contains(placement.pageIndex) else { return placement }
        var result = placement
        let page = pageBounds[placement.pageIndex]
        let relative = font.relativeGlyphBounds(size: placement.fontSize)
        let horizontal = min(max(placement.x, page.minX - relative.minX), page.maxX - relative.maxX)
        let vertical = min(max(placement.y, page.minY - relative.minY), page.maxY - relative.maxY)
        result.x = horizontal
        result.y = vertical
        return result
    }
}
