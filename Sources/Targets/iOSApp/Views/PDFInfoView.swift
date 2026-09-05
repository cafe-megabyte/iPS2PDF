import SwiftUI

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
                                ForEach(sections) { section in PDFInfoSectionView(section: section, fontReveal: fontReveal, noticeReveal: noticeReveal) }
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
                        if let editing = actions.editing, editing.isEdited, let revision = editing.current {
                            Button("Export edited PDF…") { sharedRevision = revision }
                            Divider()
                        }
                        Button("Formatted text (.rtf)") { share(formatted: true) }
                        Button("Plain text (.txt)") { share(formatted: false) }
                    } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Export complete report")
                    .disabled(session.isReading || session.report.isLocked || session.errorMessage != nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { close(); dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("close")
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { removeMetadata() } label: { Image(systemName: "eraser") }
                        .accessibilityLabel("Remove metadata")
                        .disabled(session.isReading || session.report.isLocked || session.errorMessage != nil || actions.isProcessing)
                    Button {
                        do { compression = try PDFCompressionSession(editing: actions.editingSession()) }
                        catch { message = error.localizedDescription }
                    } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }
                        .accessibilityLabel("Compress PDF")
                        .disabled(session.isReading || session.report.isLocked || session.errorMessage != nil || actions.isProcessing)
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
        .onDisappear { if !showsExport && sharedRevision == nil && compression == nil { close(); removeExport() } }
    }
    private func close() { actions.cancel(); if ownsInspection { session.cancel() } }
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
        if let exportURL { try? FileManager.default.removeItem(at: exportURL.deletingLastPathComponent()) }
        exportURL = nil
    }
}

private struct PDFInfoSectionView: View {
    let section: PDFInfoSection
    let fontReveal: Int
    let noticeReveal: Int
    @State private var expanded: Bool
    init(section: PDFInfoSection, fontReveal: Int, noticeReveal: Int) { self.section = section; self.fontReveal = fontReveal; self.noticeReveal = noticeReveal; _expanded = State(initialValue: section.initiallyExpanded || section.warning != nil || section.id == "analysis-notices" && noticeReveal > 0) }
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                if let warning = section.warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill").font(.subheadline.bold())
                }
                ForEach(section.fields) { field in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(field.label).font(.caption).foregroundStyle(.secondary)
                        Text(field.value).font(section.id == "xmp" ? .system(.footnote, design: .monospaced) : .body).textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, field.emphasis == nil ? 0 : 5)
                    .padding(.horizontal, field.emphasis == nil ? 0 : 7)
                    .background {
                        if let emphasis = field.emphasis {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(emphasis.backgroundColor)
                        }
                    }
                    .overlay {
                        if let emphasis = field.emphasis {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(emphasis.borderColor, lineWidth: 1)
                        }
                    }
                }
            }.padding(.top, 10)
        } label: { Text(section.title).font(.headline).foregroundStyle(.primary).textSelection(.enabled) }
        .padding(14)
        .background(section.warning == nil ? Color(uiColor: .secondarySystemGroupedBackground) : Color.orange.opacity(0.20), in: RoundedRectangle(cornerRadius: 12))
        .overlay { if section.warning != nil { RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.62), lineWidth: 1) } }
        .onChange(of: noticeReveal) { _, _ in if section.id == "analysis-notices" { expanded = true } }
        .onChange(of: fontReveal) { _, _ in if section.warning != nil { expanded = true } }
    }
}

private extension PDFInfoFieldEmphasis {
    var color: Color {
        switch self {
        case .standardDeclaration: .indigo
        case .warning: .orange
        }
    }

    var backgroundColor: Color {
        switch self {
        case .standardDeclaration: color.opacity(0.14)
        case .warning: color.opacity(0.20)
        }
    }

    var borderColor: Color {
        switch self {
        case .standardDeclaration: color.opacity(0.50)
        case .warning: color.opacity(0.62)
        }
    }

}
