import Foundation

@MainActor
final class MacOSPostScriptExportProviderReference {
    weak var provider: (any MacOSPostScriptExportProviding)?

    init(_ provider: any MacOSPostScriptExportProviding) {
        self.provider = provider
    }
}
