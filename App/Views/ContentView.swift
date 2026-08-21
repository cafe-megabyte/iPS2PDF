import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var viewModel: ConversionViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            viewModel.handleIncomingFiles([url])
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

private struct DiagnosticDetailsView: View {
    let presentation: DiagnosticPresentation
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                Text(presentation.text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(copied ? "Copied" : "Copy") {
                        UIPasteboard.general.string = presentation.text
                        copied = true
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct FrontConversionView: View {
    @ObservedObject var viewModel: ConversionViewModel
    let onShowSettings: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            HStack {
                Spacer()
                Button(action: onShowSettings) {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.controlsAreDisabled)
            }

            Spacer(minLength: 0)

            Button(String(localized: "open_file")) {
                viewModel.isFileImporterPresented = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.controlsAreDisabled)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Joboptions")
                        .font(.headline)

                    JoboptionsDropdown(
                        repository: viewModel.joboptionsRepository,
                        isDisabled: viewModel.controlsAreDisabled
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "pdf_version"))
                        .font(.headline)

                    PDFVersionDropdown(
                        selectedVersion: viewModel.selectedPDFVersion,
                        isDisabled: viewModel.controlsAreDisabled || viewModel.joboptionsRepository.activeStandard != .none
                    ) { version in
                        viewModel.setPDFVersion(version)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "pdfa_compatibility"))
                        .font(.headline)

                    PDFACompatibilityDropdown(
                        selectedCompatibility: viewModel.selectedPDFACompatibility,
                        isDisabled: viewModel.controlsAreDisabled
                    ) { compatibility in
                        viewModel.setPDFACompatibility(compatibility)
                    }
                }
            }
            .frame(maxWidth: 360, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)

            Spacer(minLength: 0)
        }
        .padding(32)
    }
}

private struct JoboptionsDropdown: View {
    @ObservedObject var repository: JoboptionsRepository
    let isDisabled: Bool

    var body: some View {
        Menu {
            Section("Bundled") {
                ForEach(repository.records.filter(\.isBundled)) { record in
                    recordButton(record)
                }
            }
            Section("User") {
                ForEach(repository.records.filter { !$0.isBundled }) { record in
                    recordButton(record)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: repository.activeRecord?.isBundled == true ? "shippingbox.fill" : "person.crop.circle")
                    .frame(width: 22)
                Text(repository.activeName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .disabled(isDisabled || !repository.isReady)
    }

    private func recordButton(_ record: JoboptionsRecord) -> some View {
        Button {
            do { try repository.activate(record) }
            catch { repository.lastError = error.localizedDescription }
        } label: {
            if repository.activeRecord?.id == record.id {
                Label(record.name, systemImage: "checkmark")
            } else {
                Text(record.name)
            }
        }
    }
}

private struct PDFVersionDropdown: View {
    let selectedVersion: PDFVersion
    let isDisabled: Bool
    let onSelect: (PDFVersion) -> Void

    var body: some View {
        Menu {
            ForEach(PDFVersion.allCases.reversed()) { version in
                Button {
                    onSelect(version)
                } label: {
                    menuItemTitle(for: version)
                    if let detail = version.detail {
                        Text(detail)
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                PDFVersionOptionRow(version: selectedVersion, showsSelection: false)

                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .disabled(isDisabled)
    }

    @ViewBuilder
    private func menuItemTitle(for version: PDFVersion) -> some View {
        if version.isHighlighted {
            Label(version.title, systemImage: "star.fill")
        } else {
            Text(version.title)
        }
    }
}

private struct PDFVersionOptionRow: View {
    let version: PDFVersion
    let showsSelection: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: version.isHighlighted ? "star.fill" : "star")
                .foregroundStyle(version.isHighlighted ? .red : .clear)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(version.title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)

                if let detail = version.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            }

            Spacer(minLength: 8)

            if showsSelection {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct PDFACompatibilityDropdown: View {
    let selectedCompatibility: PDFACompatibility
    let isDisabled: Bool
    let onSelect: (PDFACompatibility) -> Void

    var body: some View {
        Menu {
            ForEach(PDFACompatibility.allCases.reversed()) { compatibility in
                Button {
                    onSelect(compatibility)
                } label: {
                    menuItemTitle(for: compatibility)
                    if let detail = compatibility.detail {
                        Text(detail)
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                PDFACompatibilityOptionRow(compatibility: selectedCompatibility)

                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .disabled(isDisabled)
    }

    @ViewBuilder
    private func menuItemTitle(for compatibility: PDFACompatibility) -> some View {
        if compatibility.isHighlighted {
            Label(compatibility.title, systemImage: "star.fill")
        } else {
            Text(compatibility.title)
        }
    }
}

private struct PDFACompatibilityOptionRow: View {
    let compatibility: PDFACompatibility

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: compatibility.isHighlighted ? "star.fill" : "star")
                .foregroundStyle(compatibility.isHighlighted ? .red : .clear)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(compatibility.title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)

                if let detail = compatibility.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            }

            Spacer(minLength: 8)
        }
        .contentShape(Rectangle())
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
