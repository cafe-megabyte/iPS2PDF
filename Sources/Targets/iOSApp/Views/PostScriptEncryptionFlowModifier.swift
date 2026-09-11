import SwiftUI

struct PostScriptEncryptionFlowModifier: ViewModifier {
    @ObservedObject var session: PostScriptEncryptionSession

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $session.isPasswordPromptPresented) {
                PostScriptEncryptionPasswordView(
                    sourceName: session.sourceName,
                    cancel: session.dismissPasswordPrompt,
                    encrypt: session.encrypt
                )
            }
            .sheet(
                isPresented: $session.isFileExporterPresented,
                onDismiss: cancelExportIfNeeded
            ) {
                if let artifact = session.artifact {
                    PostScriptDocumentExporter(
                        sourceURL: artifact.url,
                        onCompletion: session.fileExporterDidFinish
                    )
                }
            }
            .overlay {
                if session.showsProgress {
                    ProcessingOverlay()
                }
            }
            .alert(item: $session.alert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
    }

    private func cancelExportIfNeeded() {
        guard session.artifact != nil else { return }
        session.fileExporterDidFinish(.failure(CocoaError(.userCancelled)))
    }
}
