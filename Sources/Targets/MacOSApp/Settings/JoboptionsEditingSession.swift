import Foundation

@MainActor
final class JoboptionsEditingSession {
    static let directoryName = "Settings Editing Sessions"

    let originalRecord: JoboptionsRecord
    let originalData: Data
    let workingDirectoryURL: URL
    let workingURL: URL

    private(set) var document: LosslessJoboptionsDocument
    private(set) var issues: [JoboptionsConsistencyIssue] = []
    private(set) var securityLimitsEnabled: Bool
    private(set) var automaticRandomSeed: Bool
    private(set) var manualRandomSeed: Int

    var onChange: (() -> Void)?

    private let repository: JoboptionsRepository
    private let fileManager: FileManager
    private let originalSecurityLimitsEnabled: Bool
    private let originalAutomaticRandomSeed: Bool
    private let originalManualRandomSeed: Int
    private var isFinished = false

    var isDirty: Bool {
        document.data != originalData
            || securityLimitsEnabled != originalSecurityLimitsEnabled
            || automaticRandomSeed != originalAutomaticRandomSeed
            || manualRandomSeed != originalManualRandomSeed
    }

    init(
        repository: JoboptionsRepository,
        fileManager: FileManager = .default
    ) throws {
        guard let record = repository.activeRecord,
              let activeDocument = repository.activeDocument
        else { throw JoboptionsError.unreadable }

        self.repository = repository
        self.fileManager = fileManager
        originalRecord = record
        originalData = activeDocument.data
        document = activeDocument
        originalSecurityLimitsEnabled = repository.securityLimitsEnabled
        originalAutomaticRandomSeed = repository.automaticRandomSeed
        originalManualRandomSeed = repository.manualRandomSeed
        securityLimitsEnabled = repository.securityLimitsEnabled
        automaticRandomSeed = repository.automaticRandomSeed
        manualRandomSeed = repository.manualRandomSeed

        let root = Self.rootDirectory(fileManager: fileManager)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        workingDirectoryURL = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: workingDirectoryURL, withIntermediateDirectories: true)
        workingURL = workingDirectoryURL.appendingPathComponent("Working.joboptions")
        try originalData.write(to: workingURL, options: [.atomic])
        refreshIssues()
    }

    func apply(_ changeSet: JoboptionsChangeSet) throws {
        let updated = try changeSet.applying(to: document)
        guard updated.data != document.data else { return }
        try updated.data.write(to: workingURL, options: [.atomic])
        document = updated
        refreshIssues()
        onChange?()
    }

    func repair() throws {
        let updated = try JoboptionsConsistencyEngine.repair(document, applying: issues)
        guard updated.data != document.data else { return }
        try updated.data.write(to: workingURL, options: [.atomic])
        document = updated
        refreshIssues()
        onChange?()
    }

    func setSecurityLimitsEnabled(_ value: Bool) {
        securityLimitsEnabled = value
        onChange?()
    }

    func setAutomaticRandomSeed(_ value: Bool) {
        automaticRandomSeed = value
        onChange?()
    }

    func setManualRandomSeed(_ value: Int) {
        manualRandomSeed = PostScriptRandomSeedSettings.clampedSeed(value)
        onChange?()
    }

    func commit() throws {
        guard !isFinished else { return }
        try repository.commitEditingSession(
            data: document.data,
            originalRecord: originalRecord,
            originalData: originalData
        )
        if securityLimitsEnabled != originalSecurityLimitsEnabled {
            repository.securityLimitsEnabled = securityLimitsEnabled
        }
        if automaticRandomSeed != originalAutomaticRandomSeed {
            repository.setAutomaticRandomSeed(automaticRandomSeed)
        }
        if manualRandomSeed != originalManualRandomSeed {
            repository.setManualRandomSeed(manualRandomSeed)
        }
        isFinished = true
        cleanup()
    }

    func cancel() {
        guard !isFinished else { return }
        isFinished = true
        cleanup()
    }

    static func cleanupStaleDirectories(fileManager: FileManager = .default) {
        let root = rootDirectory(fileManager: fileManager)
        guard fileManager.fileExists(atPath: root.path) else { return }
        try? fileManager.removeItem(at: root)
    }

    private func refreshIssues() {
        issues = JoboptionsConsistencyEngine.issues(
            in: document,
            context: repository.consistencyAnalysisContext
        )
    }

    private func cleanup() {
        if fileManager.fileExists(atPath: workingDirectoryURL.path) {
            try? fileManager.removeItem(at: workingDirectoryURL)
        }
    }

    private static func rootDirectory(fileManager: FileManager) -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent("iPS2PDF", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
    }
}
