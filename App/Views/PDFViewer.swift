import PDFKit
import SwiftUI
import UIKit

struct PDFViewer: View {
    let url: URL
    let onClose: () -> Void
    let onShareStarted: () -> Void
    let onShareFinished: () -> Void

    @State private var isShowingShareSheet = false

    var body: some View {
        NavigationStack {
            PDFKitView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(url.lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            onShareStarted()
                            isShowingShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(String(localized: "share"))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            onClose()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(String(localized: "close"))
                    }
                }
        }
        .sheet(isPresented: $isShowingShareSheet, onDismiss: onShareFinished) {
            ActivityView(activityItems: [url]) {
                isShowingShareSheet = false
            }
        }
    }
}

private struct PDFKitView: UIViewRepresentable {
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

private final class ResponsivePageFitPDFView: PDFView {
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

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let completion: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            completion()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
