import ExtensionFoundation

extension AppExtensionPoint {
    @Definition
    static var iPS2PDFGhostscriptHelper: AppExtensionPoint {
        Name("ghostscriptHelper")
        UserInterface(false)
    }
}
