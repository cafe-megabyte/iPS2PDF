import SwiftUI
import UIKit

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
