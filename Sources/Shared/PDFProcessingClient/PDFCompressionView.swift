import SwiftUI

@MainActor
struct PDFCompressionView: View {
    @ObservedObject var session: PDFCompressionSession
    let close: () -> Void
    @State private var message: String?
    @State private var password = ""
    @State private var showsLicenses = false

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                Text(session.input.input.fileName).font(.headline).lineLimit(1)
                ViewThatFits(in: .horizontal) {
                    HStack { levelPicker; colorPicker }
                    VStack { levelPicker; colorPicker }
                }
                if session.options.colorMode == .blackAndWhite {
                    HStack {
                        Text("Threshold")
                        Slider(value: Binding(get: { Double(session.options.threshold) },
                                              set: { session.options.threshold = Int($0.rounded()) }), in: 0...100, step: 1)
                            .accessibilityLabel("Black and white threshold")
                        Text(session.options.threshold.formatted()).monospacedDigit().frame(width: 32, alignment: .trailing)
                    }
                }
                Text("Compression removes metadata, PDF conformity declarations, embedded files and color profiles. Embedded fonts are retained.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text("Original: \(session.originalSize)")
                    Spacer()
                    if let size = session.resultSize {
                        VStack(alignment: .trailing) {
                            Text("Result: \(size)").bold()
                            if let difference = session.sizeDifference { Text(difference).font(.caption) }
                        }
                    } else { Text("Calculating file size…").foregroundStyle(.secondary) }
                }.font(.callout).monospacedDigit()
            }.padding(.horizontal).padding(.top)
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
            PDFComparisonSurface(original: session.input, result: session.candidate ?? session.pagePreview,
                                 previewPage: session.previewPageIndex, password: session.password,
                                 currentPage: $session.currentPage)
            if let candidate = session.candidate, !candidate.warnings.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(candidate.warnings) { warning in
                            Label(warning.message, systemImage: "exclamationmark.triangle").font(.callout)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 110).padding(.horizontal)
            }
            HStack {
                Button("Cancel") { session.cancel(); close() }.keyboardShortcut(.cancelAction)
                Button("Licenses") { showsLicenses = true }.buttonStyle(.plain).font(.caption)
                if session.isProcessing {
                    ProgressView().controlSize(.small)
                    Text(session.pagePreview == nil ? String(localized: "Preparing preview…") : String(localized: "Compressing complete PDF…"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Use result") {
                    if session.accept() { close() }
                    else { message = String(localized: "The PDF changed while the preview was being prepared. Open compression again.") }
                }.buttonStyle(.borderedProminent).disabled(!session.canAccept).keyboardShortcut(.defaultAction)
            }.padding(.horizontal).padding(.bottom)
        }
        .task { session.start() }
        .onDisappear { if !showsLicenses { session.cancel() } }
        .sheet(isPresented: $showsLicenses) { PDFProcessingLicensesView() }
        .alert("Compress PDF", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }
    private var levelPicker: some View {
        Picker("Compression", selection: $session.options.level) {
            ForEach(PDFCompressionOptions.Level.allCases, id: \.self) { Text($0.title).tag($0) }
        }.pickerStyle(.segmented).frame(minWidth: 230)
    }
    private var colorPicker: some View {
        Picker("Color", selection: $session.options.colorMode) {
            ForEach(PDFCompressionOptions.ColorMode.allCases, id: \.self) { Text($0.title).tag($0) }
        }.pickerStyle(.segmented).frame(minWidth: 130)
    }
    private func unlock() { let value = password; password = ""; session.unlock(value) }
}
