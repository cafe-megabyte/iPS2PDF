import PDFKit
import SwiftUI

struct PDFViewer: View {
    let url: URL
    let runtimeSettings: GhostscriptRuntimeSettings
    let onClose: () -> Void
    let onShareStarted: () -> Void
    let onShareFinished: () -> Void
    @StateObject private var editing: PDFEditingSession

    @State private var isShowingShareSheet = false
    @State private var infoSession: PDFInspectionSession?
    @State private var sharedRevision: PDFEditingRevision?

    init(url: URL, runtimeSettings: GhostscriptRuntimeSettings,
         onClose: @escaping () -> Void, onShareStarted: @escaping () -> Void,
         onShareFinished: @escaping () -> Void) {
        self.url = url
        self.runtimeSettings = runtimeSettings
        self.onClose = onClose
        self.onShareStarted = onShareStarted
        self.onShareFinished = onShareFinished
        _editing = StateObject(wrappedValue: PDFEditingSession(url: url))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let current = editing.current {
                    PDFKitView(url: current.input.url, password: editing.passwordForProcessing)
                } else if let error = editing.errorMessage {
                    ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
                } else { ProgressView() }
            }
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(url.lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            sharedRevision = editing.current
                            onShareStarted()
                            isShowingShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(String(localized: "share"))
                        .disabled(editing.current == nil)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { infoSession = editing.inspection } label: { Image(systemName: "info") }
                            .accessibilityLabel("PDF information")
                            .disabled(editing.inspection == nil)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            onClose()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(String(localized: "close"))
                    }
                }
        }
        .sheet(item: $infoSession) { session in
            PDFInfoView(
                session: session,
                editing: editing,
                runtimeSettings: runtimeSettings
            )
        }
        .sheet(isPresented: $isShowingShareSheet, onDismiss: { sharedRevision = nil; onShareFinished() }) {
            if let sharedRevision {
                ActivityView(activityItems: [sharedRevision.input.url]) {
                    isShowingShareSheet = false
                }
            }
        }
    }
}
