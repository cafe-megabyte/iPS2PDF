import Darwin
import ExtensionFoundation
import Foundation
import XPC

// ExtensionFoundation may overlap helper processes; Ghostscript work must stay one request at a time.
private actor EnhancedSecurityRequestSerializer {
    static let shared = EnhancedSecurityRequestSerializer()
    private var isAvailable = true
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run<T>(_ operation: () async throws -> T) async throws -> T {
        await wait()
        do {
            let result = try await operation()
            signal()
            return result
        } catch {
            signal()
            throw error
        }
    }

    private func wait() async {
        if isAvailable {
            isAvailable = false
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func signal() {
        if waiters.isEmpty {
            isAvailable = true
        } else {
            waiters.removeFirst().resume()
        }
    }
}

final class EnhancedSecurityClient: @unchecked Sendable {
    private let maximumInputBytes: Int64 = 1_073_741_824
    private let maximumOutputBytes: Int64 = 2_147_483_648
    private let timeout: TimeInterval = 15 * 60

    func profileMetadata() async throws -> [EnhancedSecurityProfileMetadata] {
        var request = XPCDictionary()
        request[EnhancedSecurityEnvelope.envelopeVersion] = EnhancedSecurityEnvelope.version
        request[EnhancedSecurityEnvelope.operation] = EnhancedSecurityEnvelope.profiles
        let reply = try await send(request)
        let status: Int64 = reply[EnhancedSecurityEnvelope.status] ?? -1
        guard status == 0,
              let json: String = reply[EnhancedSecurityEnvelope.profileMetadataJSON],
              let data = json.data(using: .utf8)
        else {
            throw ConversionFailure.ghostscriptInitialization(
                returnCode: 0,
                diagnostics: "The helper profile catalogue is unavailable."
            )
        }
        return try JSONDecoder().decode([EnhancedSecurityProfileMetadata].self, from: data)
    }

    func validate(joboptionsURL: URL) async throws {
        let diagnosticURL = temporaryDiagnosticURL()
        defer { try? FileManager.default.removeItem(at: diagnosticURL) }
        let descriptors = try openDescriptors(
            inputURL: nil,
            outputURL: nil,
            joboptionsURL: joboptionsURL,
            diagnosticURL: diagnosticURL
        )
        defer { descriptors.closeAll() }

        var request = XPCDictionary()
        request[EnhancedSecurityEnvelope.envelopeVersion] = EnhancedSecurityEnvelope.version
        request[EnhancedSecurityEnvelope.operation] = EnhancedSecurityEnvelope.validate
        request[EnhancedSecurityEnvelope.allowTransparency] = descriptors.allowTransparency
        XPCDescriptorBridge.set(descriptors.joboptions, forKey: EnhancedSecurityEnvelope.joboptionsFD, in: request)
        XPCDescriptorBridge.set(descriptors.journal, forKey: EnhancedSecurityEnvelope.journalFD, in: request)
        let reply = try await send(request)
        try requireSuccess(reply, diagnosticURL: diagnosticURL)
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
            guard inputSize <= maximumInputBytes else {
                throw ConversionFailure.ghostscriptConversion(
                    returnCode: -1003,
                    diagnostics: "The PostScript input exceeds the 1 GB safety limit."
                )
            }
        }

        let diagnosticURL = temporaryDiagnosticURL()
        defer { try? FileManager.default.removeItem(at: diagnosticURL) }
        let descriptors = try openDescriptors(
            inputURL: inputURL,
            outputURL: outputURL,
            joboptionsURL: joboptionsURL,
            diagnosticURL: diagnosticURL
        )
        defer { descriptors.closeAll() }

        var request = XPCDictionary()
        request[EnhancedSecurityEnvelope.envelopeVersion] = EnhancedSecurityEnvelope.version
        request[EnhancedSecurityEnvelope.operation] = EnhancedSecurityEnvelope.convert
        request[EnhancedSecurityEnvelope.limitsEnabled] = limitsEnabled
        request[EnhancedSecurityEnvelope.allowTransparency] = descriptors.allowTransparency
        request[EnhancedSecurityEnvelope.standard] = standard.rawValue
        request[EnhancedSecurityEnvelope.postScriptRandomSeed] = Int64(postScriptRandomSeed)
        request[EnhancedSecurityEnvelope.deadline] = Int64(Date().addingTimeInterval(timeout).timeIntervalSince1970)
        request[EnhancedSecurityEnvelope.maximumOutputBytes] = maximumOutputBytes
        XPCDescriptorBridge.set(descriptors.joboptions, forKey: EnhancedSecurityEnvelope.joboptionsFD, in: request)
        XPCDescriptorBridge.set(descriptors.input, forKey: EnhancedSecurityEnvelope.inputFD, in: request)
        XPCDescriptorBridge.set(descriptors.output, forKey: EnhancedSecurityEnvelope.outputFD, in: request)
        XPCDescriptorBridge.set(descriptors.journal, forKey: EnhancedSecurityEnvelope.journalFD, in: request)
        request[EnhancedSecurityEnvelope.profileSelectionCount] = Int64(descriptors.profileSelections.count)
        for (index, selection) in descriptors.profileSelections.enumerated() {
            request[EnhancedSecurityEnvelope.profileSelectionKey(index)] = selection.key
            request[EnhancedSecurityEnvelope.profileSelectionName(index)] = selection.name
        }
        request[EnhancedSecurityEnvelope.userProfileCount] = Int64(descriptors.userProfiles.count)
        for (index, profile) in descriptors.userProfiles.enumerated() {
            request[EnhancedSecurityEnvelope.userProfileKey(index)] = profile.key
            XPCDescriptorBridge.set(
                profile.descriptor,
                forKey: EnhancedSecurityEnvelope.userProfileFD(index),
                in: request
            )
        }

        let reply = try await send(request)
        try requireSuccess(reply, diagnosticURL: diagnosticURL)
        if limitsEnabled {
            let outputSize = try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard outputSize <= maximumOutputBytes else {
                throw ConversionFailure.ghostscriptConversion(
                    returnCode: -1002,
                    diagnostics: "The generated PDF exceeds the 2 GB safety limit."
                )
            }
        }
    }

    private func send(_ request: XPCDictionary) async throws -> XPCDictionary {
        let operation: String = request[EnhancedSecurityEnvelope.operation] ?? "<missing>"
        return try await EnhancedSecurityRequestSerializer.shared.run {
            try await sendUnlocked(request, operation: operation)
        }
    }

    private func sendUnlocked(_ request: XPCDictionary, operation: String) async throws -> XPCDictionary {
        let monitor = try await AppExtensionPoint.Monitor(appExtensionPoint: .iPS2PDFEnhancedSecurity)
        guard let identity = monitor.identities.first else {
            throw ConversionFailure.ghostscriptInitialization(
                returnCode: 0,
                diagnostics: "The Enhanced Security helper is unavailable."
            )
        }
        let process = try await AppExtensionProcess(
            configuration: .init(appExtensionIdentity: identity)
        )
        let session = try process.makeXPCSession()
        try session.activate()
        defer {
            session.cancel(reason: "Request completed")
            process.invalidate()
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                session.send(message: request) { result in
                    continuation.resume(with: result.mapError { $0 as Error })
                }
            }
        } onCancel: {
            session.cancel(reason: "Host task cancelled")
            process.invalidate()
        }
    }

    private func requireSuccess(_ reply: XPCDictionary, diagnosticURL: URL) throws {
        let status: Int64 = reply[EnhancedSecurityEnvelope.status] ?? -1
        guard status == 0 else {
            let code: Int32 = Int32(reply[EnhancedSecurityEnvelope.ghostscriptCode] ?? Int64(status))
            let stage: Int64 = reply[EnhancedSecurityEnvelope.stage] ?? 0
            let journal = (try? Data(contentsOf: diagnosticURL))
                .map { Data($0.suffix(1_048_576)) }
                .map { String(decoding: $0, as: UTF8.self) }
            let message: String = reply[EnhancedSecurityEnvelope.message] ?? ""
            let details = [message, journal].compactMap { value in
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

    private func temporaryDiagnosticURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("iPS2PDF-\(UUID().uuidString).log")
    }

    private func openDescriptors(
        inputURL: URL?,
        outputURL: URL?,
        joboptionsURL: URL,
        diagnosticURL: URL
    ) throws -> OpenDescriptors {
        let joboptions = Darwin.open(joboptionsURL.path, O_RDONLY | O_CLOEXEC)
        guard joboptions >= 0 else { throw POSIXError(.EBADF) }
        let journal = Darwin.open(diagnosticURL.path, O_RDWR | O_CREAT | O_TRUNC | O_CLOEXEC, 0o600)
        guard journal >= 0 else {
            Darwin.close(joboptions)
            throw POSIXError(.EBADF)
        }
        var input: Int32 = -1
        var output: Int32 = -1
        if let inputURL {
            input = Darwin.open(inputURL.path, O_RDONLY | O_CLOEXEC)
        }
        if let outputURL {
            output = Darwin.open(outputURL.path, O_RDWR | O_CREAT | O_TRUNC | O_CLOEXEC, 0o600)
        }
        guard inputURL == nil || input >= 0, outputURL == nil || output >= 0 else {
            [input, output, joboptions, journal].filter { $0 >= 0 }.forEach { Darwin.close($0) }
            throw POSIXError(.EBADF)
        }
        var userProfiles: [OpenUserProfile] = []
        var profileSelections: [ProfileSelection] = []
        let document: LosslessJoboptionsDocument
        do {
            document = try LosslessJoboptionsDocument(data: Data(contentsOf: joboptionsURL))
            if inputURL != nil {
                profileSelections = selectedProfiles(document: document)
                userProfiles = try openSelectedUserProfiles(document: document)
            }
        } catch {
            [input, output, joboptions, journal].filter { $0 >= 0 }.forEach { Darwin.close($0) }
            throw error
        }
        return OpenDescriptors(
            input: input,
            output: output,
            joboptions: joboptions,
            journal: journal,
            allowTransparency: document.value(forKey: "AllowTransparency")?.boolValue ?? false,
            profileSelections: profileSelections,
            userProfiles: userProfiles
        )
    }

    private func selectedProfiles(document: LosslessJoboptionsDocument) -> [ProfileSelection] {
        return Self.profileKeys.compactMap { key in
            guard let name = document.value(forKey: key)?.textualValue,
                  !name.isEmpty,
                  name.caseInsensitiveCompare("None") != .orderedSame
            else { return nil }
            return ProfileSelection(key: key, name: name)
        }
    }

    private func openSelectedUserProfiles(document: LosslessJoboptionsDocument) throws -> [OpenUserProfile] {
        let directory = try AppGroup.containerURL().appendingPathComponent("Profiles", isDirectory: true)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        var selected: [OpenUserProfile] = []
        for key in Self.profileKeys {
            guard let value = document.value(forKey: key)?.textualValue,
                  let url = urls.first(where: {
                      $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(value) == .orderedSame
                  })
            else { continue }
            let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC)
            guard descriptor >= 0 else {
                selected.forEach { Darwin.close($0.descriptor) }
                throw POSIXError(.EBADF)
            }
            selected.append(.init(key: key, descriptor: descriptor))
        }
        return selected
    }

    private static let profileKeys = [
        "CalGrayProfile", "CalRGBProfile", "CalCMYKProfile", "sRGBProfile",
        "OutputICCProfile", "GraphicICCProfile", "ImageICCProfile",
        "TextICCProfile", "PDFXOutputIntentProfile"
    ]
}
