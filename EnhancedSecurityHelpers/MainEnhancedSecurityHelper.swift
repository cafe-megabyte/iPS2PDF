import ExtensionFoundation

@main
struct MainEnhancedSecurityHelper: iPS2PDFEnhancedSecurityExtension {
    @AppExtensionPoint.Bind
    var boundExtensionPoint: AppExtensionPoint {
        AppExtensionPoint.Identifier(host: "de.cafe-megabyte.iPS2PDF", name: "enhancedSecurity")
    }
}
