import Foundation
import UniformTypeIdentifiers

@MainActor
final class ShareConversionModel {
    private weak var extensionContext: NSExtensionContext?
    private var activateContainingApplication: ((URL, NSExtensionContext) -> Bool)?
    private var handoffIsReady = false
    private var extensionIsVisible = false
    private var isOpeningApplication = false
    private var activationTask: Task<Void, Never>?

    func start(
        extensionContext: NSExtensionContext?,
        activateContainingApplication: @escaping (URL, NSExtensionContext) -> Bool
    ) {
        self.extensionContext = extensionContext
        self.activateContainingApplication = activateContainingApplication
        let providers = textProviders()
        guard let provider = providers.first else {
            cancelRequest()
            return
        }
        let typeIdentifier = provider.registeredTypeIdentifiers.first {
            UTType($0)?.conforms(to: .plainText) == true
        } ?? provider.registeredTypeIdentifiers.first {
            UTType($0)?.conforms(to: .text) == true
        } ?? UTType.text.identifier

        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { [weak self] item, error in
            let errorMessage = error?.localizedDescription
            let text = Self.text(from: item)
            Task { @MainActor [weak self] in
                guard let self else { return }
                if errorMessage != nil {
                    cancelRequest()
                    return
                }
                guard let text else {
                    cancelRequest()
                    return
                }
                do {
                    _ = try PendingShareDocument.writePostScript(text)
                    handoffIsReady = true
                    scheduleApplicationOpeningIfPossible()
                } catch {
                    cancelRequest(error)
                }
            }
        }
    }

    func extensionDidAppear() {
        extensionIsVisible = true
        scheduleApplicationOpeningIfPossible()
    }

    private func textProviders() -> [NSItemProvider] {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        return items
            .flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.text.identifier) }
    }

    private nonisolated static func text(from item: NSSecureCoding?) -> String? {
        switch item {
        case let text as String: return text
        case let attributedText as NSAttributedString: return attributedText.string
        case let data as Data: return String(data: data, encoding: .utf8)
        case let url as URL: return try? String(contentsOf: url, encoding: .utf8)
        default: return nil
        }
    }

    private func scheduleApplicationOpeningIfPossible() {
        guard handoffIsReady,
              extensionIsVisible,
              !isOpeningApplication,
              let extensionContext,
              let activateContainingApplication
        else { return }

        isOpeningApplication = true
        activationTask = Task { [weak self] in
            // Let the Share Extension finish its presentation transition before
            // asking SpringBoard to activate the containing application.
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled, let self else { return }

            guard activateContainingApplication(
                PendingShareDocument.triggerURL,
                extensionContext
            ) else {
                isOpeningApplication = false
                activationTask = nil
                return
            }
        }
    }

    private func cancelRequest(_ error: Error? = nil) {
        let failure = error ?? CocoaError(.fileReadUnknown)
        extensionContext?.cancelRequest(withError: failure)
    }
}
