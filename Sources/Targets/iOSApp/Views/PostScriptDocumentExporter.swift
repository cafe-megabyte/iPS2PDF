import SwiftUI
import UIKit

struct PostScriptDocumentExporter: UIViewControllerRepresentable {
    let sourceURL: URL
    let onCompletion: (Result<URL, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forExporting: [sourceURL],
            asCopy: true
        )
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) { }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onCompletion: (Result<URL, Error>) -> Void
        private var hasFinished = false

        init(onCompletion: @escaping (Result<URL, Error>) -> Void) {
            self.onCompletion = onCompletion
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            guard let url = urls.first else {
                finish(.failure(CocoaError(.fileNoSuchFile)))
                return
            }
            finish(.success(url))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            finish(.failure(CocoaError(.userCancelled)))
        }

        private func finish(_ result: Result<URL, Error>) {
            guard !hasFinished else { return }
            hasFinished = true
            onCompletion(result)
        }
    }
}
