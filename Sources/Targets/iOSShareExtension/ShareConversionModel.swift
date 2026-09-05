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

        if let (provider, typeIdentifier) = sharedFileProvider() {
            loadFile(from: provider, typeIdentifier: typeIdentifier)
            return
        }

        guard let provider = textProviders().first else {
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

    private func loadFile(from provider: NSItemProvider, typeIdentifier: String) {
        let preferredFileName = Self.fileName(
            suggestedName: provider.suggestedName,
            typeIdentifier: typeIdentifier
        )
        provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] url, error in
            let result: Result<Void, Error>
            do {
                if let error { throw error }
                guard let url else { throw CocoaError(.fileReadUnknown) }
                _ = try PendingShareDocument.writeFile(
                    from: url,
                    preferredFileName: preferredFileName
                )
                result = .success(())
            } catch {
                result = .failure(error)
            }

            Task { @MainActor [weak self] in
                self?.completeHandoffPreparation(with: result)
            }
        }
    }

    func extensionDidAppear() {
        extensionIsVisible = true
        scheduleApplicationOpeningIfPossible()
    }

    private func textProviders() -> [NSItemProvider] {
        attachmentProviders()
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.text.identifier) }
    }

    private func sharedFileProvider() -> (NSItemProvider, String)? {
        for provider in attachmentProviders() {
            if let typeIdentifier = provider.registeredTypeIdentifiers.first(where: {
                UTType($0)?.conforms(to: .pdf) == true
            }) {
                return (provider, typeIdentifier)
            }
        }
        for provider in attachmentProviders() {
            if let typeIdentifier = provider.registeredTypeIdentifiers.first(where: {
                guard let type = UTType($0) else { return false }
                return type.conforms(to: .data)
                    && !type.conforms(to: .text)
                    && !type.conforms(to: .url)
            }) {
                return (provider, typeIdentifier)
            }
        }
        return nil
    }

    private func attachmentProviders() -> [NSItemProvider] {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        return items.flatMap { $0.attachments ?? [] }
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

    private nonisolated static func fileName(
        suggestedName: String?,
        typeIdentifier: String
    ) -> String? {
        guard var suggestedName, !suggestedName.isEmpty else { return nil }
        if URL(fileURLWithPath: suggestedName).pathExtension.isEmpty,
           let fileExtension = UTType(typeIdentifier)?.preferredFilenameExtension {
            suggestedName += "." + fileExtension
        }
        return suggestedName
    }

    private func completeHandoffPreparation(with result: Result<Void, Error>) {
        switch result {
        case .success:
            handoffIsReady = true
            scheduleApplicationOpeningIfPossible()
        case let .failure(error):
            cancelRequest(error)
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
