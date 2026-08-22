import Darwin
import Foundation
import XPC

final class EnhancedSecurityRequestHandler: XPCPeerHandler, @unchecked Sendable {
    typealias Input = XPCDictionary
    typealias Output = XPCDictionary

    private let fileManager = FileManager.default
    private var directoryURL: URL?
    private var inputURL: URL?
    private var joboptionsURL: URL?
    private var outputURL: URL?
    private var journalURL: URL?
    private var profileOverrideDirectory: URL?
    private var userProfileURLs: [String: URL] = [:]
    private var profileSelections: [(key: String, name: String)] = []
    private var expectedUserProfileKeys: Set<String> = []
    private var limitsEnabled = true
    private var allowTransparency = false
    private var standard = "none"
    private var postScriptRandomSeed: Int64 = 1
    private var deadline: Int64 = Int64(Date().addingTimeInterval(15 * 60).timeIntervalSince1970)
    private var maximumOutput: Int64 = 2_147_483_648

    deinit {
        cleanup()
    }

    func handleIncomingRequest(_ request: XPCDictionary) -> XPCDictionary? {
        handle(request)
    }

    func handleCancellation(error: XPCRichError) {
        cleanup()
        gs_bridge_request_cancellation()
    }

    func handle(_ request: XPCDictionary) -> XPCDictionary {
        var reply = XPCDictionary()
        let version: Int64 = request[EnhancedSecurityEnvelope.envelopeVersion] ?? -1
        let operation: String = request[EnhancedSecurityEnvelope.operation] ?? ""
        EnhancedSecurityHelperProbeLog.log("received operation=\(operation) version=\(version)")
        guard version == EnhancedSecurityEnvelope.version else {
            reply[EnhancedSecurityEnvelope.status] = Int64(-1)
            reply[EnhancedSecurityEnvelope.message] = "Unsupported XPC envelope."
            return reply
        }

        do {
            switch operation {
            case EnhancedSecurityEnvelope.profiles:
                reply[EnhancedSecurityEnvelope.status] = Int64(0)
                reply[EnhancedSecurityEnvelope.profileMetadataJSON] = Self.bundledProfileMetadataJSON()
            case EnhancedSecurityEnvelope.begin:
                try begin(request)
                reply[EnhancedSecurityEnvelope.status] = Int64(0)
            case EnhancedSecurityEnvelope.append:
                try append(request)
                reply[EnhancedSecurityEnvelope.status] = Int64(0)
            case EnhancedSecurityEnvelope.run:
                reply = try run(request)
            case EnhancedSecurityEnvelope.read:
                reply = try read(request)
            case EnhancedSecurityEnvelope.finish:
                cleanup()
                reply[EnhancedSecurityEnvelope.status] = Int64(0)
            default:
                reply[EnhancedSecurityEnvelope.status] = Int64(-1)
                reply[EnhancedSecurityEnvelope.message] = "Unknown helper operation."
            }
        } catch {
            reply[EnhancedSecurityEnvelope.status] = Int64(-1)
            reply[EnhancedSecurityEnvelope.message] = error.localizedDescription
        }
        return reply
    }

    func cleanup() {
        if let directoryURL {
            try? fileManager.removeItem(at: directoryURL)
        }
        directoryURL = nil
        inputURL = nil
        joboptionsURL = nil
        outputURL = nil
        journalURL = nil
        profileOverrideDirectory = nil
        userProfileURLs = [:]
        profileSelections = []
        expectedUserProfileKeys = []
    }

    private func begin(_ request: XPCDictionary) throws {
        cleanup()
        EnhancedSecurityHelperProbeLog.log("begin start")
        let directoryReport = EnhancedSecurityDirectoryProbe.report(fileManager: fileManager)
        for line in directoryReport.components(separatedBy: "\n") where !line.isEmpty {
            EnhancedSecurityHelperProbeLog.log(line)
        }
        let directory: URL
        do {
            directory = try EnhancedSecurityWorkingDirectory.create(fileManager: fileManager)
        } catch {
            throw HelperError.message("\(error.localizedDescription)\n\(directoryReport)")
        }
        let profiles = directory.appendingPathComponent("Profiles", isDirectory: true)
        try fileManager.createDirectory(at: profiles, withIntermediateDirectories: false)

        directoryURL = directory
        inputURL = directory.appendingPathComponent("input")
        joboptionsURL = directory.appendingPathComponent("Active.joboptions")
        outputURL = directory.appendingPathComponent("output.pdf")
        journalURL = directory.appendingPathComponent("journal.log")
        profileOverrideDirectory = profiles
        limitsEnabled = request[EnhancedSecurityEnvelope.limitsEnabled] ?? true
        allowTransparency = request[EnhancedSecurityEnvelope.allowTransparency] ?? false
        standard = request[EnhancedSecurityEnvelope.standard] ?? "none"
        postScriptRandomSeed = request[EnhancedSecurityEnvelope.postScriptRandomSeed] ?? 1
        deadline = request[EnhancedSecurityEnvelope.deadline] ?? Int64(Date().addingTimeInterval(15 * 60).timeIntervalSince1970)
        maximumOutput = request[EnhancedSecurityEnvelope.maximumOutputBytes] ?? 2_147_483_648

        let allowedProfileKeys = Self.allowedProfileKeys
        let selectionCount: Int64 = request[EnhancedSecurityEnvelope.profileSelectionCount] ?? 0
        guard (0...allowedProfileKeys.count).contains(Int(selectionCount)) else {
            throw HelperError.message("The ICC profile selection count is invalid.")
        }
        var selectedKeys: Set<String> = []
        profileSelections = []
        for index in 0..<Int(selectionCount) {
            let key: String = request[EnhancedSecurityEnvelope.profileSelectionKey(index)] ?? ""
            let name: String = request[EnhancedSecurityEnvelope.profileSelectionName(index)] ?? ""
            guard allowedProfileKeys.contains(key),
                  !name.isEmpty,
                  name.utf8.count <= 1_024,
                  selectedKeys.insert(key).inserted
            else {
                throw HelperError.message("An ICC profile selection is invalid.")
            }
            profileSelections.append((key, name))
        }

        let userProfileCount: Int64 = request[EnhancedSecurityEnvelope.userProfileCount] ?? 0
        guard (0...allowedProfileKeys.count).contains(Int(userProfileCount)) else {
            throw HelperError.message("The user-profile descriptor count is invalid.")
        }
        expectedUserProfileKeys = []
        for index in 0..<Int(userProfileCount) {
            let key: String = request[EnhancedSecurityEnvelope.userProfileKey(index)] ?? ""
            guard allowedProfileKeys.contains(key),
                  selectedKeys.contains(key),
                  expectedUserProfileKeys.insert(key).inserted
            else {
                throw HelperError.message("A user-profile key is invalid.")
            }
            userProfileURLs[key] = profiles.appendingPathComponent("profile-\(index).icc")
        }
        EnhancedSecurityHelperProbeLog.log("begin complete directory=\(directory.path)")
    }

    private func append(_ request: XPCDictionary) throws {
        let stream: String = request[EnhancedSecurityEnvelope.stream] ?? ""
        guard let chunk = XPCDataBridge.data(forKey: EnhancedSecurityEnvelope.chunk, from: request) else {
            throw HelperError.message("The XPC chunk is missing.")
        }
        let url: URL
        switch stream {
        case EnhancedSecurityEnvelope.inputStream:
            guard let inputURL else { throw HelperError.message("The helper input path is unavailable.") }
            url = inputURL
        case EnhancedSecurityEnvelope.joboptionsStream:
            guard let joboptionsURL else { throw HelperError.message("The helper joboptions path is unavailable.") }
            url = joboptionsURL
        case EnhancedSecurityEnvelope.userProfileStream:
            let key: String = request[EnhancedSecurityEnvelope.userProfileKey(0)] ?? ""
            guard expectedUserProfileKeys.contains(key), let profileURL = userProfileURLs[key] else {
                throw HelperError.message("The helper user profile key is invalid.")
            }
            url = profileURL
        default:
            throw HelperError.message("The XPC stream name is invalid.")
        }

        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: chunk)
        EnhancedSecurityHelperProbeLog.log("append stream=\(stream) bytes=\(chunk.count)")
    }

    private func run(_ request: XPCDictionary) throws -> XPCDictionary {
        let validationOnly: Bool = request[EnhancedSecurityEnvelope.validate] ?? false
        EnhancedSecurityHelperProbeLog.log("run start validationOnly=\(validationOnly)")
        guard let joboptionsURL, let journalURL else {
            throw HelperError.message("The helper conversion state is incomplete.")
        }
        if !validationOnly, inputURL == nil || outputURL == nil {
            throw HelperError.message("The helper conversion state is incomplete.")
        }
        guard fileManager.fileExists(atPath: joboptionsURL.path) else {
            throw HelperError.message("The helper joboptions file is missing.")
        }
        if !validationOnly, let inputURL, !fileManager.fileExists(atPath: inputURL.path) {
            throw HelperError.message("The helper input file is missing.")
        }

        let joboptions = Darwin.open(joboptionsURL.path, O_RDONLY | O_CLOEXEC)
        guard joboptions >= 0 else { throw POSIXError(.EBADF) }
        defer { Darwin.close(joboptions) }

        let journal = Darwin.open(journalURL.path, O_RDWR | O_CREAT | O_TRUNC | O_CLOEXEC, 0o600)
        guard journal >= 0 else { throw POSIXError(.EBADF) }
        defer { Darwin.close(journal) }

        var input: Int32 = -1
        var output: Int32 = -1
        if !validationOnly {
            input = Darwin.open(inputURL!.path, O_RDONLY | O_CLOEXEC)
            guard input >= 0 else { throw POSIXError(.EBADF) }
            output = Darwin.open(outputURL!.path, O_RDWR | O_CREAT | O_TRUNC | O_CLOEXEC, 0o600)
            guard output >= 0 else {
                Darwin.close(input)
                throw POSIXError(.EBADF)
            }
        }
        defer {
            [input, output].filter { $0 >= 0 }.forEach { Darwin.close($0) }
        }

        let compatibilityLevel = validationOnly ? nil : Self.compatibilityLevel(from: joboptions)
        let blendConversionStrategy = validationOnly ? nil : Self.blendConversionStrategy(from: joboptions)
        let ghostscriptDirectory = Bundle.main.resourceURL?.appendingPathComponent("Ghostscript", isDirectory: true)
        let profileDirectory = Bundle.main.resourceURL?.appendingPathComponent("Profiles", isDirectory: true)
        let definitionName = standard.hasPrefix("pdfa") ? "PDFA_def" : "PDFX_def"
        let definitionURL = standard == "none" ? nil : Bundle.main.url(
            forResource: definitionName,
            withExtension: "ps",
            subdirectory: "Ghostscript"
        )
        if standard != "none" && (definitionURL == nil || ghostscriptDirectory == nil || profileDirectory == nil) {
            throw HelperError.message("A standards resource is unavailable in the helper.")
        }

        let profileOverrides = profileOverrides(
            profileDirectory: profileDirectory,
            stagedUserProfiles: userProfileURLs
        )
        var ghostscriptCode: Int32 = 0
        var stage: Int32 = 0
        gs_bridge_reset_cancellation()
        let status = standard.withCString { standardPointer in
            Self.withOptionalCString(compatibilityLevel) { compatibilityPointer in
                Self.withOptionalPath(definitionURL) { definitionPointer in
                    Self.withOptionalPath(ghostscriptDirectory) { ghostscriptPointer in
                        Self.withOptionalPath(profileDirectory) { profilePointer in
                            Self.withOptionalPath(profileOverrideDirectory) { overridesDirectoryPointer in
                                Self.withOptionalCString(profileOverrides) { overridesPointer in
                                    Self.withOptionalCString(blendConversionStrategy) { blendConversionPointer in
                                        gs_run_joboptions_with_fds(
                                            input, output, joboptions, journal,
                                            validationOnly ? 1 : 0,
                                            allowTransparency ? 1 : 0,
                                            compatibilityPointer,
                                            standardPointer, definitionPointer, ghostscriptPointer, profilePointer,
                                            overridesPointer, overridesDirectoryPointer, blendConversionPointer,
                                            Int32(postScriptRandomSeed),
                                            limitsEnabled ? 1 : 0, deadline, maximumOutput,
                                            &ghostscriptCode, &stage
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        var reply = XPCDictionary()
        reply[EnhancedSecurityEnvelope.status] = Int64(status)
        reply[EnhancedSecurityEnvelope.ghostscriptCode] = Int64(ghostscriptCode)
        reply[EnhancedSecurityEnvelope.stage] = Int64(stage)
        EnhancedSecurityHelperProbeLog.log("run complete status=\(status) ghostscriptCode=\(ghostscriptCode) stage=\(stage)")
        return reply
    }

    private func read(_ request: XPCDictionary) throws -> XPCDictionary {
        let stream: String = request[EnhancedSecurityEnvelope.stream] ?? ""
        let offset: Int64 = request[EnhancedSecurityEnvelope.offset] ?? 0
        let length: Int64 = request[EnhancedSecurityEnvelope.length] ?? Int64(64 * 1024)
        guard offset >= 0, (0...1_048_576).contains(length) else {
            throw HelperError.message("The read range is invalid.")
        }
        let url: URL?
        switch stream {
        case EnhancedSecurityEnvelope.outputStream:
            url = outputURL
        case EnhancedSecurityEnvelope.journalStream:
            url = journalURL
        default:
            throw HelperError.message("The XPC stream name is invalid.")
        }
        guard let url, fileManager.fileExists(atPath: url.path) else {
            var reply = XPCDictionary()
            reply[EnhancedSecurityEnvelope.status] = Int64(0)
            reply[EnhancedSecurityEnvelope.hasMore] = false
            XPCDataBridge.set(Data(), forKey: EnhancedSecurityEnvelope.chunk, in: reply)
            return reply
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        let data = try handle.read(upToCount: Int(length)) ?? Data()
        let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0

        var reply = XPCDictionary()
        reply[EnhancedSecurityEnvelope.status] = Int64(0)
        reply[EnhancedSecurityEnvelope.hasMore] = offset + Int64(data.count) < Int64(fileSize)
        XPCDataBridge.set(data, forKey: EnhancedSecurityEnvelope.chunk, in: reply)
        return reply
    }

    private func profileOverrides(
        profileDirectory: URL?,
        stagedUserProfiles: [String: URL]
    ) -> String? {
        let bundledProfilesByName: [String: URL] = profileDirectory.map { directory -> [String: URL] in
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            var result: [String: URL] = [:]
            for url in urls {
                guard let profile = try? ICCProfileRecord.inspect(url: url, origin: .bundled) else { continue }
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

    private static let allowedProfileKeys = Set([
        "CalGrayProfile", "CalRGBProfile", "CalCMYKProfile", "sRGBProfile",
        "OutputICCProfile", "GraphicICCProfile", "ImageICCProfile",
        "TextICCProfile", "PDFXOutputIntentProfile"
    ])

    private enum HelperError: LocalizedError {
        case message(String)

        var errorDescription: String? {
            switch self {
            case .message(let value): value
            }
        }
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

    private static let allowedCompatibilityLevels = Set([
        "1.1", "1.2", "1.3", "1.4", "1.5", "1.6", "1.7", "2.0"
    ])

    private static let allowedBlendConversionStrategies = Set([
        "None", "Simple", "Managed"
    ])

    private static func postScriptLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
    }

    private static func bundledProfileMetadataJSON() -> String {
        let directory = Bundle.main.resourceURL?.appendingPathComponent("Profiles", isDirectory: true)
        let urls = directory.flatMap {
            try? FileManager.default.contentsOfDirectory(
                at: $0,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            )
        } ?? []
        let profiles: [[String: Any]] = urls.compactMap { url in
            guard let metadata = try? ICCProfileRecord.inspect(url: url, origin: .bundled) else { return nil }
            return [
                "name": metadata.name,
                "file": url.lastPathComponent,
                "class": metadata.profileClass,
                "colorSpace": metadata.colorSpace,
                "connectionSpace": metadata.connectionSpace
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: profiles, options: [.sortedKeys]) else { return "[]" }
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
}
