import SwiftUI

@MainActor
struct PDFCompressionView: View {
    private enum EditingScope: Hashable { case document, page }

    @ObservedObject var session: PDFCompressionSession
    let close: () -> Void
    @State private var message: String?
    @State private var password = ""
    @State private var showsLicenses = false
    @State private var editingScope: EditingScope = .document
    @State private var paperSelectionScope: EditingScope?

    var body: some View {
        VStack(spacing: 12) {
            settings
            if let error = session.errorMessage {
                VStack(spacing: 8) {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                    Button("Try again") { session.retry() }
                }.padding(.horizontal)
            }
            if session.passwordRequired {
                HStack {
                    SecureField("Password", text: $password).textFieldStyle(.roundedBorder)
                        .onSubmit(unlock)
                    Button("Open", action: unlock)
                }.padding(.horizontal)
            }
            PDFComparisonSurface(
                original: session.input, result: session.displayedResult,
                previewPage: session.displayedPreviewPageIndex, password: session.password,
                currentPage: $session.currentPage,
                paperSample: displayedPaperSample,
                isChoosingPaperArea: paperSelectionScope != nil,
                paperSampled: applyPaperSample
            )
            if let candidate = session.displayedResult, !candidate.warnings.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(candidate.warnings) { warning in
                            Label(warning.message, systemImage: "exclamationmark.triangle").font(.callout)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 110).padding(.horizontal)
            }
            footer
        }
        .task { session.start() }
        .onDisappear { if !showsLicenses { session.cancel() } }
        .sheet(isPresented: $showsLicenses) { PDFProcessingLicensesView() }
        .alert("Compress PDF", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(session.input.input.fileName).font(.headline).lineLimit(1)
#if os(macOS)
            HStack(alignment: .top, spacing: 12) {
                GroupBox("Document Standard") {
                    CompressionOptionsEditor(
                        options: $session.options,
                        isLevelEnabled: { session.isLevelEnabled($0, for: session.options) },
                        isChoosingPaperArea: paperSelectionScope == .document,
                        choosePaperArea: { togglePaperSelection(.document) },
                        clearPaperArea: clearDocumentPaperArea
                    )
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                GroupBox(pageTitle) { pageSettings }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
#else
            Picker("Settings for", selection: $editingScope) {
                Text("Document").tag(EditingScope.document)
                Text(pageTitle).tag(EditingScope.page)
            }
            .pickerStyle(.segmented)
            if editingScope == .document {
                CompressionOptionsEditor(
                    options: $session.options,
                    isLevelEnabled: { session.isLevelEnabled($0, for: session.options) },
                    isChoosingPaperArea: paperSelectionScope == .document,
                    choosePaperArea: { togglePaperSelection(.document) },
                    clearPaperArea: clearDocumentPaperArea
                )
            } else {
                pageSettings
            }
#endif
            Text("Compression removes metadata, PDF conformity declarations, embedded files and color profiles. Embedded fonts are retained.")
                .font(.caption).foregroundStyle(.secondary)
            documentSize
        }
        .padding(.horizontal)
        .padding(.top)
    }

    private var pageTitle: String {
        String.localizedStringWithFormat(
            String(localized: "Page %lld of %lld"),
            session.currentPageNumber, session.pageCount
        )
    }

    private var pageSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(
                "Page settings",
                selection: Binding(
                    get: { session.currentPageUsesIndividualSettings },
                    set: { session.setCurrentPageUsesIndividualSettingsFromView($0) }
                )
            ) {
                Text("Document Standard").tag(false)
                Text("Individual").tag(true)
            }
            .pickerStyle(.segmented)

            if session.currentPageUsesIndividualSettings {
                CompressionOptionsEditor(
                    options: Binding(
                        get: { session.currentPageOptions },
                        set: { session.updateCurrentPageOptionsFromView($0) }
                    ),
                    isLevelEnabled: { session.isLevelEnabled($0, for: session.currentPageOptions) },
                    isChoosingPaperArea: paperSelectionScope == .page,
                    choosePaperArea: { togglePaperSelection(.page) },
                    clearPaperArea: clearCurrentPagePaperArea
                )
                pageSizeComparison
            } else {
                Label(settingsSummary(session.options), systemImage: "doc.text")
                    .lineLimit(2, reservesSpace: true)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Label(
                    String.localizedStringWithFormat(
                        String(localized: "%lld shared resources use settings from earlier pages."),
                        session.sharedResourcesFromEarlierPages
                    ),
                    systemImage: "link"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .opacity(session.sharedResourcesFromEarlierPages > 0 ? 1 : 0)
                .accessibilityHidden(session.sharedResourcesFromEarlierPages == 0)

            HStack {
                Button("Reset Page") { session.resetCurrentPage() }
                    .disabled(!session.currentPageUsesIndividualSettings)
                Button("Reset All Pages") { session.resetAllPages() }
                    .disabled(session.individualPageCount == 0)
                Spacer()
                Text(
                    String.localizedStringWithFormat(
                        String(localized: "Individual pages: %lld"),
                        session.individualPageCount
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var pageSizeComparison: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Complete PDF").font(.caption).bold()
            HStack {
                Text("With individual page settings")
                Spacer()
                Text(session.resultSize ?? String(localized: "Calculating…"))
            }
            HStack {
                Text("With Document Standard on this page")
                Spacer()
                Text(session.standardComparisonSize ?? String(localized: "Calculating…"))
                    .foregroundStyle(.secondary)
            }
            Text(session.currentPageSizeImpact ?? String(localized: "No file-size difference"))
                .bold()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .opacity(session.currentPageSizeImpact == nil ? 0 : 1)
                .accessibilityHidden(session.currentPageSizeImpact == nil)
        }
        .font(.caption)
        .monospacedDigit()
    }

    private var documentSize: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Original: \(session.originalSize)")
            Spacer()
            VStack(alignment: .trailing) {
                if let size = session.resultSize {
                    Text("Result: \(size)").bold()
                } else {
                    Text("Calculating file size…").foregroundStyle(.secondary)
                }
                Text(session.sizeDifference ?? String(localized: "Calculating file size…"))
                    .font(.caption)
                    .opacity(session.sizeDifference == nil ? 0 : 1)
                    .accessibilityHidden(session.sizeDifference == nil)
            }
        }
        .font(.callout)
        .monospacedDigit()
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { session.cancel(); close() }.keyboardShortcut(.cancelAction)
            Button("Licenses") { showsLicenses = true }.buttonStyle(.plain).font(.caption)
            HStack {
                ProgressView().controlSize(.small)
                Text(progressText).font(.caption).foregroundStyle(.secondary)
            }
            .opacity(session.isProcessing || session.isCalculatingPageDifference ? 1 : 0)
            .accessibilityHidden(!session.isProcessing && !session.isCalculatingPageDifference)
            Spacer()
            Button("Use result") {
                if session.accept() { close() }
                else { message = String(localized: "The PDF changed while the preview was being prepared. Open compression again.") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!session.canAccept)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal)
        .padding(.bottom)
    }

    private var progressText: String {
        if session.candidate != nil && session.currentPageUsesIndividualSettings {
            return String(localized: "Calculating page comparison…")
        }
        return session.pagePreview == nil
            ? String(localized: "Preparing preview…")
            : String(localized: "Compressing complete PDF…")
    }

    private func settingsSummary(_ value: PDFCompressionOptions) -> String {
        let adjustment = value.colorMode == .blackAndWhite
            ? String.localizedStringWithFormat(String(localized: "Threshold: %lld"), value.threshold)
            : String.localizedStringWithFormat(String(localized: "Contrast: %lld"), value.contrast)
        let cleanup = String.localizedStringWithFormat(
            String(localized: "Paper cleanup: %lld"), value.paperCleanup
        )
        var parts = [value.level.title, value.colorMode.title, adjustment, cleanup]
        if value.paperSample != nil { parts.append(String(localized: "Paper area selected")) }
        return parts.joined(separator: " · ")
    }

    private var displayedPaperSample: PDFPaperSample? {
        switch paperSelectionScope ?? editingScope {
        case .document: session.options.paperSample
        case .page: session.currentPageUsesIndividualSettings ? session.currentPageOptions.paperSample : nil
        }
    }

    private func togglePaperSelection(_ scope: EditingScope) {
        editingScope = scope
        paperSelectionScope = paperSelectionScope == scope ? nil : scope
    }

    private func applyPaperSample(_ sample: PDFPaperSample) {
        guard let scope = paperSelectionScope else { return }
        paperSelectionScope = nil
        switch scope {
        case .document:
            session.options.paperSample = sample
        case .page:
            var settings = session.currentPageOptions
            settings.paperSample = sample
            session.updateCurrentPageOptions(settings)
        }
    }

    private func clearCurrentPagePaperArea() {
        if paperSelectionScope == .page { paperSelectionScope = nil }
        var settings = session.currentPageOptions
        settings.paperSample = nil
        session.updateCurrentPageOptions(settings)
    }

    private func clearDocumentPaperArea() {
        if paperSelectionScope == .document { paperSelectionScope = nil }
        session.options.paperSample = nil
    }

    private func unlock() {
        let value = password
        password = ""
        session.unlock(value)
    }
}
