import SwiftUI

@MainActor
struct PDFSignatureEditorView: View {
    @ObservedObject var session: PDFSignatureEditingSession
    let close: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.input.input.fileName).font(.headline).lineLimit(1)
                    Text("Tap or click a page to insert the signature. Select it to move, resize or remove it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("Visible signature — not a cryptographic digital signature")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal).padding(.top)

            PDFSignatureCanvas(session: session)
                .accessibilityLabel("PDF signature placement")

            HStack {
                Button(role: .destructive) { session.removeSelected() } label: {
                    Label("Remove signature", systemImage: "trash")
                }
                Divider().frame(height: 20)
                Text("Size")
                Slider(value: Binding(
                    get: { session.selectedFontSize },
                    set: { session.resizeSelected(to: $0) }
                ), in: PDFSignaturePlacement.minimumFontSize...PDFSignaturePlacement.maximumFontSize, step: 1)
                .accessibilityLabel("Signature size")
                Text(String.localizedStringWithFormat(String(localized: "%lld pt"), Int64(session.selectedFontSize.rounded())))
                    .monospacedDigit().frame(minWidth: 54, alignment: .trailing)
            }
            .padding(.horizontal)
            .opacity(session.selectedPlacement == nil ? 0 : 1)
            .allowsHitTesting(session.selectedPlacement != nil)
            .accessibilityHidden(session.selectedPlacement == nil)

            HStack {
                Button("Cancel") { session.cancel(); close() }
                    .keyboardShortcut(.cancelAction)
                if session.isProcessing {
                    ProgressView().controlSize(.small)
                    Text("Creating signed PDF…").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(String.localizedStringWithFormat(String(localized: "Signatures: %lld"), Int64(session.placements.count)))
                    .font(.caption).foregroundStyle(.secondary)
                Button("Apply") { session.apply() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!session.canApply)
            }
            .padding(.horizontal).padding(.bottom)
        }
        #if os(macOS)
        .frame(minWidth: 760, minHeight: 560)
        #endif
        .onChange(of: session.didFinish) { _, finished in if finished { close() } }
        .onDisappear { if !session.didFinish { session.cancel() } }
        .alert("Sign PDF", isPresented: Binding(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { session.errorMessage = nil }
        } message: { Text(session.errorMessage ?? "") }
        .alert("PDF changed", isPresented: Binding(
            get: { session.notice != nil },
            set: { if !$0 { session.acknowledgeNotice() } }
        )) {
            Button("OK") { session.acknowledgeNotice() }
        } message: { Text(session.notice ?? "") }
    }
}
