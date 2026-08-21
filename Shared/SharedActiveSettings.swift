import Foundation

struct SharedActiveSettings: Sendable {
    private enum Key {
        static let standard = "activePDFStandard"
        static let securityLimitsEnabled = "securityLimitsEnabled"
    }

    static let snapshotFileName = "Active.joboptions"

    let joboptionsData: Data
    let standard: PDFStandard
    let securityLimitsEnabled: Bool

    static func load(fileManager: FileManager = .default) throws -> Self {
        let snapshotURL = try AppGroup.containerURL(fileManager: fileManager)
            .appendingPathComponent(snapshotFileName)
        let data = try Data(contentsOf: snapshotURL)
        _ = try LosslessJoboptionsDocument(data: data)
        let defaults = AppGroup.defaults
        return Self(
            joboptionsData: data,
            standard: PDFStandard(rawValue: defaults.string(forKey: Key.standard) ?? "none") ?? .none,
            securityLimitsEnabled: defaults.object(forKey: Key.securityLimitsEnabled) == nil
                ? true
                : defaults.bool(forKey: Key.securityLimitsEnabled)
        )
    }

    static func publish(
        document: LosslessJoboptionsDocument,
        standard: PDFStandard,
        fileManager: FileManager = .default
    ) throws {
        let snapshotURL = try AppGroup.containerURL(fileManager: fileManager)
            .appendingPathComponent(snapshotFileName)
        try document.data.write(to: snapshotURL, options: [.atomic])
        AppGroup.defaults.set(standard.rawValue, forKey: Key.standard)
    }
}
