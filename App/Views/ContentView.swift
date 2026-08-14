import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var viewModel: ConversionViewModel

    var body: some View {
        ZStack {
            VStack(spacing: 32) {
                Button(String(localized: "open_file")) {
                    viewModel.isFileImporterPresented = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.controlsAreDisabled)

                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "pdf_version"))
                        .font(.headline)

                    Picker(String(localized: "pdf_version"), selection: pdfVersionBinding) {
                        ForEach(PDFVersion.allCases) { version in
                            Text(version.rawValue).tag(version)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(viewModel.controlsAreDisabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(32)

            if viewModel.showsProgressOverlay {
                ProcessingOverlay()
            }
        }
        .fileImporter(
            isPresented: $viewModel.isFileImporterPresented,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first {
                    viewModel.handleSelectedFile(url)
                }
            case .failure:
                break
            }
        }
        .onOpenURL { url in
            viewModel.handleIncomingFiles([url])
        }
        .fullScreenCover(item: $viewModel.presentedPDF, onDismiss: viewModel.pdfViewerDidDismiss) { presentation in
            PDFViewer(
                url: presentation.url,
                onClose: viewModel.closePDFViewer,
                onShareStarted: viewModel.beginSharing,
                onShareFinished: viewModel.endSharing
            )
        }
        .alert(item: $viewModel.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(String(localized: "dismiss"))) {
                    viewModel.dismissAlert()
                }
            )
        }
    }

    private var pdfVersionBinding: Binding<PDFVersion> {
        Binding(
            get: { viewModel.selectedPDFVersion },
            set: { viewModel.setPDFVersion($0) }
        )
    }
}
