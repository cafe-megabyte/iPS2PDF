import Darwin
import Foundation
import XPC
#if os(macOS)
import GhostscriptRuntime
#endif

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

    func handle(
        _ request: XPCDictionary,
        inputFileHandle: FileHandle? = nil
    ) -> XPCDictionary {
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
                reply = try run(request, inputFileHandle: inputFileHandle)
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

    private func run(
        _ request: XPCDictionary,
        inputFileHandle: FileHandle?
    ) throws -> XPCDictionary {
        let validationOnly: Bool = request[GhostscriptExtensionEnvelope.validate] ?? false
        let limitsEnabled: Bool = request[GhostscriptExtensionEnvelope.limitsEnabled] ?? true
        let allowTransparency: Bool =
            request[GhostscriptExtensionEnvelope.allowTransparency] ?? false
        let epsCrop: Bool = request[GhostscriptExtensionEnvelope.epsCrop] ?? false
        let standard: String = request[GhostscriptExtensionEnvelope.standard] ?? "none"
        let requestedEmbedding: Bool =
            request[GhostscriptExtensionEnvelope.embedOutputIntentProfile] ?? false
        let embedsOutputIntentProfile = standard.hasPrefix("pdfx") || requestedEmbedding
        let pdfXMetadata = try pdfXMetadata(from: request)
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
        if standard.hasPrefix("pdfx"),
           !profileConfiguration.selections.contains(where: {
               $0.key == "PDFXOutputIntentProfile"
           }) {
            throw HelperError.message("A PDF/X output intent profile is required.")
        }

        var joboptions = try openRegularFile(at: joboptionsURL, flags: O_RDONLY | O_CLOEXEC)
        var journal = try openRegularFile(
            at: partialJournalURL,
            flags: O_RDWR | O_CREAT | O_TRUNC | O_CLOEXEC | O_NOFOLLOW,
            mode: 0o600
        )
        var input: Int32 = -1
        var output: Int32 = -1
        if !validationOnly {
            if let inputFileHandle {
                input = try duplicateRegularFileDescriptor(
                    inputFileHandle.fileDescriptor,
                    name: AppGroupWorkspace.inputFileName
                )
            } else {
                input = try openRegularFile(at: inputURL, flags: O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
            }
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
        guard let ghostscriptDirectory = GhostscriptRuntimeResources.ghostscriptDirectoryURL else {
            throw HelperError.message(
                "The Ghostscript resource directory is unavailable in the Ghostscript extension."
            )
        }
        let bundledProfileDirectory = GhostscriptRuntimeResources.profilesDirectoryURL
        let bundledDefinitionURL = standard.hasPrefix("pdfx")
            ? GhostscriptRuntimeResources.ghostscriptDefinitionURL(named: "PDFX_def")
            : nil
        if standard.hasPrefix("pdfx"),
           bundledDefinitionURL == nil || bundledProfileDirectory == nil {
            throw HelperError.message(
                "A standards resource is unavailable in the Ghostscript extension."
            )
        }

        let profileOverrides = try profileOverrides(
            profileSelections: profileConfiguration.selections,
            profileDirectory: bundledProfileDirectory,
            stagedUserProfiles: profileConfiguration.userProfiles,
            standard: standard,
            embedsOutputIntentProfile: embedsOutputIntentProfile
        )
        let definitionURL = try standardDefinitionURL(
            bundledDefinitionURL,
            standard: standard,
            profileSelections: profileConfiguration.selections,
            bundledProfileDirectory: bundledProfileDirectory,
            stagedUserProfiles: profileConfiguration.userProfiles,
            profilesDirectory: profilesDirectory,
            inputDirectory: inputDirectory,
            metadata: pdfXMetadata
        )
        let profileOverrideDirectory = profileConfiguration.userProfiles.isEmpty && definitionURL == bundledDefinitionURL
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
                                            epsCrop ? 1 : 0,
                                            0,
                                            0,
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

    private func duplicateRegularFileDescriptor(
        _ descriptor: Int32,
        name: String
    ) throws -> Int32 {
        let duplicate = Darwin.fcntl(descriptor, F_DUPFD_CLOEXEC, 0)
        guard duplicate >= 0 else {
            throw HelperError.message(
                "Could not duplicate \(name): \(String(cString: strerror(errno)))."
            )
        }

        var metadata = stat()
        guard Darwin.fstat(duplicate, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG
        else {
            Darwin.close(duplicate)
            throw HelperError.message("A Ghostscript job file is not a regular file.")
        }

        guard Darwin.lseek(duplicate, 0, SEEK_SET) >= 0 else {
            Darwin.close(duplicate)
            throw HelperError.message(
                "Could not rewind \(name): \(String(cString: strerror(errno)))."
            )
        }
        return duplicate
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
        stagedUserProfiles: [String: URL],
        standard: String,
        embedsOutputIntentProfile: Bool
    ) throws -> String? {
        let resolver = try profileDirectory.map(GhostscriptProfileResolver.init(directoryURL:))
        var resolvedProfiles: [String: (name: String, url: URL, origin: ICCProfileRecord.Origin)] = [:]
        let profileEntries = try profileSelections.map { selection -> String in
            let url: URL
            let origin: ICCProfileRecord.Origin
            if let staged = stagedUserProfiles[selection.key] {
                url = staged
                origin = .user
            } else if let resolver {
                url = try resolver.resolve(selection.name)
                origin = .bundled
            } else {
                throw HelperError.message("The bundled ICC profile directory is unavailable.")
            }
            resolvedProfiles[selection.key] = (selection.name, url, origin)
            return "/\(selection.key) (\(Self.postScriptLiteral(url.path)))"
        }
        var programs: [String] = []
        if !profileEntries.isEmpty {
            programs.append("<< \(profileEntries.joined(separator: " ")) >> setdistillerparams")
        }
        if embedsOutputIntentProfile,
           !standard.hasPrefix("pdfx"),
           let outputProfile = resolvedProfiles["PDFXOutputIntentProfile"] {
            programs.append(try Self.outputIntentProgram(
                profileURL: outputProfile.url,
                profileName: outputProfile.name,
                profileOrigin: outputProfile.origin,
                standard: standard
            ))
        }
        return programs.isEmpty ? nil : programs.joined(separator: "\n")
    }

    private func standardDefinitionURL(
        _ bundledDefinitionURL: URL?,
        standard: String,
        profileSelections: [(key: String, name: String)],
        bundledProfileDirectory: URL?,
        stagedUserProfiles: [String: URL],
        profilesDirectory: URL,
        inputDirectory: URL,
        metadata: PDFXMetadata
    ) throws -> URL? {
        guard let bundledDefinitionURL,
              let bundledProfileDirectory,
              let configuration = standardProfileConfiguration(
                  standard: standard,
                  profileSelections: profileSelections
              )
        else { return bundledDefinitionURL }

        let sourceProfileURL: URL
        let profileOrigin: ICCProfileRecord.Origin
        if let staged = stagedUserProfiles[configuration.key] {
            sourceProfileURL = staged
            profileOrigin = .user
        } else {
            let resolver = try GhostscriptProfileResolver(directoryURL: bundledProfileDirectory)
            sourceProfileURL = try resolver.resolve(configuration.name)
            profileOrigin = .bundled
        }
        let selectedProfile = try ICCProfileRecord.inspect(
            url: sourceProfileURL,
            origin: profileOrigin
        )
        guard selectedProfile.profileClass == "prtr", selectedProfile.colorSpace == "CMYK" else {
            throw HelperError.message(
                "The selected PDF/X output intent must be a CMYK output-device profile."
            )
        }

        let stagedProfileURL = profilesDirectory
            .appendingPathComponent(Self.standardOutputProfileFileName)
        try AppGroupWorkspace.publishFile(from: sourceProfileURL, to: stagedProfileURL)

        let definitionData = try Data(contentsOf: bundledDefinitionURL, options: [.mappedIfSafe])
        let definitionText = String(decoding: definitionData, as: UTF8.self)
        let profileAdjustedDefinition = configuration.originalFilenames.reduce(definitionText) { text, original in
            text.replacingOccurrences(of: original, with: Self.standardOutputProfileFileName)
        }
        let adjustedDefinition = Self.adjustedPDFXDefinition(
            profileAdjustedDefinition,
            profileName: configuration.name,
            metadata: metadata
        )
        let adjustedDefinitionURL = inputDirectory
            .appendingPathComponent(Self.standardDefinitionFileName)
        try Data(adjustedDefinition.utf8).write(to: adjustedDefinitionURL, options: [.atomic])
        return adjustedDefinitionURL
    }

    private func standardProfileConfiguration(
        standard: String,
        profileSelections: [(key: String, name: String)]
    ) -> (key: String, name: String, originalFilenames: [String])? {
        if standard.hasPrefix("pdfx"),
           let selection = profileSelections.first(where: { $0.key == "PDFXOutputIntentProfile" }) {
            return (selection.key, selection.name, ["CoatedFOGRA39.icc", "ISO Coated sb.icc"])
        }
        return nil
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
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private func pdfXMetadata(from request: XPCDictionary) throws -> PDFXMetadata {
        func value(_ key: String) throws -> String {
            let result: String = request[key] ?? ""
            guard result.utf8.count <= 4_096 else {
                throw HelperError.message("A PDF/X output-intent value is too long.")
            }
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let trapped = try value(GhostscriptExtensionEnvelope.pdfXTrapped)
        guard trapped.isEmpty || trapped == "True" || trapped == "False" else {
            throw HelperError.message("The PDF/X trapped state is invalid.")
        }
        return PDFXMetadata(
            outputCondition: try value(GhostscriptExtensionEnvelope.pdfXOutputCondition),
            outputConditionIdentifier: try value(
                GhostscriptExtensionEnvelope.pdfXOutputConditionIdentifier
            ),
            registryName: try value(GhostscriptExtensionEnvelope.pdfXRegistryName),
            trapped: trapped.isEmpty ? "False" : trapped
        )
    }

    private static func outputIntentProgram(
        profileURL: URL,
        profileName: String,
        profileOrigin: ICCProfileRecord.Origin,
        standard: String
    ) throws -> String {
        let profile = try ICCProfileRecord.inspect(url: profileURL, origin: profileOrigin)
        let components: Int
        switch profile.colorSpace {
        case "GRAY": components = 1
        case "RGB", "Lab", "XYZ": components = 3
        case "CMYK": components = 4
        default:
            throw HelperError.message(
                "The selected output intent profile has an unsupported color space."
            )
        }
        let subtype = standard.hasPrefix("pdfa") ? "GTS_PDFA1" : "GTS_PDFX"
        let identifier = profile.outputConditionIdentifier ?? "Custom"
        return """
        [/_objdef {icc_iPS2PDF} /type /stream /OBJ pdfmark
        [{icc_iPS2PDF} << /N \(components) >> /PUT pdfmark
        [{icc_iPS2PDF} (\(postScriptLiteral(profileURL.path))) (r) file /PUT pdfmark
        [/_objdef {OutputIntent_iPS2PDF} /type /dict /OBJ pdfmark
        [{OutputIntent_iPS2PDF} <<
          /Type /OutputIntent
          /S /\(subtype)
          /OutputConditionIdentifier (\(postScriptLiteral(identifier)))
          /Info (\(postScriptLiteral(profileName)))
          /DestOutputProfile {icc_iPS2PDF}
        >> /PUT pdfmark
        [{Catalog} << /OutputIntents [ {OutputIntent_iPS2PDF} ] >> /PUT pdfmark
        """
    }

    private static func adjustedPDFXDefinition(
        _ source: String,
        profileName: String,
        metadata: PDFXMetadata
    ) -> String {
        let identifier = metadata.outputConditionIdentifier.isEmpty
            ? "Custom"
            : metadata.outputConditionIdentifier
        return source.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let text = String(line)
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            let indentation = String(text.prefix { $0 == " " || $0 == "\t" })
            if trimmed.hasPrefix("/Trapped ") {
                return "\(indentation)/Trapped /\(metadata.trapped)"
            }
            if trimmed.hasPrefix("/OutputCondition ") {
                guard !metadata.outputCondition.isEmpty else {
                    return "\(indentation)% /OutputCondition omitted"
                }
                return "\(indentation)/OutputCondition (\(postScriptLiteral(metadata.outputCondition)))"
            }
            if trimmed.hasPrefix("/Info ") {
                return "\(indentation)/Info (\(postScriptLiteral(profileName)))"
            }
            if trimmed.hasPrefix("/OutputConditionIdentifier ") {
                return "\(indentation)/OutputConditionIdentifier (\(postScriptLiteral(identifier)))"
            }
            if trimmed.hasPrefix("/RegistryName ") {
                guard !metadata.registryName.isEmpty else {
                    return "\(indentation)% /RegistryName omitted"
                }
                return "\(indentation)/RegistryName (\(postScriptLiteral(metadata.registryName)))"
            }
            return text
        }.joined(separator: "\n")
    }

    private static func bundledProfileMetadataJSON() -> String {
        let directory = GhostscriptRuntimeResources.profilesDirectoryURL
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
            var result: [String: Any] = [
                "name": metadata.name,
                "fileStem": metadata.fileStem,
                "file": url.lastPathComponent,
                "profileClass": metadata.profileClass,
                "colorSpace": metadata.colorSpace,
                "connectionSpace": metadata.connectionSpace
            ]
            if let identifier = metadata.outputConditionIdentifier {
                result["outputConditionIdentifier"] = identifier
            }
            return result
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

    private static let standardDefinitionFileName = "ActiveStandardDefinition.ps"
    private static let standardOutputProfileFileName = "SelectedOutputProfile.icc"

    private struct ProfileConfiguration {
        let selections: [(key: String, name: String)]
        let userProfiles: [String: URL]
    }

    private struct PDFXMetadata {
        let outputCondition: String
        let outputConditionIdentifier: String
        let registryName: String
        let trapped: String
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
