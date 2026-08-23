import PDFKit
import SwiftUI

struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> ResponsivePageFitPDFView {
        let view = ResponsivePageFitPDFView()
        view.autoScales = false
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.setDocument(PDFDocument(url: url))
        return view
    }

    func updateUIView(_ uiView: ResponsivePageFitPDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.setDocument(PDFDocument(url: url))
        }
    }
}
