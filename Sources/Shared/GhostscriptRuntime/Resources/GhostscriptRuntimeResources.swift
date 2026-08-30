#if os(macOS)
import GhostscriptRuntime
#endif
import Foundation

enum GhostscriptRuntimeResources {
    static var bundle: Bundle {
#if os(macOS)
        Bundle(for: GhostscriptRuntimeBundleMarker.self)
#else
        Bundle.main
#endif
    }

    static var joboptionsDirectoryURL: URL? {
        bundle.url(forResource: "Joboptions", withExtension: nil)
    }

    static var normalJoboptionsURL: URL? {
        bundle.url(
            forResource: "Normal",
            withExtension: "joboptions",
            subdirectory: "Joboptions"
        )
    }

    static var profilesDirectoryURL: URL? {
        bundle.url(forResource: "Profiles", withExtension: nil)?
            .resolvingSymlinksInPath()
    }

    static var ghostscriptDirectoryURL: URL? {
        bundle.url(forResource: "Ghostscript", withExtension: nil)
    }

    static func ghostscriptDefinitionURL(named name: String) -> URL? {
        bundle.url(forResource: name, withExtension: "ps", subdirectory: "Ghostscript")
    }
}
