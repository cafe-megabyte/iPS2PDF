import Foundation
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
                    .frame(maxWidth: .infinity)
                    .disabled(viewModel.controlsAreDisabled)
                }
                .frame(width: 280, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(32)

            if viewModel.showsProgressOverlay {
                ProcessingOverlay()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
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
        .onDrop(of: [.item], isTargeted: nil) { providers in
            receiveDroppedItems(providers)
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

    private func receiveDroppedItems(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty, !viewModel.controlsAreDisabled else {
            return false
        }

        guard providers.count == 1, let provider = providers.first else {
            viewModel.handleIncomingFiles([])
            return true
        }

        let typeIdentifier = provider.registeredTypeIdentifiers.first { identifier in
            UTType(identifier)?.conforms(to: .data) == true
        } ?? provider.registeredTypeIdentifiers.first

        guard let typeIdentifier else { return false }

        let suggestedName = provider.suggestedName
        let viewModel = viewModel
        _ = provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { temporaryURL, _ in
            guard let temporaryURL else {
                Task { @MainActor in
                    viewModel.handleDroppedFileLoadFailure()
                }
                return
            }

            let stagedURL: URL
            do {
                stagedURL = try DroppedFileStaging.stage(
                    temporaryURL,
                    suggestedName: suggestedName
                )
            } catch {
                Task { @MainActor in
                    viewModel.handleDroppedFileLoadFailure()
                }
                return
            }

            Task { @MainActor in
                viewModel.handleDroppedFile(stagedURL)
            }
        }
        return true
    }
}

private enum DroppedFileStaging {
    static let directoryName = "Incoming drops"

    static func stage(_ temporaryURL: URL, suggestedName: String?) throws -> URL {
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let proposedName = suggestedName.flatMap { $0.isEmpty ? nil : $0 }
            ?? temporaryURL.lastPathComponent
        let fileName = URL(fileURLWithPath: proposedName).lastPathComponent
        let stagedURL = directoryURL.appendingPathComponent(fileName)
        do {
            try fileManager.copyItem(at: temporaryURL, to: stagedURL)
            return stagedURL
        } catch {
            try? fileManager.removeItem(at: directoryURL)
            throw error
        }
    }
}
