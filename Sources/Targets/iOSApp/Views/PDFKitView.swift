import PDFKit
import SwiftUI

struct PDFKitView: UIViewRepresentable {
    let url: URL
    var password: String? = nil

    func makeUIView(context: Context) -> ResponsivePageFitPDFView {
        let view = ResponsivePageFitPDFView()
        view.autoScales = false
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.setDocument(document())
        return view
    }

    func updateUIView(_ uiView: ResponsivePageFitPDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.setDocument(document())
        }
    }

    private func document() -> PDFDocument? {
        let document = PDFDocument(url: url)
        if let password, document?.isLocked == true { document?.unlock(withPassword: password) }
        return document
    }
}
