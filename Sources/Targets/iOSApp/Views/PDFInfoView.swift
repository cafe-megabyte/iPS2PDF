import SwiftUI
import UniformTypeIdentifiers

struct PDFInfoView: View {
    @ObservedObject var session: PDFInspectionSession
    @StateObject private var actions: PDFEditingActions
    private let ownsInspection: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var category = PDFInfoCategory.overview
    @State private var fontReveal = 0
    @State private var noticeReveal = 0
    @State private var password = ""
    @State private var exportURL: URL?
    @State private var showsExport = false
    @State private var message: String?
    @State private var copied = false
    @State private var asksConformity = false
    @State private var sharedRevision: PDFEditingRevision?
    @State private var compression: PDFCompressionSession?
    @State private var resourceArtifact: PDFExportArtifact?
    @State private var resourceExportTask: Task<Void, Never>?
    @State private var selectsResourceFolder = false
    @State private var resourceProgress: PDFResourceExporter.Progress?

    private var isExportingResources: Bool { resourceExportTask != nil }

    init(session: PDFInspectionSession, editing: PDFEditingSession? = nil) {
        self.session = session
        ownsInspection = editing == nil
        _actions = StateObject(wrappedValue: PDFEditingActions(inspection: session, editing: editing))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if actions.isProcessing {
                    HStack {
                        ProgressView()
                        Text("Removing metadata…")
                        Spacer()
                        Button("Cancel") { actions.cancel() }
                    }.padding()
                }
                if let progress = resourceProgress {
                    HStack {
                        ProgressView()
                        Text(progress.completed == progress.total
                             ? String(localized: "Finishing resource export…")
                             : String.localizedStringWithFormat(String(localized: "Exporting resource %lld of %lld: %@"), Int64(progress.completed + 1), Int64(progress.total), progress.filename))
                            .font(.footnote)
                        Spacer()
                        Button("Cancel") { resourceExportTask?.cancel() }
                    }.padding()
                }
                if let summary = session.report.warningSummary {
                    Button { category = .fonts; fontReveal += 1 } label: {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(summary).font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .foregroundStyle(.primary)
                        .padding(12)
                        .background(Color.orange.opacity(0.20))
                    }
                    .accessibilityHint("Show fonts that are not embedded")
                }
                if session.isReading {
                    HStack {
                        ProgressView()
                        Text(session.report.pageCount > 0 ? String.localizedStringWithFormat(String(localized: "Reading page %lld of %lld"), Int64(session.report.pagesRead), Int64(session.report.pageCount)) : String(localized: "Reading PDF information…"))
                            .font(.footnote)
                        Spacer()
                    }.padding(.horizontal).padding(.vertical, 8)
                }
                if !session.isReading, !session.report.isComplete, !session.report.isLocked, session.errorMessage == nil {
                    Button { category = .overview; noticeReveal += 1 } label: {
                        HStack {
                            Text(String.localizedStringWithFormat(String(localized: "Analysis incomplete — %lld notices"), Int64(session.report.notices.count)))
                            Spacer()
                            Text("Details")
                        }.font(.footnote)
                    }.padding(.horizontal).padding(.vertical, 6)
                }
                if let error = session.errorMessage {
                    Text(error).foregroundStyle(.red).padding()
                }
                if session.report.isLocked {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Password required", systemImage: "lock.fill").font(.headline)
                        Text("Enter the PDF opening password.")
                        SecureField("Password", text: $password)
                            .textContentType(.password).textFieldStyle(.roundedBorder)
                            .onSubmit(unlock)
                        if session.passwordWasIncorrect { Text("The password is incorrect. Please try again.").foregroundStyle(.red) }
                        Button("Open", action: unlock).buttonStyle(.borderedProminent).disabled(session.isReading)
                    }.padding()
                } else {
                    HStack {
                        Picker("Category", selection: $category) {
                            ForEach(PDFInfoCategory.allCases) { category in Label(category.title, systemImage: category.symbol).tag(category) }
                        }.pickerStyle(.menu)
                        Spacer()
                    }.padding(.horizontal).padding(.vertical, 4)
                    Divider()
                    ScrollViewReader { reader in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                Color.clear.frame(height: 0).id("top")
                                let sections = session.report.sections(in: category)
                                if sections.isEmpty, !session.isReading {
                                    Text(session.report.isComplete ? String(localized: "No entries found") : PDFInspectionFormat.unknown).foregroundStyle(.secondary)
                                }
                                ForEach(sections) { section in
                                    PDFInfoSectionView(section: section, fontReveal: fontReveal, noticeReveal: noticeReveal,
                                                       canExport: session.report.allowsResourceExporting && !isExportingResources,
                                                       export: exportResource)
                                }
                            }.padding(.horizontal).padding(.bottom)
                        }
                        .onChange(of: category) { _, _ in reader.scrollTo("top", anchor: .top) }
                        .onChange(of: noticeReveal) { _, _ in reader.scrollTo("top", anchor: .top) }
                        .onChange(of: fontReveal) { _, _ in reader.scrollTo("top", anchor: .top) }
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(session.report.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        do { try PDFReportSharing.copy(session.report); copied = true }
                        catch { message = error.localizedDescription }
                    } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                    .accessibilityLabel("Copy complete report")
                    .disabled(session.isReading || session.report.isLocked || session.errorMessage != nil)
                    Menu {
                        Button("Formatted text (.rtf)") { share(formatted: true) }
                        Button("Plain text (.txt)") { share(formatted: false) }
                        Divider()
                        Button("Export All Resources…") { selectsResourceFolder = true }
                            .disabled(!session.report.allowsResourceExporting || session.report.exportableResources.isEmpty || isExportingResources)
                        if let editing = actions.editing, editing.isEdited, let revision = editing.current {
                            Divider()
                            Button("Export edited PDF…") { sharedRevision = revision }
                        }
                    } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Export")
                    .disabled(session.isReading || session.report.isLocked || session.errorMessage != nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { close(); dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("close")
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { removeMetadata() } label: { Image(systemName: "eraser") }
                        .accessibilityLabel("Remove metadata")
                        .disabled(session.isReading || session.report.isLocked || session.errorMessage != nil || actions.isProcessing || isExportingResources)
                    Button {
                        do { compression = try PDFCompressionSession(editing: actions.editingSession()) }
                        catch { message = error.localizedDescription }
                    } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }
                        .accessibilityLabel("Compress PDF")
                        .disabled(session.isReading || session.report.isLocked || session.errorMessage != nil || actions.isProcessing || isExportingResources)
                    Spacer()
                    Button { actions.editing?.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .accessibilityLabel("Undo PDF edit")
                        .disabled(actions.editing?.canUndo != true || actions.isProcessing)
                    Button { actions.editing?.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                        .accessibilityLabel("Redo PDF edit")
                        .disabled(actions.editing?.canRedo != true || actions.isProcessing)
                }
            }
        }
        .sheet(isPresented: $showsExport, onDismiss: removeExport) {
            if let exportURL { ActivityView(activityItems: [exportURL]) { showsExport = false } }
        }
        .sheet(item: $sharedRevision) { revision in
            ActivityView(activityItems: [revision.input.url]) { sharedRevision = nil }
        }
        .sheet(item: $compression) { model in
            PDFCompressionView(session: model) { compression = nil }
                .presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .fileImporter(isPresented: $selectsResourceFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let parent): exportAllResources(to: parent)
            case .failure(let error):
                if (error as NSError).code != CocoaError.userCancelled.rawValue { message = error.localizedDescription }
            }
        }
        .confirmationDialog("Preserve PDF conformity?", isPresented: $asksConformity, titleVisibility: .visible) {
            Button("Preserve conformity") { actions.removeMetadata(preserveConformity: true) }
            Button("Discard conformity") { actions.removeMetadata(preserveConformity: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Preserving conformity retains only the metadata required by the declared PDF standard. The original file remains unchanged until you explicitly save or export.")
        }
        .alert("PDF information", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
        .onChange(of: actions.errorMessage) { _, value in if let value { message = value; actions.errorMessage = nil } }
        .onChange(of: actions.notice) { _, value in if let value { message = value; actions.notice = nil } }
        .onDisappear { if !showsExport && sharedRevision == nil && compression == nil && !selectsResourceFolder { close(); removeExport() } }
    }
    private func close() { actions.cancel(); resourceExportTask?.cancel(); resourceExportTask = nil; if ownsInspection { session.cancel() } }
    private func unlock() { let value = password; password = ""; session.unlock(value) }
    private func removeMetadata() {
        if session.report.hasConformityDeclaration { asksConformity = true }
        else { actions.removeMetadata(preserveConformity: false) }
    }
    private func share(formatted: Bool) {
        do { removeExport(); exportURL = try PDFReportSharing.export(session.report, formatted: formatted); showsExport = true }
        catch { message = error.localizedDescription }
    }
    private func removeExport() {
        if resourceArtifact == nil, let exportURL { try? FileManager.default.removeItem(at: exportURL.deletingLastPathComponent()) }
        resourceArtifact = nil
        exportURL = nil
    }
    private func exportResource(_ resource: PDFExtractableResource) {
        guard resourceExportTask == nil else { return }
        resourceProgress = PDFResourceExporter.Progress(completed: 0, total: 1, filename: resource.suggestedFilename)
        resourceExportTask = Task {
            do {
                let artifact = try await PDFResourceExporter.extract(resource, from: session)
                try Task.checkCancellation()
                resourceArtifact = artifact
                exportURL = artifact.url
                showsExport = true
            } catch {
                if !(error is CancellationError) { message = error.localizedDescription }
            }
            resourceProgress = nil
            resourceExportTask = nil
        }
    }
    private func exportAllResources(to parent: URL) {
        let resources = session.report.exportableResources
        guard !resources.isEmpty, resourceExportTask == nil else { return }
        resourceExportTask = Task {
            let access = parent.startAccessingSecurityScopedResource()
            defer { if access { parent.stopAccessingSecurityScopedResource() } }
            do {
                let name = PDFResourceExporter.defaultFolderName(for: session.report.fileName)
                let destination = PDFResourceExporter.availableDirectory(named: name, in: parent)
                try await PDFResourceExporter.exportAll(resources, from: session, to: destination) { update in
                    await MainActor.run { resourceProgress = update }
                }
                message = String.localizedStringWithFormat(String(localized: "Exported all resources to %@."), destination.lastPathComponent)
            } catch {
                if !(error is CancellationError) { message = error.localizedDescription }
            }
            resourceProgress = nil
            resourceExportTask = nil
        }
    }
}
