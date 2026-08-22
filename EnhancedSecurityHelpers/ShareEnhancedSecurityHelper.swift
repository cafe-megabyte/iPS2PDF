import ExtensionFoundation

@main
struct ShareEnhancedSecurityHelper: iPS2PDFEnhancedSecurityExtension {
    @AppExtensionPoint.Bind
    var boundExtensionPoint: AppExtensionPoint {
        AppExtensionPoint.Identifier(host: "de.cafe-megabyte.iPS2PDF.Share", name: "ghostscriptHelper")
    }
}
