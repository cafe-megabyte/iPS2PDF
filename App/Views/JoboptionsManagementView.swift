import SwiftUI
import UniformTypeIdentifiers

struct JoboptionsFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.joboptions] }
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct JoboptionsManagementView: View {
    @ObservedObject var viewModel: ConversionViewModel
    @State private var showsImporter = false
    @State private var exportDocument: JoboptionsFileDocument?
    @State private var exportName = "Joboptions"
    @State private var showsExporter = false
    @State private var showsSaveAs = false
    @State private var saveAsName = ""

    private var repository: JoboptionsRepository { viewModel.joboptionsRepository }

    var body: some View {
        List {
            Section("Active") {
                if let active = repository.activeRecord {
                    JoboptionsRecordLabel(record: active, isActive: true)
                }
            }

            recordsSection(title: "Bundled", records: repository.records.filter(\.isBundled))
            recordsSection(title: "User", records: repository.records.filter { !$0.isBundled })

            Section("Actions") {
                Button("Save As…", systemImage: "doc.badge.plus") {
                    saveAsName = repository.activeName
                    showsSaveAs = true
                }
                Button("Import…", systemImage: "square.and.arrow.down") {
                    showsImporter = true
                }
                Button("Export with Save Dialog…", systemImage: "square.and.arrow.up") {
                    prepareExport()
                }
                if let active = repository.activeRecord,
                   let url = try? repository.exportURL(for: active) {
                    ShareLink(item: url) {
                        Label("Export with Share Sheet…", systemImage: "square.and.arrow.up.on.square")
                    }
                }
            }
        }
        .navigationTitle("Manage Joboptions")
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.joboptions, .data],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                viewModel.importJoboptions(url)
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
        .alert("Save Joboptions As", isPresented: $showsSaveAs) {
            TextField("Name", text: $saveAsName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                do { _ = try repository.saveAs(name: saveAsName) }
                catch { repository.lastError = error.localizedDescription }
            }
        }
        .alert("Joboptions", isPresented: Binding(
            get: { repository.lastError != nil },
            set: { if !$0 { repository.lastError = nil } }
        )) {
            Button("OK") { repository.lastError = nil }
        } message: {
            Text(repository.lastError ?? "")
        }
    }

    private func recordsSection(title: String, records: [JoboptionsRecord]) -> some View {
        Section {
            if records.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            }
            ForEach(records) { record in
                Button {
                    do { try repository.activate(record) }
                    catch { repository.lastError = error.localizedDescription }
                } label: {
                    JoboptionsRecordLabel(
                        record: record,
                        isActive: repository.activeRecord?.id == record.id
                    )
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if !record.isBundled {
                        Button(role: .destructive) {
                            do { try repository.delete(record) }
                            catch { repository.lastError = error.localizedDescription }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    Button {
                        do { _ = try repository.duplicate(record) }
                        catch { repository.lastError = error.localizedDescription }
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    .tint(.blue)
                }
                .contextMenu {
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        do { _ = try repository.duplicate(record) }
                        catch { repository.lastError = error.localizedDescription }
                    }
                    if !record.isBundled {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            do { try repository.delete(record) }
                            catch { repository.lastError = error.localizedDescription }
                        }
                    }
                }
            }
        } header: {
            Text(LocalizedStringKey(title))
        }
    }

    private func prepareExport() {
        guard let data = repository.activeDocument?.data else { return }
        exportName = repository.activeName
        exportDocument = JoboptionsFileDocument(data: data)
        showsExporter = true
    }
}

private struct JoboptionsRecordLabel: View {
    let record: JoboptionsRecord
    let isActive: Bool

    var body: some View {
        HStack {
            if record.isBundled {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(record.name)
                    .foregroundStyle(.primary)
                if record.isBundled {
                    Text("Bundled · read-only")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("User · editable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
    }
}
