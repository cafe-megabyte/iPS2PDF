import Combine
import Foundation

struct ConversionSettingsSnapshot: Sendable {
    let joboptionsData: Data
    let standard: PDFStandard
    let securityLimitsEnabled: Bool
}

@MainActor
final class JoboptionsRepository: ObservableObject {
    private enum DefaultsKey {
        static let activeIdentifier = "activeJoboptionsIdentifier"
        static let securityLimitsEnabled = "securityLimitsEnabled"
        static let initializedSecurityLimits = "initializedSecurityLimits"
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

    private let fileManager: FileManager
    private let defaults: UserDefaults
    private var readinessWaiters: [CheckedContinuation<Void, Never>] = []

    init(fileManager: FileManager = .default, defaults: UserDefaults = AppGroup.defaults) {
        self.fileManager = fileManager
        self.defaults = defaults
        if defaults.bool(forKey: DefaultsKey.initializedSecurityLimits) {
            securityLimitsEnabled = defaults.bool(forKey: DefaultsKey.securityLimitsEnabled)
        } else {
            securityLimitsEnabled = true
            defaults.set(true, forKey: DefaultsKey.initializedSecurityLimits)
            defaults.set(true, forKey: DefaultsKey.securityLimitsEnabled)
        }

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

    func waitUntilReady() async {
        if isReady { return }
        await withCheckedContinuation { readinessWaiters.append($0) }
    }

    func activate(_ record: JoboptionsRecord) throws {
        let document = try LosslessJoboptionsDocument(data: Data(contentsOf: record.url))
        try publishActiveSnapshot(document)
        activeRecord = record
        activeDocument = document
        defaults.set(record.id, forKey: DefaultsKey.activeIdentifier)
    }

    func update(key: String, value: JoboptionsValue) throws {
        let editable = try editableRecord()
        guard let document = activeDocument else { throw JoboptionsError.unreadable }
        let updated = try document.replacingValue(forKey: key, with: value)
        try atomicWrite(updated.data, to: editable.url)
        try publishActiveSnapshot(updated)
        activeRecord = editable
        activeDocument = updated
        defaults.set(editable.id, forKey: DefaultsKey.activeIdentifier)
        refreshUserRecordsPreservingSelection()
    }

    func setStandard(_ standard: PDFStandard) throws {
        try update(key: "iPS2PDFStandard", value: .name(standard.rawValue))
        guard standard != .none else {
            try update(key: "PDFX1aCheck", value: .boolean(false))
            try update(key: "PDFX3Check", value: .boolean(false))
            return
        }

        if let compatibility = standard.requiredCompatibilityLevel {
            try update(
                key: "CompatibilityLevel",
                value: .number(Double(compatibility) ?? 1.7, original: compatibility)
            )
        }
        try update(key: "EmbedAllFonts", value: .boolean(true))
        try update(key: "Encrypt", value: .boolean(false))
        try update(key: "EncryptionR", value: .number(0, original: "0"))
        try update(key: "OwnerPassword", value: .string(""))
        try update(key: "UserPassword", value: .string(""))
        try update(key: "PDFX1aCheck", value: .boolean(standard == .pdfx1))
        try update(key: "PDFX3Check", value: .boolean(standard == .pdfx3))
        if standard.ghostscriptPDFAValue != nil || standard.ghostscriptPDFXValue != nil {
            try update(key: "CannotEmbedFontPolicy", value: .name("Error"))
        }
        if standard.ghostscriptPDFAValue != nil {
            try update(key: "ColorConversionStrategy", value: .name("RGB"))
            if let profile = profiles.first(where: { $0.colorSpace == "RGB" && $0.name.localizedCaseInsensitiveContains("sRGB") })
                ?? profiles.first(where: { $0.colorSpace == "RGB" }) {
                try update(key: "OutputICCProfile", value: .string(profile.name))
            }
        } else if standard.ghostscriptPDFXValue != nil {
            try update(key: "ColorConversionStrategy", value: .name("CMYK"))
            if let profile = profiles.first(where: { $0.colorSpace == "CMYK" }) {
                try update(key: "PDFXOutputIntentProfile", value: .string(profile.name))
            }
        }
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
        return ConversionSettingsSnapshot(
            joboptionsData: document.data,
            standard: activeStandard,
            securityLimitsEnabled: securityLimitsEnabled
        )
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
        if let bundledDirectory = Bundle.main.url(
            forResource: "Joboptions",
            withExtension: nil
        ) {
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

    private func publishActiveSnapshot(_ document: LosslessJoboptionsDocument) throws {
        let rawStandard = document.value(forKey: "iPS2PDFStandard")?.textualValue ?? "none"
        try SharedActiveSettings.publish(
            document: document,
            standard: PDFStandard(rawValue: rawStandard) ?? .none,
            fileManager: fileManager
        )
    }

    private func userJoboptionsDirectory() throws -> URL {
        try AppGroup.containerURL(fileManager: fileManager)
            .appendingPathComponent("Joboptions", isDirectory: true)
    }

    private func userProfilesDirectory() throws -> URL {
        try AppGroup.containerURL(fileManager: fileManager)
            .appendingPathComponent("Profiles", isDirectory: true)
    }

    private func loadProfiles() {
        var loaded: [ICCProfileRecord] = []
        if let bundled = Bundle.main.url(forResource: "Profiles", withExtension: nil) {
            loaded += inspectProfiles(in: bundled, origin: .bundled)
        }
        if let user = try? userProfilesDirectory() {
            loaded += inspectProfiles(in: user, origin: .user)
        }
        profiles = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func refreshBundledProfileMetadataFromHelper() async {
        guard let bundledDirectory = Bundle.main.url(forResource: "Profiles", withExtension: nil),
              let metadata = try? await EnhancedSecurityClient().profileMetadata()
        else { return }
        let bundled: [ICCProfileRecord] = metadata.compactMap { item in
            let url = bundledDirectory.appendingPathComponent(item.file)
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            return ICCProfileRecord(
                id: "bundled:\(item.file)",
                name: item.name,
                origin: .bundled,
                url: url,
                profileClass: item.profileClass,
                colorSpace: item.colorSpace,
                connectionSpace: item.connectionSpace
            )
        }
        let users = profiles.filter { !$0.isBundled }
        profiles = (bundled + users).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
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
}
