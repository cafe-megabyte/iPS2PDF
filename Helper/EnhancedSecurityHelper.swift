import Darwin
import ExtensionFoundation
import Foundation
import XPC

protocol iPS2PDFEnhancedSecurityExtension: AppExtension {}

extension iPS2PDFEnhancedSecurityExtension {
    var configuration: some AppExtensionConfiguration {
        ConnectionHandler { request in
            request.accept(
                incomingMessageHandler: { message in
                    EnhancedSecurityRequestHandler.handle(message)
                },
                cancellationHandler: { _ in
                    gs_bridge_request_cancellation()
                }
            )
        }
    }
}

@main
struct EnhancedSecurityHelper: iPS2PDFEnhancedSecurityExtension {
    @AppExtensionPoint.Bind
    var boundExtensionPoint: AppExtensionPoint {
#if SHARE_HELPER
        AppExtensionPoint.Identifier(host: "de.cafe-megabyte.iPS2PDF.Share", name: "enhancedSecurity")
#else
        AppExtensionPoint.Identifier(host: "de.cafe-megabyte.iPS2PDF", name: "enhancedSecurity")
#endif
    }
}

private enum EnhancedSecurityRequestHandler {
    static func handle(_ request: XPCDictionary) -> XPCDictionary {
        var reply = XPCDictionary()
        let version: Int64 = request[EnhancedSecurityEnvelope.envelopeVersion] ?? -1
        let operation: String = request[EnhancedSecurityEnvelope.operation] ?? ""
        guard version == EnhancedSecurityEnvelope.version else {
            reply[EnhancedSecurityEnvelope.status] = Int64(-1)
            reply[EnhancedSecurityEnvelope.message] = "Unsupported XPC envelope."
            return reply
        }
        if operation == EnhancedSecurityEnvelope.profiles {
            reply[EnhancedSecurityEnvelope.status] = Int64(0)
            reply[EnhancedSecurityEnvelope.profileMetadataJSON] = bundledProfileMetadataJSON()
            return reply
        }
        guard operation == EnhancedSecurityEnvelope.validate || operation == EnhancedSecurityEnvelope.convert else {
            reply[EnhancedSecurityEnvelope.status] = Int64(-1)
            reply[EnhancedSecurityEnvelope.message] = "Unknown helper operation."
            return reply
        }

        let joboptions = XPCDescriptorBridge.duplicate(forKey: EnhancedSecurityEnvelope.joboptionsFD, from: request)
        let journal = XPCDescriptorBridge.duplicate(forKey: EnhancedSecurityEnvelope.journalFD, from: request)
        let validationOnly = operation == EnhancedSecurityEnvelope.validate
        let input = validationOnly ? -1 : XPCDescriptorBridge.duplicate(forKey: EnhancedSecurityEnvelope.inputFD, from: request)
        let output = validationOnly ? -1 : XPCDescriptorBridge.duplicate(forKey: EnhancedSecurityEnvelope.outputFD, from: request)
        defer { [joboptions, journal, input, output].filter { $0 >= 0 }.forEach { Darwin.close($0) } }

        guard joboptions >= 0, journal >= 0, validationOnly || (input >= 0 && output >= 0) else {
            reply[EnhancedSecurityEnvelope.status] = Int64(-1)
            reply[EnhancedSecurityEnvelope.message] = "The request did not contain all required file descriptors."
            return reply
        }

        let limitsEnabled: Bool = request[EnhancedSecurityEnvelope.limitsEnabled] ?? true
        let allowTransparency: Bool = request[EnhancedSecurityEnvelope.allowTransparency] ?? false
        let deadline: Int64 = request[EnhancedSecurityEnvelope.deadline] ?? Int64(Date().addingTimeInterval(15 * 60).timeIntervalSince1970)
        let maximumOutput: Int64 = request[EnhancedSecurityEnvelope.maximumOutputBytes] ?? 2_147_483_648
        let standard: String = validationOnly ? "none" : (request[EnhancedSecurityEnvelope.standard] ?? "none")
        let compatibilityLevel = validationOnly ? nil : Self.compatibilityLevel(from: joboptions)
        let ghostscriptDirectory = Bundle.main.resourceURL?.appendingPathComponent("Ghostscript", isDirectory: true)
        let profileDirectory = Bundle.main.resourceURL?.appendingPathComponent("Profiles", isDirectory: true)
        let definitionName = standard.hasPrefix("pdfa") ? "PDFA_def" : "PDFX_def"
        let definitionURL = standard == "none" ? nil : Bundle.main.url(
            forResource: definitionName,
            withExtension: "ps",
            subdirectory: "Ghostscript"
        )
        if standard != "none" && (definitionURL == nil || ghostscriptDirectory == nil || profileDirectory == nil) {
            reply[EnhancedSecurityEnvelope.status] = Int64(-1)
            reply[EnhancedSecurityEnvelope.message] = "A standards resource is unavailable in the helper."
            return reply
        }
        let allowedProfileKeys = Set([
            "CalGrayProfile", "CalRGBProfile", "CalCMYKProfile", "sRGBProfile",
            "OutputICCProfile", "GraphicICCProfile", "ImageICCProfile",
            "TextICCProfile", "PDFXOutputIntentProfile"
        ])
        let selectionCount: Int64 = request[EnhancedSecurityEnvelope.profileSelectionCount] ?? 0
        guard (0...allowedProfileKeys.count).contains(Int(selectionCount)) else {
            reply[EnhancedSecurityEnvelope.status] = Int64(-1)
            reply[EnhancedSecurityEnvelope.message] = "The ICC profile selection count is invalid."
            return reply
        }
        var profileSelections: [(key: String, name: String)] = []
        var selectedKeys: Set<String> = []
        for index in 0..<Int(selectionCount) {
            let key: String = request[EnhancedSecurityEnvelope.profileSelectionKey(index)] ?? ""
            let name: String = request[EnhancedSecurityEnvelope.profileSelectionName(index)] ?? ""
            guard allowedProfileKeys.contains(key),
                  !name.isEmpty,
                  name.utf8.count <= 1_024,
                  selectedKeys.insert(key).inserted
            else {
                reply[EnhancedSecurityEnvelope.status] = Int64(-1)
                reply[EnhancedSecurityEnvelope.message] = "An ICC profile selection is invalid."
                return reply
            }
            profileSelections.append((key, name))
        }
        let requestedProfileCount: Int64 = request[EnhancedSecurityEnvelope.userProfileCount] ?? 0
        guard (0...allowedProfileKeys.count).contains(Int(requestedProfileCount)) else {
            reply[EnhancedSecurityEnvelope.status] = Int64(-1)
            reply[EnhancedSecurityEnvelope.message] = "The user-profile descriptor count is invalid."
            return reply
        }
        var userProfileDescriptors: [Int32] = []
        var userProfileKeys: [String] = []
        var receivedUserKeys: Set<String> = []
        for index in 0..<Int(requestedProfileCount) {
            let key: String = request[EnhancedSecurityEnvelope.userProfileKey(index)] ?? ""
            let descriptor = XPCDescriptorBridge.duplicate(
                forKey: EnhancedSecurityEnvelope.userProfileFD(index),
                from: request
            )
            guard allowedProfileKeys.contains(key),
                  selectedKeys.contains(key),
                  receivedUserKeys.insert(key).inserted,
                  descriptor >= 0
            else {
                userProfileDescriptors.filter { $0 >= 0 }.forEach { Darwin.close($0) }
                reply[EnhancedSecurityEnvelope.status] = Int64(-1)
                reply[EnhancedSecurityEnvelope.message] = "A user-profile descriptor is invalid."
                return reply
            }
            userProfileDescriptors.append(descriptor)
            userProfileKeys.append(key)
        }
        defer { userProfileDescriptors.forEach { Darwin.close($0) } }

        var profileOverrideDirectory: URL?
        var stagedUserProfiles: [String: URL] = [:]
        if !userProfileDescriptors.isEmpty {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("iPS2PDF-Profiles-\(UUID().uuidString)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
                for (index, pair) in zip(userProfileKeys, userProfileDescriptors).enumerated() {
                    let url = directory.appendingPathComponent("profile-\(index).icc")
                    try copyDescriptor(pair.1, to: url)
                    stagedUserProfiles[pair.0] = url
                }
                profileOverrideDirectory = directory
            } catch {
                try? FileManager.default.removeItem(at: directory)
                reply[EnhancedSecurityEnvelope.status] = Int64(-1)
                reply[EnhancedSecurityEnvelope.message] = "A user ICC profile could not be staged in the helper."
                return reply
            }
        }
        defer {
            if let profileOverrideDirectory {
                try? FileManager.default.removeItem(at: profileOverrideDirectory)
            }
        }
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
            return "/\(selection.key) (\(postScriptLiteral(url.path)))"
        }
        let profileOverrides = profileEntries.isEmpty
            ? nil
            : "<< \(profileEntries.joined(separator: " ")) >> setdistillerparams"
        var ghostscriptCode: Int32 = 0
        var stage: Int32 = 0
        gs_bridge_reset_cancellation()
        let status = standard.withCString { standardPointer in
            withOptionalCString(compatibilityLevel) { compatibilityPointer in
                withOptionalPath(definitionURL) { definitionPointer in
                    withOptionalPath(ghostscriptDirectory) { ghostscriptPointer in
                        withOptionalPath(profileDirectory) { profilePointer in
                            withOptionalPath(profileOverrideDirectory) { overridesDirectoryPointer in
                                withOptionalCString(profileOverrides) { overridesPointer in
                                    gs_run_joboptions_with_fds(
                                        input, output, joboptions, journal,
                                        validationOnly ? 1 : 0,
                                        allowTransparency ? 1 : 0,
                                        compatibilityPointer,
                                        standardPointer, definitionPointer, ghostscriptPointer, profilePointer,
                                        overridesPointer, overridesDirectoryPointer,
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
        reply[EnhancedSecurityEnvelope.status] = Int64(status)
        reply[EnhancedSecurityEnvelope.ghostscriptCode] = Int64(ghostscriptCode)
        reply[EnhancedSecurityEnvelope.stage] = Int64(stage)
        return reply
    }

    private static func compatibilityLevel(from descriptor: Int32) -> String? {
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
        return compatibilityLevel(in: text)
    }

    private static func compatibilityLevel(in text: String) -> String? {
        guard let keyRange = text.range(of: "/CompatibilityLevel") else { return nil }
        var index = keyRange.upperBound
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }

        var endIndex = index
        while endIndex < text.endIndex {
            let character = text[endIndex]
            guard character.isNumber || character == "." else { break }
            endIndex = text.index(after: endIndex)
        }

        guard index < endIndex else { return nil }
        let value = String(text[index..<endIndex])
        return allowedCompatibilityLevels.contains(value) ? value : nil
    }

    private static let allowedCompatibilityLevels = Set([
        "1.1", "1.2", "1.3", "1.4", "1.5", "1.6", "1.7", "2.0"
    ])

    private static func copyDescriptor(_ descriptor: Int32, to destinationURL: URL) throws {
        guard Darwin.lseek(descriptor, 0, SEEK_SET) >= 0 else {
            throw CocoaError(.fileReadUnknown)
        }
        guard FileManager.default.createFile(atPath: destinationURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let source = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        let destination = try FileHandle(forWritingTo: destinationURL)
        do {
            while let data = try source.read(upToCount: 64 * 1024), !data.isEmpty {
                try destination.write(contentsOf: data)
            }
            try destination.synchronize()
            try destination.close()
        } catch {
            try? destination.close()
            throw error
        }
    }

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
