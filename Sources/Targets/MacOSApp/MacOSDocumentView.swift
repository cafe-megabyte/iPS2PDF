import AppKit
import PDFKit

@MainActor
final class MacOSDocumentViewController: NSViewController {
    private let viewModel: MacOSDocumentViewModel
    private let contentContainer = NSView()
    private let progressIndicator = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: String(localized: "Converting with Ghostscript..."))

    init(viewModel: MacOSDocumentViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        viewModel.onPhaseChange = { [weak self] phase in
            self?.render(phase: phase)
        }
        viewModel.onSpinnerVisibilityChange = { [weak self] showsSpinner in
            self?.updateSpinnerVisibility(showsSpinner)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentContainer)
        NSLayoutConstraint.activate([
            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: view.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        render(phase: viewModel.phase)
        updateSpinnerVisibility(viewModel.showsSpinner)
    }

    private func render(phase: MacOSDocumentViewModel.Phase) {
        contentContainer.subviews.forEach { $0.removeFromSuperview() }

        switch phase {
        case .preparing, .converting:
            showConversionProgress()

        case let .pdf(url):
            showPDF(at: url)

        case .importedJoboptions:
            showMessage(String(localized: "Joboptions imported"), symbolName: "checkmark.circle")

        case let .failed(message):
            showFailure(message)
        }
    }

    private func showConversionProgress() {
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .large
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let stackView = NSStackView(views: [progressIndicator, statusLabel])
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 14
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor)
        ])

        updateSpinnerVisibility(viewModel.showsSpinner)
    }

    private func showPDF(at url: URL) {
        let pdfView = InitialScalePDFView()
        pdfView.autoScales = false
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.loadDocument(at: url)

        contentContainer.addSubview(pdfView)
        NSLayoutConstraint.activate([
            pdfView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
    }

    private func showMessage(_ message: String, symbolName: String) {
        let imageView = NSImageView(image: NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) ?? NSImage())
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 42, weight: .regular)
        imageView.contentTintColor = .secondaryLabelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: message)
        label.font = .preferredFont(forTextStyle: .title2)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let stackView = NSStackView(views: [imageView, label])
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor)
        ])
    }

    private func showFailure(_ message: String) {
        let title = NSTextField(labelWithString: String(localized: "Conversion failed"))
        title.font = .preferredFont(forTextStyle: .title2)
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        let textView = NSTextView()
        textView.string = message
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 0, height: 0)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let stackView = NSStackView(views: [title, scrollView])
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: contentContainer.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: contentContainer.trailingAnchor, constant: -24),
            scrollView.widthAnchor.constraint(equalTo: contentContainer.widthAnchor, multiplier: 0.9),
            scrollView.heightAnchor.constraint(lessThanOrEqualToConstant: 420)
        ])
    }

    private func updateSpinnerVisibility(_ showsSpinner: Bool) {
        if showsSpinner {
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
        }
        progressIndicator.isHidden = !showsSpinner
        statusLabel.isHidden = !showsSpinner
    }
}
