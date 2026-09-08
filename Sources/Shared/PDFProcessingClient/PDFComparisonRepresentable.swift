import SwiftUI
@preconcurrency import PDFKit

@MainActor
struct PDFComparisonRepresentable {
    #if os(macOS)
    final class InteractivePDFView: PDFView {
        var usesPaperCursor = false {
            didSet {
                if usesPaperCursor != oldValue { window?.invalidateCursorRects(for: self) }
            }
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            if usesPaperCursor { addCursorRect(bounds, cursor: .crosshair) }
        }
    }
    #endif

    let revision: PDFEditingRevision
    let password: String?
    let pageOffset: Int?
    let synchronization: PDFComparisonSynchronization
    let paperSample: PDFPaperSample?
    let isChoosingPaperArea: Bool
    let pageChanged: (Int) -> Void
    let paperSampled: (PDFPaperSample) -> Void
    @MainActor final class Coordinator {
        var revisionID: UUID?
        var pageOffset: Int?
        var paperSample: PDFPaperSample?
        var isChoosingPaperArea = false
        var paperSampled: ((PDFPaperSample) -> Void)?
        weak var markerPage: PDFPage?
        var marker: PDFAnnotation?
        #if os(macOS)
        var paperGesture: NSClickGestureRecognizer?
        #else
        var paperGesture: UITapGestureRecognizer?
        #endif
        let synchronization: PDFComparisonSynchronization
        init(_ synchronization: PDFComparisonSynchronization) { self.synchronization = synchronization }
        func configurePaperInteraction(in view: PDFView, sample: PDFPaperSample?,
                                       choosing: Bool,
                                       sampled: @escaping (PDFPaperSample) -> Void) {
            let selectionChanged = paperSample != sample || isChoosingPaperArea != choosing
            paperSample = sample
            isChoosingPaperArea = choosing
            paperSampled = sampled
            if paperGesture == nil {
                #if os(macOS)
                let gesture = NSClickGestureRecognizer(target: self, action: #selector(selectPaperArea(_:)))
                #else
                let gesture = UITapGestureRecognizer(target: self, action: #selector(selectPaperArea(_:)))
                gesture.cancelsTouchesInView = true
                #endif
                view.addGestureRecognizer(gesture)
                paperGesture = gesture
            }
            paperGesture?.isEnabled = choosing
            #if os(macOS)
            (view as? InteractivePDFView)?.usesPaperCursor = choosing
            #endif
            if selectionChanged || (!choosing && sample != nil && marker == nil) {
                updateMarker(in: view)
            }
        }

        func removeMarker() {
            if let marker { markerPage?.removeAnnotation(marker) }
            marker = nil
            markerPage = nil
        }

        private func updateMarker(in view: PDFView) {
            removeMarker()
            guard !isChoosingPaperArea, let paperSample,
                  let document = view.document,
                  let page = document.page(at: paperSample.pageIndex) else { return }
            let pageBounds = page.bounds(for: .cropBox)
            let point = CGPoint(
                x: pageBounds.minX + CGFloat(paperSample.normalizedX) * pageBounds.width,
                y: pageBounds.minY + CGFloat(paperSample.normalizedY) * pageBounds.height
            )
            let diameter = max(10, min(pageBounds.width, pageBounds.height) * 0.018)
            let annotation = PDFAnnotation(
                bounds: CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2,
                               width: diameter, height: diameter),
                forType: .circle, withProperties: nil
            )
            annotation.color = .systemRed
            let border = PDFBorder()
            border.lineWidth = 2
            annotation.border = border
            annotation.shouldPrint = false
            page.addAnnotation(annotation)
            marker = annotation
            markerPage = page
        }

        #if os(macOS)
        @objc private func selectPaperArea(_ gesture: NSClickGestureRecognizer) {
            guard gesture.state == .ended, let view = gesture.view as? PDFView else { return }
            capturePaperArea(in: view, location: gesture.location(in: view))
        }
        #else
        @objc private func selectPaperArea(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let view = gesture.view as? PDFView else { return }
            capturePaperArea(in: view, location: gesture.location(in: view))
        }
        #endif

        private func capturePaperArea(in view: PDFView, location: CGPoint) {
            guard isChoosingPaperArea, let document = view.document,
                  let page = view.page(for: location, nearest: false) else { return }
            let pageIndex = document.index(for: page)
            guard pageIndex != NSNotFound else { return }
            let pagePoint = view.convert(location, to: page)
            let bounds = page.bounds(for: .cropBox)
            guard bounds.width > 0, bounds.height > 0 else { return }
            let normalized = CGPoint(
                x: (pagePoint.x - bounds.minX) / bounds.width,
                y: (pagePoint.y - bounds.minY) / bounds.height
            )
            let diameter: CGFloat = 52
            let sampleRect = CGRect(x: location.x - diameter / 2,
                                    y: location.y - diameter / 2,
                                    width: diameter, height: diameter)
                .intersection(view.bounds)
            guard sampleRect.width >= 8, sampleRect.height >= 8,
                  let image = capture(view, rectangle: sampleRect),
                  let sample = PDFPaperSampleAnalyzer.analyze(
                    image, pageIndex: pageIndex, normalizedPoint: normalized
                  ) else { return }
            paperSampled?(sample)
        }

        private func capture(_ view: PDFView, rectangle: CGRect) -> CGImage? {
            #if os(macOS)
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: rectangle) else { return nil }
            view.cacheDisplay(in: rectangle, to: bitmap)
            return bitmap.cgImage
            #else
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = view.window?.windowScene?.screen.scale ??
                max(1, view.traitCollection.displayScale)
            let renderer = UIGraphicsImageRenderer(size: rectangle.size, format: format)
            return renderer.image { context in
                context.cgContext.translateBy(x: -rectangle.minX, y: -rectangle.minY)
                view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
            }.cgImage
            #endif
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(synchronization) }
    func makeView() -> PDFView {
        #if os(macOS)
        let view = InteractivePDFView()
        #else
        let view = PDFView()
        #endif
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        return view
    }
    func update(_ view: PDFView, coordinator: Coordinator) {
        let replacesDocument = coordinator.revisionID != revision.id
        let replacesOffset = coordinator.pageOffset != pageOffset
        if replacesDocument || replacesOffset {
            coordinator.removeMarker()
            synchronization.unregister(view)
        }
        if replacesDocument {
            let document = PDFDocument(url: revision.input.url)
            if let password, document?.isLocked == true { document?.unlock(withPassword: password) }
            view.document = document
            view.autoScales = true
            #if os(macOS)
            view.layoutSubtreeIfNeeded()
            #else
            view.layoutIfNeeded()
            #endif
        }
        coordinator.revisionID = revision.id
        coordinator.pageOffset = pageOffset
        if replacesDocument || replacesOffset {
            synchronization.register(view, pageOffset: pageOffset, pageChanged: pageChanged)
        }
        coordinator.configurePaperInteraction(
            in: view, sample: paperSample, choosing: isChoosingPaperArea,
            sampled: paperSampled
        )
    }
}

#if os(macOS)
extension PDFComparisonRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> PDFView { makeView() }
    func updateNSView(_ view: PDFView, context: Context) { update(view, coordinator: context.coordinator) }
    static func dismantleNSView(_ view: PDFView, coordinator: Coordinator) {
        coordinator.removeMarker()
        coordinator.synchronization.unregister(view)
    }
}
#else
extension PDFComparisonRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> PDFView { makeView() }
    func updateUIView(_ view: PDFView, context: Context) { update(view, coordinator: context.coordinator) }
    static func dismantleUIView(_ view: PDFView, coordinator: Coordinator) {
        coordinator.removeMarker()
        coordinator.synchronization.unregister(view)
    }
}
#endif
