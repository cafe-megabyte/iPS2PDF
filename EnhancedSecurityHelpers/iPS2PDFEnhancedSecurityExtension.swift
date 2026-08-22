import ExtensionFoundation

protocol iPS2PDFEnhancedSecurityExtension: AppExtension {}

extension iPS2PDFEnhancedSecurityExtension {
    @MainActor
    var configuration: some AppExtensionConfiguration {
        ConnectionHandler { request in
            request.accept { _ in
                EnhancedSecurityRequestHandler()
            }
        }
    }
}
