import ExtensionFoundation

extension AppExtensionPoint {
#if !ENHANCED_SECURITY_HELPER
    @Definition
    static var iPS2PDFEnhancedSecurity: AppExtensionPoint {
        Name("enhancedSecurity")
        EnhancedSecurity()
    }
#endif
}
