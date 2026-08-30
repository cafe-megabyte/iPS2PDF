import Combine
import Foundation

@MainActor
final class JoboptionsRepository: ObservableObject {
    private enum DefaultsKey {
        static let activeIdentifier = "activeJoboptionsIdentifier"
        static let securityLimitsEnabled = "securityLimitsEnabled"
        static let initializedSecurityLimits = "initializedSecurityLimits"
        static let automaticRandomSeed = "automaticRandomSeed"
        static let manualRandomSeed = "manualRandomSeed"
    }

    @Published private(set) var records: [JoboptionsRecord] = []
    @Published private(set) var activeRecord: JoboptionsRecord?
    @Published private(set) var activeDocument: LosslessJoboptionsDocument?
    @Published private(set) var profiles: [ICCProfileRecord] = []
    @Published private(set) var isReady = false
    @Published var lastError: String?
    @Published var securityLimitsEnabled: Bool {
        didSet { defaults.set(securityLimitsEnabled, forKey: DefaultsKey.securityLimitsEnabled) }
    }
    @Published private(set) var automaticRandomSeed: Bool
    @Published private(set) var manualRandomSeed: Int

    private let fileManager: FileManager
    private let defaults: UserDefaults
    private var readinessWaiters: [CheckedContinuation<Void, Never>] = []

    init(fileManager: FileManager = .default, defaults: UserDefaults = .standard) {
        self.fileManager = fileManager
        self.defaults = defaults
        if defaults.bool(forKey: DefaultsKey.initializedSecurityLimits) {
            securityLimitsEnabled = defaults.bool(forKey: DefaultsKey.securityLimitsEnabled)
        } else {
            securityLimitsEnabled = true
            defaults.set(true, forKey: DefaultsKey.initializedSecurityLimits)
            defaults.set(true, forKey: DefaultsKey.securityLimitsEnabled)
        }
        automaticRandomSeed = defaults.object(forKey: DefaultsKey.automaticRandomSeed) == nil
            ? true
            : defaults.bool(forKey: DefaultsKey.automaticRandomSeed)
        manualRandomSeed = defaults.object(forKey: DefaultsKey.manualRandomSeed) == nil
            ? PostScriptRandomSeedSettings.defaultManualSeed
            : PostScriptRandomSeedSettings.clampedSeed(defaults.integer(forKey: DefaultsKey.manualRandomSeed))

        Task { [weak self] in
            await self?.load()
        }
    }

    var activeName: String { activeRecord?.name ?? "Normal" }

    var activeStandard: PDFStandard {
        guard let raw = activeDocument?.value(forKey: "iPS2PDFStandard")?.textualValue else {
            return .none
        }
        return PDFStandard(rawValue: raw) ?? .none
    }

    var compatibilityLevel: String {
        activeDocument?.value(forKey: "CompatibilityLevel")?.textualValue ?? "1.3"
    }

    var compatibilityIssues: [GhostscriptCompatibilityIssue] {
        guard let activeDocument else { return [] }
        return JoboptionsConsistencyEngine.issues(
            in: activeDocument,
            context: consistencyContext
        )
    }

    var consistencyAnalysisContext: JoboptionsConsistencyContext {
        consistencyContext
    }

    var effectiveDisplayDocument: LosslessJoboptionsDocument? {
        guard let activeDocument else { return nil }
        let issues = JoboptionsConsistencyEngine.issues(
            in: activeDocument,
            context: consistencyContext
        )
        return (try? JoboptionsConsistencyEngine.repair(activeDocument, applying: issues))
            ?? activeDocument
    }

    func waitUntilReady() async {
        if isReady { return }
        await withCheckedContinuation { readinessWaiters.append($0) }
    }

    func activate(_ record: JoboptionsRecord) throws {
        let document = try LosslessJoboptionsDocument(data: Data(contentsOf: record.url))
        activeRecord = record
        activeDocument = document
        defaults.set(record.id, forKey: DefaultsKey.activeIdentifier)
    }

    func update(key: String, value: JoboptionsValue) throws {
        try apply(JoboptionsChangeSet([JoboptionsChange("/\(key)", value)]))
    }

    func update(path: JoboptionsKeyPath, value: JoboptionsValue) throws {
        try apply(JoboptionsChangeSet([JoboptionsChange(path.description, value)]))
    }

    func apply(_ changeSet: JoboptionsChangeSet) throws {
        guard let document = activeDocument else { throw JoboptionsError.unreadable }
        let updated = try changeSet.applying(to: document)
        guard updated.data != document.data else { return }
        let editable = try editableRecord()
        try atomicWrite(updated.data, to: editable.url)
        activeRecord = editable
        activeDocument = updated
        defaults.set(editable.id, forKey: DefaultsKey.activeIdentifier)
        refreshUserRecordsPreservingSelection()
    }

    @discardableResult
    func setStandard(_ standard: PDFStandard) throws -> Bool {
        guard let document = activeDocument else { throw JoboptionsError.unreadable }
        let usesDefaultPDFXOutputIntent = standard.isPDFX
            && SemanticJoboptions.needsDefaultPDFXOutputIntentProfile(in: document)
        try apply(SemanticJoboptions.changeStandard(standard, in: document))
        return usesDefaultPDFXOutputIntent
    }

    func setAutomaticRandomSeed(_ enabled: Bool) {
        automaticRandomSeed = enabled
        defaults.set(enabled, forKey: DefaultsKey.automaticRandomSeed)
    }

    func setManualRandomSeed(_ seed: Int) {
        let clampedSeed = PostScriptRandomSeedSettings.clampedSeed(seed)
        manualRandomSeed = clampedSeed
        defaults.set(clampedSeed, forKey: DefaultsKey.manualRandomSeed)
    }

    func duplicate(_ record: JoboptionsRecord) throws -> JoboptionsRecord {
        let data = try Data(contentsOf: record.url)
        let name = uniqueName(record.name)
        return try adopt(data: data, named: name, activate: true)
    }

    func saveAs(name requestedName: String) throws -> JoboptionsRecord {
        guard let document = activeDocument else { throw JoboptionsError.unreadable }
        let sanitized = sanitizedName(requestedName.isEmpty ? activeName : requestedName)
        return try adopt(data: document.data, named: uniqueName(sanitized), activate: true)
    }

    func importJoboptions(from stagedURL: URL) throws -> JoboptionsRecord {
        let values = try stagedURL.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey])
        guard values.isRegularFile == true else { throw JoboptionsError.unreadable }
        let data = try Data(contentsOf: stagedURL, options: [.mappedIfSafe])
        _ = try LosslessJoboptionsDocument(data: data)
        let baseName = sanitizedName(stagedURL.deletingPathExtension().lastPathComponent)
        return try adopt(data: data, named: uniqueName(baseName), activate: true)
    }

    func delete(_ record: JoboptionsRecord) throws {
        guard !record.isBundled else { return }
        try fileManager.removeItem(at: record.url)
        refreshUserRecordsPreservingSelection()
        if activeRecord?.id == record.id,
           let normal = records.first(where: { $0.isBundled && $0.name == "Normal" }) {
            try activate(normal)
        }
    }

    func exportURL(for record: JoboptionsRecord) throws -> URL {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("Joboptions Exports", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory
            .appendingPathComponent(record.name)
            .appendingPathExtension("joboptions")
        try? fileManager.removeItem(at: destination)
        try fileManager.copyItem(at: record.url, to: destination)
        return destination
    }

    func snapshot() throws -> ConversionSettingsSnapshot {
        guard let document = activeDocument else { throw JoboptionsError.unreadable }
        let effectiveDocument = try JoboptionsConsistencyEngine.effectiveDocument(
            from: document,
            context: consistencyContext
        )
        return ConversionSettingsSnapshot(
            effectiveJoboptionsData: effectiveDocument.data,
            standard: activeStandard,
            securityLimitsEnabled: securityLimitsEnabled,
            postScriptRandomSeed: PostScriptRandomSeedSettings(
                usesAutomaticSeed: automaticRandomSeed,
                manualSeed: manualRandomSeed
            ).resolvedSeed
        )
    }

    func applyGhostscriptCompatibilityAdjustments() throws {
        try applyConsistencyRepairs(compatibilityIssues)
    }

    func applyConsistencyRepairs(_ issues: [JoboptionsConsistencyIssue]) throws {
        guard let document = activeDocument else { throw JoboptionsError.unreadable }
        let adjusted = try JoboptionsConsistencyEngine.repair(document, applying: issues)
        guard adjusted.data != document.data else { return }

        let editable = try editableRecord()
        try atomicWrite(adjusted.data, to: editable.url)
        activeRecord = editable
        activeDocument = adjusted
        defaults.set(editable.id, forKey: DefaultsKey.activeIdentifier)
        refreshUserRecordsPreservingSelection()
    }

    func commitEditingSession(
        data: Data,
        originalRecord: JoboptionsRecord,
        originalData: Data
    ) throws {
        guard data != originalData else { return }
        _ = try LosslessJoboptionsDocument(data: data)
        if originalRecord.isBundled {
            _ = try adopt(
                data: data,
                named: uniqueName(originalRecord.name),
                activate: true
            )
        } else {
            try atomicWrite(data, to: originalRecord.url)
            try activate(originalRecord)
            refreshUserRecordsPreservingSelection()
        }
    }

    func importProfile(from sourceURL: URL) throws {
        let started = sourceURL.startAccessingSecurityScopedResource()
        defer { if started { sourceURL.stopAccessingSecurityScopedResource() } }
        _ = try ICCProfileRecord.inspect(url: sourceURL, origin: .user)
        let directory = try userProfilesDirectory()
        let destination = uniqueFileURL(
            in: directory,
            name: sourceURL.deletingPathExtension().lastPathComponent,
            extension: sourceURL.pathExtension
        )
        try fileManager.copyItem(at: sourceURL, to: destination)
        loadProfiles()
    }

    func deleteProfile(_ profile: ICCProfileRecord) throws {
        guard !profile.isBundled else { return }
        try fileManager.removeItem(at: profile.url)
        loadProfiles()
    }

    private func load() async {
        do {
            try fileManager.createDirectory(
                at: try userJoboptionsDirectory(),
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: try userProfilesDirectory(),
                withIntermediateDirectories: true
            )
            records = try discoverRecords()
            let requestedID = defaults.string(forKey: DefaultsKey.activeIdentifier)
            let selection = records.first { $0.id == requestedID }
                ?? records.first { $0.isBundled && $0.name == "Normal" }
                ?? records.first
            if let selection { try activate(selection) }
            loadProfiles()
            await refreshBundledProfileMetadataFromHelper()
        } catch {
            lastError = error.localizedDescription
        }
        isReady = true
        let waiters = readinessWaiters
        readinessWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func discoverRecords() throws -> [JoboptionsRecord] {
        var discovered: [JoboptionsRecord] = []
        if let bundledDirectory = GhostscriptRuntimeResources.joboptionsDirectoryURL {
            discovered += try records(in: bundledDirectory, origin: .bundled)
        }
        discovered += try records(in: userJoboptionsDirectory(), origin: .user)
        return discovered.sorted {
            if $0.origin != $1.origin { return $0.origin == .bundled }
            if $0.name == "Normal" { return true }
            if $1.name == "Normal" { return false }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func records(in directory: URL, origin: JoboptionsOrigin) throws -> [JoboptionsRecord] {
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return urls.compactMap { url in
            guard url.pathExtension.caseInsensitiveCompare("joboptions") == .orderedSame else {
                return nil
            }
            let name = url.deletingPathExtension().lastPathComponent
            return JoboptionsRecord(
                id: "\(origin.rawValue):\(url.lastPathComponent)",
                name: name,
                origin: origin,
                url: url
            )
        }
    }

    private func editableRecord() throws -> JoboptionsRecord {
        guard let record = activeRecord, let document = activeDocument else {
            throw JoboptionsError.unreadable
        }
        guard record.isBundled else { return record }
        return try adopt(data: document.data, named: uniqueName(record.name), activate: true)
    }

    private func adopt(data: Data, named name: String, activate: Bool) throws -> JoboptionsRecord {
        _ = try LosslessJoboptionsDocument(data: data)
        let destination = try userJoboptionsDirectory()
            .appendingPathComponent(name)
            .appendingPathExtension("joboptions")
        try atomicWrite(data, to: destination)
        let record = JoboptionsRecord(
            id: "user:\(destination.lastPathComponent)",
            name: name,
            origin: .user,
            url: destination
        )
        records = try discoverRecords()
        if activate { try self.activate(record) }
        return record
    }

    private func refreshUserRecordsPreservingSelection() {
        let selectionID = activeRecord?.id
        do {
            records = try discoverRecords()
            if let selectionID,
               let selected = records.first(where: { $0.id == selectionID }) {
                activeRecord = selected
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func uniqueName(_ requestedName: String) -> String {
        let base = sanitizedName(requestedName)
        let existing = Set(records.map { $0.name.lowercased() })
        guard existing.contains(base.lowercased()) else { return base }
        var suffix = 1
        while existing.contains("\(base) (\(suffix))".lowercased()) { suffix += 1 }
        return "\(base) (\(suffix))"
    }

    private func sanitizedName(_ name: String) -> String {
        let leaf = URL(fileURLWithPath: name).lastPathComponent
        let withoutExtension = leaf.lowercased().hasSuffix(".joboptions")
            ? String(leaf.dropLast(".joboptions".count))
            : leaf
        let trimmed = withoutExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Joboptions" : trimmed
    }

    private func atomicWrite(_ data: Data, to destination: URL) throws {
        do {
            try data.write(to: destination, options: [.atomic])
        } catch {
            throw JoboptionsError.writeFailed
        }
    }

    private func userJoboptionsDirectory() throws -> URL {
        try ApplicationStorage.userJoboptionsDirectory(fileManager: fileManager)
    }

    private func userProfilesDirectory() throws -> URL {
        try ApplicationStorage.userProfilesDirectory(fileManager: fileManager)
    }

    private func loadProfiles() {
        var loaded: [ICCProfileRecord] = []
        if let bundled = GhostscriptRuntimeResources.profilesDirectoryURL {
            loaded += inspectProfiles(in: bundled, origin: .bundled)
        }
        if let user = try? userProfilesDirectory() {
            loaded += inspectProfiles(in: user, origin: .user)
        }
        profiles = sortedProfiles(loaded)
    }

    private func refreshBundledProfileMetadataFromHelper() async {
        guard let bundledDirectory = GhostscriptRuntimeResources.profilesDirectoryURL,
              let metadata = try? await GhostscriptExtensionClient().profileMetadata()
        else { return }
        let bundled: [ICCProfileRecord] = metadata.compactMap { item in
            let url = bundledDirectory.appendingPathComponent(item.file)
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            return ICCProfileRecord(
                id: "bundled:\(item.file)",
                name: item.name,
                fileStem: item.fileStem,
                origin: .bundled,
                url: url,
                profileClass: item.profileClass,
                colorSpace: item.colorSpace,
                connectionSpace: item.connectionSpace,
                outputConditionIdentifier: item.outputConditionIdentifier
            )
        }
        let users = profiles.filter { !$0.isBundled }
        profiles = sortedProfiles(bundled + users)
    }

    private func inspectProfiles(in directory: URL, origin: ICCProfileRecord.Origin) -> [ICCProfileRecord] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.compactMap { try? ICCProfileRecord.inspect(url: $0, origin: origin) }
    }

    private func uniqueFileURL(in directory: URL, name: String, extension pathExtension: String) -> URL {
        var candidate = directory.appendingPathComponent(name).appendingPathExtension(pathExtension)
        var suffix = 1
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(name) (\(suffix))")
                .appendingPathExtension(pathExtension)
            suffix += 1
        }
        return candidate
    }

    private var consistencyContext: JoboptionsConsistencyContext {
        JoboptionsConsistencyContext(
            availableProfiles: profiles.map {
                .init(
                    name: $0.name,
                    fileStem: $0.fileStem,
                    colorSpace: $0.colorSpace,
                    profileClass: $0.profileClass,
                    outputConditionIdentifier: $0.outputConditionIdentifier
                )
            }
        )
    }

    private func sortedProfiles(_ profiles: [ICCProfileRecord]) -> [ICCProfileRecord] {
        profiles.sorted {
            let nameComparison = $0.name.localizedStandardCompare($1.name)
            if nameComparison != .orderedSame { return nameComparison == .orderedAscending }
            return $0.fileStem.localizedStandardCompare($1.fileStem) == .orderedAscending
        }
    }
}
