@preconcurrency import ExtensionFoundation
import Foundation
import XPC

/// Prepares one shared conversion job and uses XPC only to control its
/// isolated ExtensionKit process.
final class GhostscriptExtensionClient: @unchecked Sendable {
    private let maximumInputBytes: Int64 = 1_073_741_824
    private let maximumOutputBytes: Int64 = 2_147_483_648
    private let timeout: TimeInterval = 15 * 60

    func profileMetadata() async throws -> [GhostscriptExtensionProfileMetadata] {
        let reply = try await send(baseRequest(operation: GhostscriptExtensionEnvelope.profiles))
        let status: Int64 = reply[GhostscriptExtensionEnvelope.status] ?? -1
        guard status == 0,
              let json: String = reply[GhostscriptExtensionEnvelope.profileMetadataJSON],
              let data = json.data(using: .utf8)
        else {
            throw ConversionFailure.ghostscriptInitialization(
                returnCode: 0,
                diagnostics: "The Ghostscript extension profile catalogue is unavailable."
            )
        }
        return try JSONDecoder().decode([GhostscriptExtensionProfileMetadata].self, from: data)
    }

    func validate(joboptionsURL: URL) async throws {
        let prepared = try prepareWorkspace(inputURL: nil, joboptionsURL: joboptionsURL)
        defer { try? AppGroupWorkspace.clearConversionDirectories() }

        var request = runRequest(
            validationOnly: true,
            standard: .none,
            limitsEnabled: true,
            allowTransparency: prepared.allowTransparency,
            postScriptRandomSeed: PostScriptRandomSeedSettings.defaultManualSeed
        )
        addProfiles(prepared, to: &request)
        let reply = try await sendRun(request)
        try requireSuccess(reply, diagnostics: journalText())
    }

    func convert(
        inputURL: URL,
        outputURL: URL,
        joboptionsURL: URL,
        standard: PDFStandard,
        limitsEnabled: Bool,
        postScriptRandomSeed: Int
    ) async throws {
        if limitsEnabled {
            let inputSize = try inputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard Int64(inputSize) <= maximumInputBytes else {
                throw ConversionFailure.ghostscriptConversion(
                    returnCode: -1003,
                    diagnostics: "The input exceeds the 1 GB safety limit."
                )
            }
        }

        let prepared = try prepareWorkspace(inputURL: inputURL, joboptionsURL: joboptionsURL)
        defer { try? AppGroupWorkspace.clearConversionDirectories() }

        var request = runRequest(
            validationOnly: false,
            standard: standard,
            limitsEnabled: limitsEnabled,
            allowTransparency: prepared.allowTransparency,
            postScriptRandomSeed: postScriptRandomSeed
        )
        addProfiles(prepared, to: &request)
        let reply = try await sendRun(request)
        try requireSuccess(reply, diagnostics: journalText())
        try copyOutput(to: outputURL)

        if limitsEnabled {
            let outputSize = try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard Int64(outputSize) <= maximumOutputBytes else {
                throw ConversionFailure.ghostscriptConversion(
                    returnCode: -1002,
                    diagnostics: "The generated PDF exceeds the 2 GB safety limit."
                )
            }
        }
    }

    private func prepareWorkspace(
        inputURL: URL?,
        joboptionsURL: URL
    ) throws -> PreparedJob {
        try AppGroupWorkspace.prepareConversionDirectories()
        let inputDirectory = try AppGroupWorkspace.inputDirectoryURL()
        let joboptionsDestination = inputDirectory
            .appendingPathComponent(AppGroupWorkspace.joboptionsFileName)
        try AppGroupWorkspace.publishFile(from: joboptionsURL, to: joboptionsDestination)

        let document = try LosslessJoboptionsDocument(data: Data(contentsOf: joboptionsURL))
        let selections = inputURL == nil ? [] : selectedProfiles(document: document)
        var userProfileKeys: [String] = []

        if let inputURL {
            try AppGroupWorkspace.publishFile(
                from: inputURL,
                to: inputDirectory.appendingPathComponent(AppGroupWorkspace.inputFileName)
            )
            let profilesDirectory = inputDirectory
                .appendingPathComponent(AppGroupWorkspace.profilesDirectoryName, isDirectory: true)
            try FileManager.default.createDirectory(
                at: profilesDirectory,
                withIntermediateDirectories: true
            )
            let userProfiles = try availableUserProfiles()
            for selection in selections {
                guard let sourceURL = userProfiles.first(where: {
                    $0.deletingPathExtension().lastPathComponent
                        .caseInsensitiveCompare(selection.name) == .orderedSame
                }) else { continue }
                let destinationURL = profilesDirectory
                    .appendingPathComponent("profile-\(userProfileKeys.count).icc")
                try AppGroupWorkspace.publishFile(from: sourceURL, to: destinationURL)
                userProfileKeys.append(selection.key)
            }
        }

        try Data().write(
            to: inputDirectory.appendingPathComponent(AppGroupWorkspace.readyFileName),
            options: [.atomic]
        )
        return PreparedJob(
            allowTransparency: document.value(forKey: "AllowTransparency")?.boolValue ?? false,
            profileSelections: selections,
            userProfileKeys: userProfileKeys
        )
    }

    private func availableUserProfiles() throws -> [URL] {
        let directory = try ApplicationStorage.userProfilesDirectory()
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter {
            try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
        }
    }

    private func selectedProfiles(document: LosslessJoboptionsDocument) -> [ProfileSelection] {
        Self.profileKeys.compactMap { key in
            guard let name = document.value(forKey: key)?.textualValue,
                  !name.isEmpty,
                  name.caseInsensitiveCompare("None") != .orderedSame
            else { return nil }
            return ProfileSelection(key: key, name: name)
        }
    }

    private func runRequest(
        validationOnly: Bool,
        standard: PDFStandard,
        limitsEnabled: Bool,
        allowTransparency: Bool,
        postScriptRandomSeed: Int
    ) -> XPCDictionary {
        var request = baseRequest(operation: GhostscriptExtensionEnvelope.run)
        request[GhostscriptExtensionEnvelope.validate] = validationOnly
        request[GhostscriptExtensionEnvelope.standard] = standard.rawValue
        request[GhostscriptExtensionEnvelope.limitsEnabled] = limitsEnabled
        request[GhostscriptExtensionEnvelope.allowTransparency] = allowTransparency
        request[GhostscriptExtensionEnvelope.postScriptRandomSeed] = Int64(postScriptRandomSeed)
        request[GhostscriptExtensionEnvelope.deadline] = Int64(
            Date().addingTimeInterval(timeout).timeIntervalSince1970
        )
        request[GhostscriptExtensionEnvelope.maximumOutputBytes] = maximumOutputBytes
        return request
    }

    private func addProfiles(_ prepared: PreparedJob, to request: inout XPCDictionary) {
        request[GhostscriptExtensionEnvelope.profileSelectionCount] = Int64(
            prepared.profileSelections.count
        )
        for (index, selection) in prepared.profileSelections.enumerated() {
            request[GhostscriptExtensionEnvelope.profileSelectionKey(index)] = selection.key
            request[GhostscriptExtensionEnvelope.profileSelectionName(index)] = selection.name
        }
        request[GhostscriptExtensionEnvelope.userProfileCount] = Int64(prepared.userProfileKeys.count)
        for (index, key) in prepared.userProfileKeys.enumerated() {
            request[GhostscriptExtensionEnvelope.userProfileKey(index)] = key
        }
    }

    private func copyOutput(to destinationURL: URL) throws {
        let sourceURL = try AppGroupWorkspace.outputDirectoryURL()
            .appendingPathComponent(AppGroupWorkspace.outputFileName)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw ConversionFailure.outputMissing
        }
        try AppGroupWorkspace.publishFile(from: sourceURL, to: destinationURL)
    }

    private func journalText() -> String? {
        guard let directory = try? AppGroupWorkspace.outputDirectoryURL() else { return nil }
        let candidates = [
            directory.appendingPathComponent(AppGroupWorkspace.journalFileName),
            directory.appendingPathComponent(AppGroupWorkspace.partialJournalFileName)
        ]
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return String(decoding: data.suffix(1_048_576), as: UTF8.self)
    }

    private func sendRun(_ request: XPCDictionary) async throws -> XPCDictionary {
        do {
            return try await send(request)
        } catch let failure as ConversionFailure {
            throw failure
        } catch {
            let diagnostics = [error.localizedDescription, journalText()]
                .compactMap { value in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }
                .joined(separator: "\n")
            throw ConversionFailure.ghostscriptProcessTerminated(diagnostics: diagnostics)
        }
    }

    private func requireSuccess(_ reply: XPCDictionary, diagnostics: String?) throws {
        let status: Int64 = reply[GhostscriptExtensionEnvelope.status] ?? -1
        guard status == 0 else {
            let code = Int32(reply[GhostscriptExtensionEnvelope.ghostscriptCode] ?? status)
            let stage: Int64 = reply[GhostscriptExtensionEnvelope.stage] ?? 0
            let message: String = reply[GhostscriptExtensionEnvelope.message] ?? ""
            let details = [message, diagnostics].compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }.joined(separator: "\n")
            switch stage {
            case 1:
                throw ConversionFailure.ghostscriptInstance(returnCode: code, diagnostics: details)
            case 2:
                throw ConversionFailure.ghostscriptInitialization(returnCode: code, diagnostics: details)
            default:
                throw ConversionFailure.ghostscriptConversion(returnCode: code, diagnostics: details)
            }
        }
    }

    private func baseRequest(operation: String) -> XPCDictionary {
        var request = XPCDictionary()
        request[GhostscriptExtensionEnvelope.envelopeVersion] = GhostscriptExtensionEnvelope.version
        request[GhostscriptExtensionEnvelope.operation] = operation
        return request
    }

    private func send(_ request: XPCDictionary) async throws -> XPCDictionary {
        let serializer = GhostscriptExtensionRequestSerializer.shared
        await serializer.wait()
        do {
            let reply = try await sendUnlocked(request)
            await serializer.signal()
            return reply
        } catch {
            await serializer.signal()
            throw error
        }
    }

    private func sendUnlocked(_ request: XPCDictionary) async throws -> XPCDictionary {
        let monitor = try await AppExtensionPoint.Monitor(
            appExtensionPoint: .iPS2PDFGhostscriptHelper
        )
        guard let identity = monitor.identities.first else {
            throw ConversionFailure.ghostscriptInitialization(
                returnCode: 0,
                diagnostics: "The Ghostscript extension is unavailable."
            )
        }
        let process = try await AppExtensionProcess(
            configuration: .init(appExtensionIdentity: identity) {}
        )
        let session = try process.makeXPCSession()
        let processHandle = AppExtensionProcessHandle(process: process)
        try session.activate()
        defer {
            session.cancel(reason: "Request completed")
            processHandle.invalidate()
        }
        return try await withTaskCancellationHandler {
            let reply = try await withCheckedThrowingContinuation { continuation in
                session.send(message: request) { result in
                    switch result {
                    case .success(let reply):
                        continuation.resume(returning: SendableXPCDictionary(value: reply))
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
            return reply.value
        } onCancel: {
            session.cancel(reason: "Host task cancelled")
            processHandle.invalidate()
        }
    }

    private static let profileKeys = [
        "CalGrayProfile", "CalRGBProfile", "CalCMYKProfile", "sRGBProfile",
        "OutputICCProfile", "GraphicICCProfile", "ImageICCProfile",
        "TextICCProfile", "PDFXOutputIntentProfile"
    ]

    private struct PreparedJob {
        let allowTransparency: Bool
        let profileSelections: [ProfileSelection]
        let userProfileKeys: [String]
    }
}
