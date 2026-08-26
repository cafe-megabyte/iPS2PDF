import ExtensionFoundation

/// The private ExtensionKit point used for isolated Ghostscript execution.
extension AppExtensionPoint {
    @Definition
    static var iPS2PDFGhostscriptHelper: AppExtensionPoint {
        Name("ghostscriptHelper")
        UserInterface(false)
        Scope(restriction: .application)
    }
}
