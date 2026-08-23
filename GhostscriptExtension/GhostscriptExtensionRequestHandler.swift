import Darwin
import Foundation
import XPC

/// Executes one file-based Ghostscript request inside the isolated
/// ExtensionKit process.
final class GhostscriptExtensionRequestHandler: XPCPeerHandler, @unchecked Sendable {
    typealias Input = XPCDictionary
    typealias Output = XPCDictionary

    private let fileManager = FileManager.default

    func handleIncomingRequest(_ request: XPCDictionary) -> XPCDictionary? {
        handle(request)
    }

    func handleCancellation(error: XPCRichError) {
        gs_bridge_request_cancellation()
    }

    func handle(_ request: XPCDictionary) -> XPCDictionary {
        var reply = XPCDictionary()
        let version: Int64 = request[GhostscriptExtensionEnvelope.envelopeVersion] ?? -1
        let operation: String = request[GhostscriptExtensionEnvelope.operation] ?? ""
        guard version == GhostscriptExtensionEnvelope.version else {
            reply[GhostscriptExtensionEnvelope.status] = Int64(-1)
            reply[GhostscriptExtensionEnvelope.message] =
                "The XPC request uses an unsupported protocol version."
            return reply
        }

        do {
            switch operation {
            case GhostscriptExtensionEnvelope.profiles:
                reply[GhostscriptExtensionEnvelope.status] = Int64(0)
                reply[GhostscriptExtensionEnvelope.profileMetadataJSON] =
                    Self.bundledProfileMetadataJSON()
            case GhostscriptExtensionEnvelope.run:
                reply = try run(request)
            default:
                reply[GhostscriptExtensionEnvelope.status] = Int64(-1)
                reply[GhostscriptExtensionEnvelope.message] =
                    "The Ghostscript extension received an unknown operation."
            }
        } catch {
            reply[GhostscriptExtensionEnvelope.status] = Int64(-1)
            reply[GhostscriptExtensionEnvelope.message] = error.localizedDescription
        }
        return reply
    }

    private func run(_ request: XPCDictionary) throws -> XPCDictionary {
        let validationOnly: Bool = request[GhostscriptExtensionEnvelope.validate] ?? false
        let limitsEnabled: Bool = request[GhostscriptExtensionEnvelope.limitsEnabled] ?? true
        let allowTransparency: Bool =
            request[GhostscriptExtensionEnvelope.allowTransparency] ?? false
        let standard: String = request[GhostscriptExtensionEnvelope.standard] ?? "none"
        let postScriptRandomSeed: Int64 =
            request[GhostscriptExtensionEnvelope.postScriptRandomSeed] ?? 1
        let deadline: Int64 = request[GhostscriptExtensionEnvelope.deadline]
            ?? Int64(Date().addingTimeInterval(15 * 60).timeIntervalSince1970)
        let maximumOutput: Int64 =
            request[GhostscriptExtensionEnvelope.maximumOutputBytes] ?? 2_147_483_648

        let inputDirectory = try AppGroupWorkspace.inputDirectoryURL()
        let outputDirectory = try AppGroupWorkspace.outputDirectoryURL()
        let readyURL = inputDirectory.appendingPathComponent(AppGroupWorkspace.readyFileName)
        try verifyRegularFile(at: readyURL)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let joboptionsURL = inputDirectory
            .appendingPathComponent(AppGroupWorkspace.joboptionsFileName)
        let inputURL = inputDirectory.appendingPathComponent(AppGroupWorkspace.inputFileName)
        let profilesDirectory = inputDirectory
            .appendingPathComponent(AppGroupWorkspace.profilesDirectoryName, isDirectory: true)
        let partialOutputURL = outputDirectory
            .appendingPathComponent(AppGroupWorkspace.partialOutputFileName)
        let outputURL = outputDirectory.appendingPathComponent(AppGroupWorkspace.outputFileName)
        let partialJournalURL = outputDirectory
            .appendingPathComponent(AppGroupWorkspace.partialJournalFileName)
        let journalURL = outputDirectory.appendingPathComponent(AppGroupWorkspace.journalFileName)

        for url in [partialOutputURL, outputURL, partialJournalURL, journalURL]
        where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }

        let profileConfiguration = try profileConfiguration(
            request,
            profilesDirectory: profilesDirectory
        )

        var joboptions = try openRegularFile(at: joboptionsURL, flags: O_RDONLY | O_CLOEXEC)
        var journal = try openRegularFile(
            at: partialJournalURL,
            flags: O_RDWR | O_CREAT | O_TRUNC | O_CLOEXEC | O_NOFOLLOW,
            mode: 0o600
        )
        var input: Int32 = -1
        var output: Int32 = -1
        if !validationOnly {
            input = try openRegularFile(at: inputURL, flags: O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
            output = try openRegularFile(
                at: partialOutputURL,
                flags: O_RDWR | O_CREAT | O_TRUNC | O_CLOEXEC | O_NOFOLLOW,
                mode: 0o600
            )
        }
        defer {
            [input, output, joboptions, journal]
                .filter { $0 >= 0 }
                .forEach { Darwin.close($0) }
        }

        let compatibilityLevel = validationOnly ? nil : Self.compatibilityLevel(from: joboptions)
        let blendConversionStrategy = validationOnly
            ? nil
            : Self.blendConversionStrategy(from: joboptions)
        let ghostscriptDirectory = Bundle.main.resourceURL?
            .appendingPathComponent("Ghostscript", isDirectory: true)
        let bundledProfileDirectory = Bundle.main.resourceURL?
            .appendingPathComponent("Profiles", isDirectory: true)
        let definitionName = standard.hasPrefix("pdfa") ? "PDFA_def" : "PDFX_def"
        let definitionURL = standard == "none" ? nil : Bundle.main.url(
            forResource: definitionName,
            withExtension: "ps",
            subdirectory: "Ghostscript"
        )
        if standard != "none",
           definitionURL == nil || ghostscriptDirectory == nil || bundledProfileDirectory == nil {
            throw HelperError.message(
                "A standards resource is unavailable in the Ghostscript extension."
            )
        }

        let profileOverrides = profileOverrides(
            profileSelections: profileConfiguration.selections,
            profileDirectory: bundledProfileDirectory,
            stagedUserProfiles: profileConfiguration.userProfiles
        )
        let profileOverrideDirectory = profileConfiguration.userProfiles.isEmpty
            ? nil
            : profilesDirectory
        var ghostscriptCode: Int32 = 0
        var stage: Int32 = 0
        gs_bridge_reset_cancellation()
        let status = standard.withCString { standardPointer in
            Self.withOptionalCString(compatibilityLevel) { compatibilityPointer in
                Self.withOptionalPath(definitionURL) { definitionPointer in
                    Self.withOptionalPath(ghostscriptDirectory) { ghostscriptPointer in
                        Self.withOptionalPath(bundledProfileDirectory) { profilePointer in
                            Self.withOptionalPath(profileOverrideDirectory) { overridesDirectoryPointer in
                                Self.withOptionalCString(profileOverrides) { overridesPointer in
                                    Self.withOptionalCString(blendConversionStrategy) { blendPointer in
                                        gs_run_joboptions_with_fds(
                                            input, output, joboptions, journal,
                                            validationOnly ? 1 : 0,
                                            allowTransparency ? 1 : 0,
                                            compatibilityPointer,
                                            standardPointer,
                                            definitionPointer,
                                            ghostscriptPointer,
                                            profilePointer,
                                            overridesPointer,
                                            overridesDirectoryPointer,
                                            blendPointer,
                                            Int32(postScriptRandomSeed),
                                            limitsEnabled ? 1 : 0,
                                            deadline,
                                            maximumOutput,
                                            &ghostscriptCode,
                                            &stage
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        [input, output, joboptions, journal]
            .filter { $0 >= 0 }
            .forEach { Darwin.close($0) }
        input = -1
        output = -1
        joboptions = -1
        journal = -1

        if fileManager.fileExists(atPath: partialJournalURL.path) {
            try publish(partialJournalURL, as: journalURL)
        }
        if status == 0, !validationOnly {
            try publish(partialOutputURL, as: outputURL)
        } else {
            try? fileManager.removeItem(at: partialOutputURL)
        }

        var reply = XPCDictionary()
        reply[GhostscriptExtensionEnvelope.status] = Int64(status)
        reply[GhostscriptExtensionEnvelope.ghostscriptCode] = Int64(ghostscriptCode)
        reply[GhostscriptExtensionEnvelope.stage] = Int64(stage)
        return reply
    }

    private func profileConfiguration(
        _ request: XPCDictionary,
        profilesDirectory: URL
    ) throws -> ProfileConfiguration {
        let selectionCount: Int64 =
            request[GhostscriptExtensionEnvelope.profileSelectionCount] ?? 0
        guard (0...Self.allowedProfileKeys.count).contains(Int(selectionCount)) else {
            throw HelperError.message("The ICC profile selection count is invalid.")
        }
        var selectedKeys: Set<String> = []
        var selections: [(key: String, name: String)] = []
        for index in 0..<Int(selectionCount) {
            let key: String =
                request[GhostscriptExtensionEnvelope.profileSelectionKey(index)] ?? ""
            let name: String =
                request[GhostscriptExtensionEnvelope.profileSelectionName(index)] ?? ""
            guard Self.allowedProfileKeys.contains(key),
                  !name.isEmpty,
                  name.utf8.count <= 1_024,
                  selectedKeys.insert(key).inserted
            else {
                throw HelperError.message("An ICC profile selection is invalid.")
            }
            selections.append((key, name))
        }

        let userProfileCount: Int64 =
            request[GhostscriptExtensionEnvelope.userProfileCount] ?? 0
        guard (0...Self.allowedProfileKeys.count).contains(Int(userProfileCount)) else {
            throw HelperError.message("The user-profile count is invalid.")
        }
        var userProfiles: [String: URL] = [:]
        for index in 0..<Int(userProfileCount) {
            let key: String = request[GhostscriptExtensionEnvelope.userProfileKey(index)] ?? ""
            guard Self.allowedProfileKeys.contains(key),
                  selectedKeys.contains(key),
                  userProfiles[key] == nil
            else {
                throw HelperError.message("A user-profile key is invalid.")
            }
            let url = profilesDirectory.appendingPathComponent("profile-\(index).icc")
            try verifyRegularFile(at: url)
            userProfiles[key] = url
        }
        return ProfileConfiguration(selections: selections, userProfiles: userProfiles)
    }

    private func verifyRegularFile(at url: URL) throws {
        let descriptor = try openRegularFile(
            at: url,
            flags: O_RDONLY | O_CLOEXEC | O_NOFOLLOW
        )
        Darwin.close(descriptor)
    }

    private func openRegularFile(
        at url: URL,
        flags: Int32,
        mode: mode_t? = nil
    ) throws -> Int32 {
        let descriptor: Int32
        if let mode {
            descriptor = Darwin.open(url.path, flags, mode)
        } else {
            descriptor = Darwin.open(url.path, flags)
        }
        guard descriptor >= 0 else {
            throw HelperError.message(
                "Could not open \(url.lastPathComponent): \(String(cString: strerror(errno)))."
            )
        }

        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG
        else {
            Darwin.close(descriptor)
            throw HelperError.message("A Ghostscript job file is not a regular file.")
        }
        return descriptor
    }

    private func publish(_ partialURL: URL, as finalURL: URL) throws {
        try? fileManager.removeItem(at: finalURL)
        do {
            try fileManager.moveItem(at: partialURL, to: finalURL)
        } catch {
            throw HelperError.message(
                "Could not publish \(finalURL.lastPathComponent): \(error.localizedDescription)"
            )
        }
    }

    private func profileOverrides(
        profileSelections: [(key: String, name: String)],
        profileDirectory: URL?,
        stagedUserProfiles: [String: URL]
    ) -> String? {
        let bundledProfilesByName: [String: URL] = profileDirectory.map { directory in
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            var result: [String: URL] = [:]
            for url in urls {
                guard let profile = try? ICCProfileRecord.inspect(url: url, origin: .bundled)
                else { continue }
                result[profile.name.lowercased(), default: url] = url
            }
            return result
        } ?? [:]
        let profileEntries = profileSelections.compactMap { selection -> String? in
            let url = stagedUserProfiles[selection.key]
                ?? bundledProfilesByName[selection.name.lowercased()]
            guard let url else { return nil }
            return "/\(selection.key) (\(Self.postScriptLiteral(url.path)))"
        }
        return profileEntries.isEmpty
            ? nil
            : "<< \(profileEntries.joined(separator: " ")) >> setdistillerparams"
    }

    private static func compatibilityLevel(from descriptor: Int32) -> String? {
        distillerNameValue(
            from: descriptor,
            key: "CompatibilityLevel",
            allowedValues: allowedCompatibilityLevels
        )
    }

    private static func blendConversionStrategy(from descriptor: Int32) -> String? {
        distillerNameValue(
            from: descriptor,
            key: "BlendConversionStrategy",
            allowedValues: allowedBlendConversionStrategies
        )
    }

    private static func distillerNameValue(
        from descriptor: Int32,
        key: String,
        allowedValues: Set<String>
    ) -> String? {
        let originalOffset = Darwin.lseek(descriptor, 0, SEEK_CUR)
        defer {
            if originalOffset >= 0 {
                Darwin.lseek(descriptor, originalOffset, SEEK_SET)
            }
        }
        guard Darwin.lseek(descriptor, 0, SEEK_SET) >= 0 else { return nil }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        let bufferSize = buffer.count
        while data.count <= 16 * 1024 * 1024 {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, bufferSize)
            }
            if count < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if count == 0 { break }
            data.append(buffer, count: count)
        }

        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? String(data: data, encoding: .utf16LittleEndian)
            ?? String(data: data, encoding: .utf16BigEndian)
        else { return nil }
        return distillerNameValue(in: text, key: key, allowedValues: allowedValues)
    }

    private static func distillerNameValue(
        in text: String,
        key: String,
        allowedValues: Set<String>
    ) -> String? {
        guard let keyRange = text.range(of: "/\(key)") else { return nil }
        var index = keyRange.upperBound
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }
        if index < text.endIndex, text[index] == "/" {
            index = text.index(after: index)
        }

        var endIndex = index
        while endIndex < text.endIndex {
            let character = text[endIndex]
            guard character.isLetter || character.isNumber || character == "." else { break }
            endIndex = text.index(after: endIndex)
        }

        guard index < endIndex else { return nil }
        let value = String(text[index..<endIndex])
        return allowedValues.contains(value) ? value : nil
    }

    private static func postScriptLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
    }

    private static func bundledProfileMetadataJSON() -> String {
        let directory = Bundle.main.resourceURL?
            .appendingPathComponent("Profiles", isDirectory: true)
        let urls = directory.flatMap {
            try? FileManager.default.contentsOfDirectory(
                at: $0,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            )
        } ?? []
        let profiles: [[String: Any]] = urls.compactMap { url in
            guard let metadata = try? ICCProfileRecord.inspect(url: url, origin: .bundled)
            else { return nil }
            return [
                "name": metadata.name,
                "file": url.lastPathComponent,
                "class": metadata.profileClass,
                "colorSpace": metadata.colorSpace,
                "connectionSpace": metadata.connectionSpace
            ]
        }
        guard let data = try? JSONSerialization.data(
            withJSONObject: profiles,
            options: [.sortedKeys]
        ) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func withOptionalPath<Result>(
        _ url: URL?,
        _ body: (UnsafePointer<CChar>?) -> Result
    ) -> Result {
        guard let url else { return body(nil) }
        return url.path.withCString(body)
    }

    private static func withOptionalCString<Result>(
        _ value: String?,
        _ body: (UnsafePointer<CChar>?) -> Result
    ) -> Result {
        guard let value else { return body(nil) }
        return value.withCString(body)
    }

    private static let allowedProfileKeys = Set([
        "CalGrayProfile", "CalRGBProfile", "CalCMYKProfile", "sRGBProfile",
        "OutputICCProfile", "GraphicICCProfile", "ImageICCProfile",
        "TextICCProfile", "PDFXOutputIntentProfile"
    ])

    private static let allowedCompatibilityLevels = Set([
        "1.1", "1.2", "1.3", "1.4", "1.5", "1.6", "1.7", "2.0"
    ])

    private static let allowedBlendConversionStrategies = Set([
        "None", "Simple", "Managed"
    ])

    private struct ProfileConfiguration {
        let selections: [(key: String, name: String)]
        let userProfiles: [String: URL]
    }

    private enum HelperError: LocalizedError {
        case message(String)

        var errorDescription: String? {
            switch self {
            case .message(let value): value
            }
        }
    }
}
