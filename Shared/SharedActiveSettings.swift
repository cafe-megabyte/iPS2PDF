import Foundation

struct PostScriptRandomSeedSettings: Sendable, Equatable {
    static let range = 0...2_147_483_647
    static let defaultManualSeed = 1

    let usesAutomaticSeed: Bool
    let manualSeed: Int

    var resolvedSeed: Int {
        usesAutomaticSeed ? Int.random(in: Self.range) : manualSeed
    }

    init(usesAutomaticSeed: Bool = true, manualSeed: Int = Self.defaultManualSeed) {
        self.usesAutomaticSeed = usesAutomaticSeed
        self.manualSeed = Self.clampedSeed(manualSeed)
    }

    static func clampedSeed(_ seed: Int) -> Int {
        min(max(seed, range.lowerBound), range.upperBound)
    }
}

struct SharedActiveSettings: Sendable {
    private enum Key {
        static let standard = "activePDFStandard"
        static let securityLimitsEnabled = "securityLimitsEnabled"
        static let automaticRandomSeed = "automaticRandomSeed"
        static let manualRandomSeed = "manualRandomSeed"
    }

    static let snapshotFileName = "Active.joboptions"

    let joboptionsData: Data
    let standard: PDFStandard
    let securityLimitsEnabled: Bool
    let randomSeedSettings: PostScriptRandomSeedSettings

    static func load(fileManager: FileManager = .default) throws -> Self {
        let snapshotURL = try AppGroup.containerURL(fileManager: fileManager)
            .appendingPathComponent(snapshotFileName)
        let data = try Data(contentsOf: snapshotURL)
        _ = try LosslessJoboptionsDocument(data: data)
        let defaults = AppGroup.defaults
        let manualSeed = defaults.object(forKey: Key.manualRandomSeed) == nil
            ? PostScriptRandomSeedSettings.defaultManualSeed
            : defaults.integer(forKey: Key.manualRandomSeed)
        return Self(
            joboptionsData: data,
            standard: PDFStandard(rawValue: defaults.string(forKey: Key.standard) ?? "none") ?? .none,
            securityLimitsEnabled: defaults.object(forKey: Key.securityLimitsEnabled) == nil
                ? true
                : defaults.bool(forKey: Key.securityLimitsEnabled),
            randomSeedSettings: PostScriptRandomSeedSettings(
                usesAutomaticSeed: defaults.object(forKey: Key.automaticRandomSeed) == nil
                    ? true
                    : defaults.bool(forKey: Key.automaticRandomSeed),
                manualSeed: manualSeed
            )
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
