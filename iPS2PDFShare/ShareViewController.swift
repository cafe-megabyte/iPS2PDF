import PDFKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class ShareViewController: UIViewController {
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let messageLabel = UILabel()

    override func loadView() {
        let view = UIView()
        view.backgroundColor = .systemBackground

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()
        view.addSubview(activityIndicator)

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.text = "Preparing PostScript…"
        view.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            messageLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 16),
            messageLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor)
        ])

        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadSharedText()
    }

    private func loadSharedText() {
        guard let provider = textProviders().first else {
            showError("No text was provided to iPS2PDF.")
            return
        }

        let typeIdentifier = provider.registeredTypeIdentifiers.first {
            UTType($0)?.conforms(to: .plainText) == true
        } ?? UTType.plainText.identifier

        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { [weak self] item, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let error {
                    self.showError(error.localizedDescription)
                    return
                }

                guard let text = Self.text(from: item) else {
                    self.showError("The shared item could not be read as text.")
                    return
                }

                do {
                    let outputURL = try await Self.convert(text)
                    self.showPDF(at: outputURL)
                } catch {
                    self.showError("Ghostscript could not convert the shared text.")
                }
            }
        }
    }

    private static func text(from item: NSSecureCoding?) -> String? {
        switch item {
        case let text as String:
            return text
        case let attributedText as NSAttributedString:
            return attributedText.string
        case let data as Data:
            return String(data: data, encoding: .utf8)
        case let url as URL:
            return try? String(contentsOf: url, encoding: .utf8)
        default:
            return nil
        }
    }

    private func textProviders() -> [NSItemProvider] {
        let inputItems = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        return inputItems
            .flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }
    }

    private func showError(_ message: String) {
        activityIndicator.stopAnimating()
        messageLabel.text = message
    }

    private func showPDF(at url: URL) {
        activityIndicator.removeFromSuperview()
        messageLabel.removeFromSuperview()

        let viewer = UIHostingController(
            rootView: PDFViewer(
                url: url,
                onClose: { [weak self] in
                    self?.finishSharing()
                },
                onShareStarted: {},
                onShareFinished: {}
            )
        )
        addChild(viewer)
        viewer.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(viewer.view)

        NSLayoutConstraint.activate([
            viewer.view.topAnchor.constraint(equalTo: view.topAnchor),
            viewer.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            viewer.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            viewer.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        viewer.didMove(toParent: self)
    }

    @objc private func finishSharing() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private nonisolated static func convert(_ text: String) async throws -> URL {
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("Shared conversion", isDirectory: true)
        try? fileManager.removeItem(at: directoryURL)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let sourceURL = directoryURL
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ps")
        let outputURL = sourceURL.deletingPathExtension().appendingPathExtension("pdf")
        try text.write(to: sourceURL, atomically: true, encoding: .utf8)
        try await GhostscriptConverter().convert(
            sourceURL: sourceURL,
            outputURL: outputURL,
            pdfVersion: .v13
        )

        guard PDFDocument(url: outputURL) != nil else {
            throw ConversionFailure.invalidPDF
        }
        return outputURL
    }
}
