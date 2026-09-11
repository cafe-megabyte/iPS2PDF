import Foundation

enum PostScriptOutputNaming {
    static func filename(for sourceName: String) -> String {
        let sourceURL = URL(fileURLWithPath: sourceName)
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let base = stem.isEmpty ? "output" : stem
        if sourceURL.pathExtension.caseInsensitiveCompare("ps") == .orderedSame {
            return base + "-converted.ps"
        }
        return base + ".ps"
    }
}
