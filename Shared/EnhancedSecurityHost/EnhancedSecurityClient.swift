import Darwin
@preconcurrency import ExtensionFoundation
import Foundation
import XPC

final class EnhancedSecurityClient: @unchecked Sendable {
    private let maximumInputBytes: Int64 = 1_073_741_824
    private let maximumOutputBytes: Int64 = 2_147_483_648
    private let chunkSize = 64 * 1024
    private let timeout: TimeInterval = 15 * 60

    func profileMetadata() async throws -> [EnhancedSecurityProfileMetadata] {
        EnhancedSecurityHostProbeLog.log("profileMetadata request")
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
        EnhancedSecurityHostProbeLog.log("validate start joboptions=\(joboptionsURL.path)")
        let diagnosticURL = temporaryDiagnosticURL()
        defer { try? FileManager.default.removeItem(at: diagnosticURL) }
        let descriptors = try openDescriptors(
            inputURL: nil,
            outputURL: nil,
            joboptionsURL: joboptionsURL,
            diagnosticURL: diagnosticURL
        )
        defer { descriptors.closeAll() }

        try await withSession(operation: EnhancedSecurityEnvelope.validate) { session in
            EnhancedSecurityHostProbeLog.log("validate session ready")
            var begin = baseRequest(operation: EnhancedSecurityEnvelope.begin)
            begin[EnhancedSecurityEnvelope.standard] = "none"
            begin[EnhancedSecurityEnvelope.limitsEnabled] = true
            begin[EnhancedSecurityEnvelope.allowTransparency] = descriptors.allowTransparency
            begin[EnhancedSecurityEnvelope.deadline] = Int64(Date().addingTimeInterval(timeout).timeIntervalSince1970)
            begin[EnhancedSecurityEnvelope.maximumOutputBytes] = maximumOutputBytes
            begin[EnhancedSecurityEnvelope.profileSelectionCount] = Int64(0)
            begin[EnhancedSecurityEnvelope.userProfileCount] = Int64(0)
            EnhancedSecurityHostProbeLog.log("validate sending begin")
            try requireControlSuccess(try await send(begin, on: session, operation: EnhancedSecurityEnvelope.begin))
            EnhancedSecurityHostProbeLog.log("validate begin ok")

            try await appendDescriptor(
                descriptors.joboptions,
                stream: EnhancedSecurityEnvelope.joboptionsStream,
                session: session
            )

            var run = baseRequest(operation: EnhancedSecurityEnvelope.run)
            run[EnhancedSecurityEnvelope.validate] = true
            let reply = try await send(run, on: session, operation: EnhancedSecurityEnvelope.run)
            try await readRemoteFile(
                stream: EnhancedSecurityEnvelope.journalStream,
                to: diagnosticURL,
                session: session
            )
            try requireSuccess(reply, diagnosticURL: diagnosticURL)
            _ = try await send(baseRequest(operation: EnhancedSecurityEnvelope.finish), on: session, operation: EnhancedSecurityEnvelope.finish)
        }
    }

    func convert(
        inputURL: URL,
        outputURL: URL,
        joboptionsURL: URL,
        standard: PDFStandard,
        limitsEnabled: Bool,
        postScriptRandomSeed: Int
    ) async throws {
        EnhancedSecurityHostProbeLog.log("convert start input=\(inputURL.path) output=\(outputURL.path)")
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

        try await withSession(operation: EnhancedSecurityEnvelope.convert) { session in
            EnhancedSecurityHostProbeLog.log("convert session ready")
            var begin = baseRequest(operation: EnhancedSecurityEnvelope.begin)
            begin[EnhancedSecurityEnvelope.standard] = standard.rawValue
            begin[EnhancedSecurityEnvelope.limitsEnabled] = limitsEnabled
            begin[EnhancedSecurityEnvelope.allowTransparency] = descriptors.allowTransparency
            begin[EnhancedSecurityEnvelope.postScriptRandomSeed] = Int64(postScriptRandomSeed)
            begin[EnhancedSecurityEnvelope.deadline] = Int64(Date().addingTimeInterval(timeout).timeIntervalSince1970)
            begin[EnhancedSecurityEnvelope.maximumOutputBytes] = maximumOutputBytes
            begin[EnhancedSecurityEnvelope.profileSelectionCount] = Int64(descriptors.profileSelections.count)
            for (index, selection) in descriptors.profileSelections.enumerated() {
                begin[EnhancedSecurityEnvelope.profileSelectionKey(index)] = selection.key
                begin[EnhancedSecurityEnvelope.profileSelectionName(index)] = selection.name
            }
            begin[EnhancedSecurityEnvelope.userProfileCount] = Int64(descriptors.userProfiles.count)
            for (index, profile) in descriptors.userProfiles.enumerated() {
                begin[EnhancedSecurityEnvelope.userProfileKey(index)] = profile.key
            }
            EnhancedSecurityHostProbeLog.log("convert sending begin profiles=\(descriptors.userProfiles.count)")
            try requireControlSuccess(try await send(begin, on: session, operation: EnhancedSecurityEnvelope.begin))
            EnhancedSecurityHostProbeLog.log("convert begin ok")

            try await appendDescriptor(
                descriptors.joboptions,
                stream: EnhancedSecurityEnvelope.joboptionsStream,
                session: session
            )
            try await appendDescriptor(
                descriptors.input,
                stream: EnhancedSecurityEnvelope.inputStream,
                session: session
            )
            for profile in descriptors.userProfiles {
                try await appendDescriptor(
                    profile.descriptor,
                    stream: EnhancedSecurityEnvelope.userProfileStream,
                    streamKey: profile.key,
                    session: session
                )
            }

            var run = baseRequest(operation: EnhancedSecurityEnvelope.run)
            run[EnhancedSecurityEnvelope.validate] = false
            let reply = try await send(run, on: session, operation: EnhancedSecurityEnvelope.run)
            try await readRemoteFile(
                stream: EnhancedSecurityEnvelope.journalStream,
                to: diagnosticURL,
                session: session
            )
            try requireSuccess(reply, diagnosticURL: diagnosticURL)
            try await readRemoteFile(
                stream: EnhancedSecurityEnvelope.outputStream,
                to: outputURL,
                session: session
            )
            _ = try await send(baseRequest(operation: EnhancedSecurityEnvelope.finish), on: session, operation: EnhancedSecurityEnvelope.finish)
        }
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

    private func baseRequest(operation: String) -> XPCDictionary {
        var request = XPCDictionary()
        request[EnhancedSecurityEnvelope.envelopeVersion] = EnhancedSecurityEnvelope.version
        request[EnhancedSecurityEnvelope.operation] = operation
        return request
    }

    private func appendDescriptor(
        _ descriptor: Int32,
        stream: String,
        streamKey: String? = nil,
        session: XPCSession
    ) async throws {
        guard Darwin.lseek(descriptor, 0, SEEK_SET) >= 0 else {
            throw POSIXError(.EBADF)
        }
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        let bufferSize = buffer.count
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, bufferSize)
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw POSIXError(.EIO)
            }
            if count == 0 { break }

            var request = baseRequest(operation: EnhancedSecurityEnvelope.append)
            request[EnhancedSecurityEnvelope.stream] = stream
            if let streamKey {
                request[EnhancedSecurityEnvelope.userProfileKey(0)] = streamKey
            }
            XPCDataBridge.set(Data(buffer.prefix(Int(count))), forKey: EnhancedSecurityEnvelope.chunk, in: request)
            try requireControlSuccess(try await send(request, on: session, operation: EnhancedSecurityEnvelope.append))
        }
        EnhancedSecurityHostProbeLog.log("append complete stream=\(stream)")
    }

    private func readRemoteFile(
        stream: String,
        to destinationURL: URL,
        session: XPCSession
    ) async throws {
        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destinationURL)
        defer { try? handle.close() }

        var offset: Int64 = 0
        while true {
            var request = baseRequest(operation: EnhancedSecurityEnvelope.read)
            request[EnhancedSecurityEnvelope.stream] = stream
            request[EnhancedSecurityEnvelope.offset] = offset
            request[EnhancedSecurityEnvelope.length] = Int64(chunkSize)
            let reply = try await send(request, on: session, operation: EnhancedSecurityEnvelope.read)
            try requireControlSuccess(reply)
            let data = XPCDataBridge.data(forKey: EnhancedSecurityEnvelope.chunk, from: reply) ?? Data()
            if !data.isEmpty {
                try handle.write(contentsOf: data)
                offset += Int64(data.count)
            }
            let hasMore: Bool = reply[EnhancedSecurityEnvelope.hasMore] ?? false
            if !hasMore { break }
        }
        try handle.synchronize()
    }

    private func requireControlSuccess(_ reply: XPCDictionary) throws {
        let status: Int64 = reply[EnhancedSecurityEnvelope.status] ?? -1
        guard status == 0 else {
            let message: String = reply[EnhancedSecurityEnvelope.message] ?? "Enhanced Security helper request failed."
            throw ConversionFailure.ghostscriptConversion(returnCode: Int32(status), diagnostics: message)
        }
    }

    private func send(_ request: XPCDictionary) async throws -> XPCDictionary {
        let operation: String = request[EnhancedSecurityEnvelope.operation] ?? "<missing>"
        let serializer = EnhancedSecurityRequestSerializer.shared
        await serializer.wait()
        do {
            let reply = try await sendUnlocked(request, operation: operation)
            await serializer.signal()
            return reply
        } catch {
            await serializer.signal()
            throw error
        }
    }

    private func withSession<Result>(
        operation: String,
        _ body: (XPCSession) async throws -> Result
    ) async throws -> Result {
        let serializer = EnhancedSecurityRequestSerializer.shared
        await serializer.wait()
        do {
            let result = try await withSessionUnlocked(operation: operation, body)
            await serializer.signal()
            return result
        } catch {
            EnhancedSecurityHostProbeLog.log("session failed operation=\(operation) error=\(error)")
            await serializer.signal()
            throw error
        }
    }

    private func withSessionUnlocked<Result>(
        operation: String,
        _ body: (XPCSession) async throws -> Result
    ) async throws -> Result {
        EnhancedSecurityHostProbeLog.log("starting helper session operation=\(operation)")
        let monitor = try await AppExtensionPoint.Monitor(appExtensionPoint: .iPS2PDFGhostscriptHelper)
        EnhancedSecurityHostProbeLog.log("monitor identities count=\(monitor.identities.count) operation=\(operation)")
        guard let identity = monitor.identities.first else {
            throw ConversionFailure.ghostscriptInitialization(
                returnCode: 0,
                diagnostics: "The Enhanced Security helper is unavailable."
            )
        }
        let process = try await AppExtensionProcess(
            configuration: .init(appExtensionIdentity: identity) {
                EnhancedSecurityHostProbeLog.log("helper interrupted operation=\(operation)")
            }
        )
        let session = try process.makeXPCSession()
        let processHandle = AppExtensionProcessHandle(process: process)
        try session.activate()
        EnhancedSecurityHostProbeLog.log("helper session activated operation=\(operation)")
        defer {
            EnhancedSecurityHostProbeLog.log("helper session cancelling operation=\(operation)")
            session.cancel(reason: "Request completed")
            processHandle.invalidate()
        }
        return try await withTaskCancellationHandler {
            try await body(session)
        } onCancel: {
            session.cancel(reason: "Host task cancelled")
            processHandle.invalidate()
        }
    }

    private func send(
        _ request: XPCDictionary,
        on session: XPCSession,
        operation: String
    ) async throws -> XPCDictionary {
        let reply = try await withCheckedThrowingContinuation { continuation in
            session.send(message: request) { result in
                switch result {
                case .success(let reply):
                    let status: Int64 = reply[EnhancedSecurityEnvelope.status] ?? Int64.min
                    let message: String = reply[EnhancedSecurityEnvelope.message] ?? "<nil>"
                    EnhancedSecurityHostProbeLog.log("reply operation=\(operation) status=\(status) message=\(message)")
                    continuation.resume(returning: SendableXPCDictionary(value: reply))
                case .failure(let error):
                    EnhancedSecurityHostProbeLog.log("reply failed operation=\(operation) error=\(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
        return reply.value
    }

    private func sendUnlocked(_ request: XPCDictionary, operation: String) async throws -> XPCDictionary {
        EnhancedSecurityHostProbeLog.log("sendUnlocked operation=\(operation)")
        let monitor = try await AppExtensionPoint.Monitor(appExtensionPoint: .iPS2PDFGhostscriptHelper)
        EnhancedSecurityHostProbeLog.log("sendUnlocked monitor identities count=\(monitor.identities.count) operation=\(operation)")
        guard let identity = monitor.identities.first else {
            throw ConversionFailure.ghostscriptInitialization(
                returnCode: 0,
                diagnostics: "The Enhanced Security helper is unavailable."
            )
        }
        let process = try await AppExtensionProcess(
            configuration: .init(appExtensionIdentity: identity) {
                EnhancedSecurityHostProbeLog.log("helper interrupted operation=\(operation)")
            }
        )
        let session = try process.makeXPCSession()
        let processHandle = AppExtensionProcessHandle(process: process)
        try session.activate()
        defer {
            EnhancedSecurityHostProbeLog.log("sendUnlocked cancelling operation=\(operation)")
            session.cancel(reason: "Request completed")
            processHandle.invalidate()
        }
        return try await withTaskCancellationHandler {
            let reply = try await withCheckedThrowingContinuation { continuation in
                session.send(message: request) { result in
                    switch result {
                    case .success(let reply):
                        let status: Int64 = reply[EnhancedSecurityEnvelope.status] ?? Int64.min
                        let message: String = reply[EnhancedSecurityEnvelope.message] ?? "<nil>"
                        EnhancedSecurityHostProbeLog.log("sendUnlocked reply operation=\(operation) status=\(status) message=\(message)")
                        continuation.resume(returning: SendableXPCDictionary(value: reply))
                    case .failure(let error):
                        EnhancedSecurityHostProbeLog.log("sendUnlocked reply failed operation=\(operation) error=\(error)")
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
