import ExtensionFoundation

/// Entry point for the isolated Ghostscript ExtensionKit process.
@main
struct iPS2PDFGhostscriptExtension: GhostscriptAppExtension {
    @AppExtensionPoint.Bind
    var boundExtensionPoint: AppExtensionPoint {
        AppExtensionPoint.Identifier(host: "de.cafe-megabyte.iPS2PDF", name: "ghostscriptHelper")
    }
}
