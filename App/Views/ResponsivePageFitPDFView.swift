import PDFKit
import UIKit

final class ResponsivePageFitPDFView: PDFView {
    private var fittedScaleFactor: CGFloat?
    private var lastAvailableSize = CGSize.zero

    func setDocument(_ document: PDFDocument?) {
        fittedScaleFactor = nil
        lastAvailableSize = .zero
        self.document = document
        setNeedsLayout()
    }

    override func layoutSubviews() {
        let wasAtFittedScale = fittedScaleFactor.map {
            abs(scaleFactor - $0) < 0.001
        } ?? true

        super.layoutSubviews()

        guard let firstPage = document?.page(at: 0) else {
            return
        }

        let safeBounds = bounds.inset(by: safeAreaInsets)
        let availableSize = CGSize(
            width: safeBounds.width - pageBreakMargins.left - pageBreakMargins.right,
            height: safeBounds.height - pageBreakMargins.top - pageBreakMargins.bottom
        )

        guard availableSize.width > 0,
              availableSize.height > 0,
              availableSize != lastAvailableSize
        else {
            return
        }

        lastAvailableSize = availableSize
        guard wasAtFittedScale else { return }

        var pageSize = firstPage.bounds(for: displayBox).size
        if abs(firstPage.rotation) % 180 != 0 {
            pageSize = CGSize(width: pageSize.height, height: pageSize.width)
        }

        guard pageSize.width > 0, pageSize.height > 0 else { return }

        let fittedScaleFactor = min(
            availableSize.width / pageSize.width,
            availableSize.height / pageSize.height
        )
        guard fittedScaleFactor > 0 else { return }

        self.fittedScaleFactor = fittedScaleFactor
        scaleFactor = fittedScaleFactor
        self.fittedScaleFactor = scaleFactor
    }
}
