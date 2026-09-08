import Foundation

actor GhostscriptExtensionProfileCatalog {
    private var profiles: [GhostscriptExtensionProfileMetadata]?

    func value() -> [GhostscriptExtensionProfileMetadata]? {
        profiles
    }

    func store(_ profiles: [GhostscriptExtensionProfileMetadata]) {
        self.profiles = profiles
    }
}
