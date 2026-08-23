import ExtensionFoundation

extension GhostscriptAppExtension {
    @MainActor
    var configuration: some AppExtensionConfiguration {
        ConnectionHandler { request in
            request.accept { _ in
                GhostscriptExtensionRequestHandler()
            }
        }
    }
}
