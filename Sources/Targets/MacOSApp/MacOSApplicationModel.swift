import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class MacOSApplicationModel: ObservableObject {
    static let shared = MacOSApplicationModel()

    let joboptionsRepository = JoboptionsRepository()
    let conversionCoordinator = MacOSConversionCoordinator()

    private(set) var activeConversionCount = 0
    private var idleActions: [() -> Void] = []

    private init() {}

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            self?.openDocuments(at: panel.urls)
        }
    }

    func openDocuments(at urls: [URL]) {
        Task { @MainActor in
            for url in urls {
                do {
                    _ = try await NSDocumentController.shared.openDocument(
                        withContentsOf: url,
                        display: true
                    )
                } catch {
                    presentOpenError(error, fileName: url.lastPathComponent)
                }
            }
        }
    }

    func conversionDidStart() {
        activeConversionCount += 1
    }

    func conversionDidFinish() {
        activeConversionCount = max(0, activeConversionCount - 1)
        guard activeConversionCount == 0 else { return }
        let actions = idleActions
        idleActions.removeAll()
        actions.forEach { $0() }
    }

    func performWhenConversionsFinish(_ action: @escaping () -> Void) {
        if activeConversionCount == 0 {
            action()
        } else {
            idleActions.append(action)
        }
    }

    private func presentOpenError(_ error: Error, fileName: String) {
        let alert = NSAlert(error: error)
        alert.messageText = String.localizedStringWithFormat(
            String(localized: "Could not open %@"),
            fileName
        )
        alert.runModal()
    }
}
