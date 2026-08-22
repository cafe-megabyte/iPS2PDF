import ExtensionFoundation

final class AppExtensionProcessHandle: @unchecked Sendable {
    private let process: AppExtensionProcess

    init(process: AppExtensionProcess) {
        self.process = process
    }

    func invalidate() {
        process.invalidate()
    }
}
