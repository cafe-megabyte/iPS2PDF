import PDFKit

final class InitialScalePDFView: PDFView {
    private(set) var loadedDocumentURL: URL?
    private var needsInitialScale = false
    private var scaleUpdateIsScheduled = false

    func loadDocument(at url: URL) {
        document = PDFDocument(url: url)
        loadedDocumentURL = url
        needsInitialScale = true
        scheduleInitialScaleUpdate()
    }

    override func layout() {
        super.layout()
        scheduleInitialScaleUpdate()
    }

    private func scheduleInitialScaleUpdate() {
        guard needsInitialScale, !scaleUpdateIsScheduled else { return }

        scaleUpdateIsScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.applyInitialScaleIfPossible()
        }
    }

    private func applyInitialScaleIfPossible() {
        scaleUpdateIsScheduled = false
        guard needsInitialScale, document != nil else { return }
        guard bounds.width > 0, bounds.height > 0 else {
            scheduleInitialScaleUpdate()
            return
        }

        autoScales = true
        layoutDocumentView()
        let fittedScale = scaleFactorForSizeToFit
        guard fittedScale.isFinite, fittedScale > 0 else { return }

        autoScales = false
        scaleFactor = min(fittedScale, 1.0)
        needsInitialScale = false
    }
}
