import SwiftUI
import UIKit

/// The system lifecycle controller contains no UIKit controls or UIKit layout.
/// Its entire visible hierarchy is supplied by SwiftUI.
@MainActor
final class ShareViewController: UIHostingController<ShareRootView> {
    private let model: ShareConversionModel

    @objc(initWithNibName:bundle:)
    dynamic init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        let model = ShareConversionModel()
        self.model = model
        super.init(rootView: ShareRootView())
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        let model = ShareConversionModel()
        self.model = model
        super.init(coder: aDecoder, rootView: ShareRootView())
    }

    @available(*, unavailable)
    override init(rootView: ShareRootView) {
        fatalError("init(rootView:) is unavailable")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        model.start(
            extensionContext: extensionContext,
            activateContainingApplication: { [weak self] url, extensionContext in
                self?.completeShareAndOpenApplication(
                    url,
                    extensionContext: extensionContext
                ) ?? false
            }
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        model.extensionDidAppear()
    }

    /// Capture the extension's public scene while it is still presented.
    /// Opening before `completeRequest` can be discarded when the active Share
    /// session closes. Opening from the completion handler avoids that race.
    private func completeShareAndOpenApplication(
        _ url: URL,
        extensionContext: NSExtensionContext
    ) -> Bool {
        guard let scene = view.window?.windowScene else { return false }

        extensionContext.completeRequest(returningItems: nil) { _ in
            Task { @MainActor in
                _ = await scene.open(url, options: nil)
            }
        }
        return true
    }
}
