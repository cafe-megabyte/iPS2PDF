import SwiftUI
import UniformTypeIdentifiers

struct MacOSJoboptionsManagementView: View {
    @ObservedObject var repository: JoboptionsRepository
    @Environment(\.dismiss) private var dismiss
    @State private var showsImporter = false
    @State private var exportDocument: JoboptionsFileDocument?
    @State private var exportName = String(localized: "Joboptions")
    @State private var showsExporter = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Manage Joboptions"))
                    .font(.title2.bold())
                Spacer()
                Button(String(localized: "Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            List {
                recordsSection(title: String(localized: "Bundled"), records: repository.records.filter(\.isBundled))
                recordsSection(title: String(localized: "User"), records: repository.records.filter { !$0.isBundled })
            }

            HStack {
                Button(String(localized: "Import...")) { showsImporter = true }
                Button(String(localized: "Export...")) { prepareExport() }
                Button(String(localized: "Duplicate")) {
                    guard let record = repository.activeRecord else { return }
                    do { _ = try repository.duplicate(record) }
                    catch { repository.lastError = error.localizedDescription }
                }
                Spacer()
            }
            .padding()
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.joboptions, .data],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                importJoboptions(url)
            } catch {
                repository.lastError = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $showsExporter,
            document: exportDocument,
            contentType: .joboptions,
            defaultFilename: exportName
        ) { result in
            if case let .failure(error) = result {
                repository.lastError = error.localizedDescription
            }
            exportDocument = nil
        }
    }

    private func recordsSection(title: String, records: [JoboptionsRecord]) -> some View {
        Section(title) {
            ForEach(records) { record in
                HStack {
                    Button {
                        do { try repository.activate(record) }
                        catch { repository.lastError = error.localizedDescription }
                    } label: {
                        HStack {
                            Text(record.name)
                            Spacer()
                            if repository.activeRecord?.id == record.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    if !record.isBundled {
                        Button(role: .destructive) {
                            do { try repository.delete(record) }
                            catch { repository.lastError = error.localizedDescription }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private func importJoboptions(_ sourceURL: URL) {
        Task { @MainActor in
            let workspace = MacOSDocumentWorkspace()
            do {
                let stagedURL = try await workspace.stageInput(from: sourceURL)
                try await MacOSApplicationModel.shared.conversionCoordinator.validate(
                    joboptionsURL: stagedURL
                )
                _ = try repository.importJoboptions(from: stagedURL)
                try? await workspace.clear()
            } catch {
                try? await workspace.clear()
                repository.lastError = error.localizedDescription
            }
        }
    }

    private func prepareExport() {
        guard let data = repository.activeDocument?.data else { return }
        exportName = repository.activeName
        exportDocument = JoboptionsFileDocument(data: data)
        showsExporter = true
    }
}
