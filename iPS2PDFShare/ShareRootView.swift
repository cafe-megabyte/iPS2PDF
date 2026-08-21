import SwiftUI

struct ShareRootView: View {
    @ObservedObject var model: ShareConversionModel

    var body: some View {
        Group {
            switch model.phase {
            case .preparing:
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Preparing PostScript…")
                        .multilineTextAlignment(.center)
                }
                .padding()
            case let .viewer(url):
                PDFViewer(
                    url: url,
                    onClose: model.finish,
                    onShareStarted: {},
                    onShareFinished: {}
                )
            case let .failed(message):
                ContentUnavailableView {
                    Label("Conversion failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Close", action: model.finish)
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .tint(AppTint.color)
    }
}
