import PDFKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The system lifecycle controller contains no UIKit controls or UIKit layout.
/// Its entire visible hierarchy is supplied by SwiftUI.
@MainActor
final class ShareViewController: UIHostingController<ShareRootView> {
    private let model: ShareConversionModel

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        let model = ShareConversionModel()
        self.model = model
        super.init(coder: aDecoder, rootView: ShareRootView(model: model))
    }

    @available(*, unavailable)
    override init(rootView: ShareRootView) {
        fatalError("init(rootView:) is unavailable")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        model.start(extensionContext: extensionContext)
    }
}

@MainActor
final class ShareConversionModel: ObservableObject {
    enum Phase {
        case preparing
        case viewer(URL)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .preparing
    private weak var extensionContext: NSExtensionContext?

    func start(extensionContext: NSExtensionContext?) {
        self.extensionContext = extensionContext
        guard let provider = textProviders().first else {
            phase = .failed(String(localized: "No text was provided to iPS2PDF."))
            return
        }
        let typeIdentifier = provider.registeredTypeIdentifiers.first {
            UTType($0)?.conforms(to: .plainText) == true
        } ?? UTType.plainText.identifier

        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { [weak self] item, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    phase = .failed(error.localizedDescription)
                    return
                }
                guard let text = Self.text(from: item) else {
                    phase = .failed(String(localized: "The shared item could not be read as text."))
                    return
                }
                do {
                    phase = .viewer(try await Self.convert(text))
                } catch let failure as ConversionFailure {
                    phase = .failed([failure.localizedMessage, failure.diagnostics]
                        .compactMap { $0 }
                        .joined(separator: "\n"))
                } catch {
                    phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func textProviders() -> [NSItemProvider] {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        return items
            .flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }
    }

    private static func text(from item: NSSecureCoding?) -> String? {
        switch item {
        case let text as String: return text
        case let attributedText as NSAttributedString: return attributedText.string
        case let data as Data: return String(data: data, encoding: .utf8)
        case let url as URL: return try? String(contentsOf: url, encoding: .utf8)
        default: return nil
        }
    }

    private nonisolated static func convert(_ text: String) async throws -> URL {
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("Shared conversion", isDirectory: true)
        try? fileManager.removeItem(at: directoryURL)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let sourceURL = directoryURL.appendingPathComponent(UUID().uuidString).appendingPathExtension("ps")
        let outputURL = sourceURL.deletingPathExtension().appendingPathExtension("pdf")
        let joboptionsURL = directoryURL.appendingPathComponent("Active.joboptions")
        try text.write(to: sourceURL, atomically: true, encoding: .utf8)

        let settings: SharedActiveSettings
        do {
            settings = try SharedActiveSettings.load()
        } catch {
            guard let normal = Bundle.main.url(
                forResource: "Normal",
                withExtension: "joboptions",
                subdirectory: "Joboptions"
            ) else { throw error }
            settings = SharedActiveSettings(
                joboptionsData: try Data(contentsOf: normal),
                standard: .none,
                securityLimitsEnabled: true
            )
        }
        try settings.joboptionsData.write(to: joboptionsURL, options: [.atomic])
        try await GhostscriptConverter().convert(
            sourceURL: sourceURL,
            outputURL: outputURL,
            joboptionsURL: joboptionsURL,
            standard: settings.standard,
            securityLimitsEnabled: settings.securityLimitsEnabled
        )
        guard PDFDocument(url: outputURL) != nil else { throw ConversionFailure.invalidPDF }
        return outputURL
    }
}

struct ShareRootView: View {
    @ObservedObject var model: ShareConversionModel

    var body: some View {
        Group {
            switch model.phase {
            case .preparing:
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Preparing PostScript…")
                        .multilineTextAlignment(.center)
                }
                .padding()
            case let .viewer(url):
                PDFViewer(
                    url: url,
                    onClose: model.finish,
                    onShareStarted: {},
                    onShareFinished: {}
                )
            case let .failed(message):
                ContentUnavailableView {
                    Label("Conversion failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Close", action: model.finish)
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .tint(AppTint.color)
    }
}
