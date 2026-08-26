import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var viewModel: ConversionViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsBack = false

    var body: some View {
        ZStack {
            FrontConversionView(
                viewModel: viewModel,
                onShowSettings: { setBackVisible(true) }
            )
            .opacity(showsBack ? 0 : 1)
            .rotation3DEffect(
                .degrees(reduceMotion ? 0 : (showsBack ? -180 : 0)),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.65
            )
            .allowsHitTesting(!showsBack)
            .accessibilityHidden(showsBack)

            AdvancedSettingsView(
                viewModel: viewModel,
                onShowFront: { setBackVisible(false) }
            )
            .opacity(showsBack ? 1 : 0)
            .rotation3DEffect(
                .degrees(reduceMotion ? 0 : (showsBack ? 0 : 180)),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.65
            )
            .allowsHitTesting(showsBack)
            .accessibilityHidden(!showsBack)

            if viewModel.showsProgressOverlay {
                ProcessingOverlay()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .fileImporter(
            isPresented: $viewModel.isFileImporterPresented,
            allowedContentTypes: [.data, .joboptions],
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
            viewModel.handleOpenURL(url)
        }
        .task {
            viewModel.handlePendingShareDocumentIfAvailable()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            viewModel.handlePendingShareDocumentIfAvailable()
        }
        .onChange(of: viewModel.settingsPresentationToken) { _, _ in
            setBackVisible(true)
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
        .sheet(item: $viewModel.diagnosticDetails, onDismiss: viewModel.diagnosticDetailsDidDismiss) { presentation in
            DiagnosticDetailsView(presentation: presentation)
        }
        .alert(item: $viewModel.alert) { alert in
            if alert.details != nil {
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    primaryButton: .default(Text("Details")) {
                        viewModel.showDetails(for: alert)
                    },
                    secondaryButton: .cancel(Text(String(localized: "dismiss"))) {
                        viewModel.dismissAlert()
                    }
                )
            } else {
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text(String(localized: "dismiss"))) {
                        viewModel.dismissAlert()
                    }
                )
            }
        }
    }

    private func setBackVisible(_ visible: Bool) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.62)) {
            showsBack = visible
        }
    }

    private func receiveDroppedItems(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty, !viewModel.controlsAreDisabled else {
            return false
        }

        guard providers.count == 1, let provider = providers.first else {
            viewModel.handleIncomingFiles([])
            return true
        }

        let preferredTypeIdentifiers = [
            UTType.joboptions.identifier,
            "com.adobe.encapsulated-postscript",
            "com.adobe.postscript"
        ]
        let typeIdentifier = preferredTypeIdentifiers.first { identifier in
            provider.hasItemConformingToTypeIdentifier(identifier)
        } ?? provider.registeredTypeIdentifiers.first { identifier in
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
