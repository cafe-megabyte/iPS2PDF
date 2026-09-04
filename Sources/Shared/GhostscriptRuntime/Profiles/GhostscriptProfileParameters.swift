import Foundation

/// Route resolved ICC paths to the Ghostscript operator that accepts them.
/// GraphicICCProfile is the retained Joboptions spelling; pdfwrite calls its
/// corresponding device parameter VectorICCProfile.
enum GhostscriptProfileParameters {
    private static let deviceKeys = [
        "OutputICCProfile": "OutputICCProfile",
        "GraphicICCProfile": "VectorICCProfile",
        "ImageICCProfile": "ImageICCProfile",
        "TextICCProfile": "TextICCProfile"
    ]

    static func program(entries: [(key: String, value: String)], lockDistillerParams: Bool) -> String {
        var distiller: [String] = []
        var device: [String] = []
        for entry in entries {
            if let key = deviceKeys[entry.key] {
                device.append("/\(key) \(entry.value)")
            } else {
                distiller.append("/\(entry.key) \(entry.value)")
            }
        }
        var programs: [String] = []
        if !distiller.isEmpty {
            programs.append("<< \(distiller.joined(separator: " ")) >> setdistillerparams")
        }
        if !device.isEmpty {
            programs.append("<< \(device.joined(separator: " ")) >> setpagedevice")
        }
        guard !programs.isEmpty else { return "" }
        return """
        << /LockDistillerParams false >> setdistillerparams
        \(programs.joined(separator: "\n"))
        << /LockDistillerParams \(lockDistillerParams) >> setdistillerparams
        """
    }
}
