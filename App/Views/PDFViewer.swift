import PDFKit
import SwiftUI

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
