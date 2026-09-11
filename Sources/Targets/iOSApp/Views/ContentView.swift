import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var viewModel: ConversionViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsBack = false
    @State private var fileImportPurpose: FileImportPurpose?
    @State private var showsGhostscriptSettings = false

    var body: some View {
        ZStack {
            FrontConversionView(
                viewModel: viewModel,
                onShowSettings: { setBackVisible(true) },
                onShowPDFInfo: { presentFileImporter(for: .pdfInformation) },
                onOpenFile: { presentFileImporter(for: .pdfConversion) },
                onOpenPostScriptFile: { presentFileImporter(for: .postScriptConversion) },
                onShowGhostscriptSettings: { showsGhostscriptSettings = true }
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
            allowedContentTypes: fileImportPurpose?.allowedContentTypes ?? [.item],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .sheet(
            isPresented: $viewModel.isPostScriptFileExporterPresented,
            onDismiss: cancelPostScriptExportIfNeeded
        ) {
            if let artifact = viewModel.postScriptExportArtifact {
                PostScriptDocumentExporter(
                    sourceURL: artifact.url,
                    onCompletion: viewModel.postScriptFileExporterDidFinish
                )
            }
        }
        .sheet(isPresented: $showsGhostscriptSettings) {
            GhostscriptSettingsView(settings: viewModel.runtimeSettings)
        }
        .sheet(item: $viewModel.presentedPDFInfo, onDismiss: viewModel.pdfInfoDidDismiss) { session in
            PDFInfoView(session: session, runtimeSettings: viewModel.runtimeSettings)
        }
        .modifier(PDFPasswordPresenter(controller: viewModel.passwordController))
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
                runtimeSettings: viewModel.runtimeSettings,
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

    private func presentFileImporter(for purpose: FileImportPurpose) {
        guard !viewModel.controlsAreDisabled else { return }
        fileImportPurpose = purpose
        viewModel.isFileImporterPresented = true
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        let purpose = fileImportPurpose
        fileImportPurpose = nil
        viewModel.isFileImporterPresented = false
        guard case let .success(urls) = result, let url = urls.first else { return }

        switch purpose {
        case .pdfInformation:
            viewModel.presentedPDFInfo = PDFInspectionSession(url: url)
        case .pdfConversion:
            viewModel.handleSelectedFile(url)
        case .postScriptConversion:
            viewModel.handleSelectedPostScriptFile(url)
        case nil:
            break
        }
    }

    private func cancelPostScriptExportIfNeeded() {
        guard viewModel.postScriptExportArtifact != nil else { return }
        viewModel.postScriptFileExporterDidFinish(.failure(CocoaError(.userCancelled)))
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

    private enum FileImportPurpose {
        case pdfInformation
        case pdfConversion
        case postScriptConversion

        var allowedContentTypes: [UTType] {
            switch self {
            case .pdfInformation:
                return [.pdf]
            case .pdfConversion:
                return [.data, .joboptions]
            case .postScriptConversion:
                return [.item]
            }
        }
    }
}
