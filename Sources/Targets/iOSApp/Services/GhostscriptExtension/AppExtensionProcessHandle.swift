import ExtensionFoundation

/// Retains and invalidates one ExtensionKit process independently of the main app.
final class AppExtensionProcessHandle: @unchecked Sendable {
    private let process: AppExtensionProcess

    init(process: AppExtensionProcess) {
        self.process = process
    }

    func invalidate() {
        process.invalidate()
    }
}
