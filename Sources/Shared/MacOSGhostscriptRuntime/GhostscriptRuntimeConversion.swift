import Darwin
import Foundation
import GhostscriptRuntime

enum GhostscriptRuntimeConversion {
    enum PageSelection {
        case all
        case first
    }

    enum Failure: LocalizedError {
        case inputTooLarge
        case fileAccess(String)
        case missingResource(String)
        case conversion(returnCode: Int32, stage: Int32, diagnostics: String)

        var errorDescription: String? {
            switch self {
            case .inputTooLarge:
                "The input exceeds the Quick Look size limit."
            case .fileAccess(let details):
                details
            case .missingResource(let name):
                "The bundled resource \(name) is unavailable."
            case .conversion(let returnCode, let stage, let diagnostics):
                "Ghostscript failed with code \(returnCode) during stage \(stage).\n\(diagnostics)"
            }
        }
    }

    static func convert(
        inputURL: URL,
        outputURL: URL,
        joboptionsURL: URL,
        pageSelection: PageSelection
    ) throws {
        let inputSize = try inputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard inputSize <= 1_073_741_824 else { throw Failure.inputTooLarge }

        let joboptionsData = try Data(contentsOf: joboptionsURL, options: [.mappedIfSafe])
        let document = try LosslessJoboptionsDocument(data: joboptionsData)
        guard let ghostscriptDirectory = GhostscriptRuntimeResources.ghostscriptDirectoryURL else {
            throw Failure.missingResource("Ghostscript")
        }
        guard let profilesDirectory = GhostscriptRuntimeResources.profilesDirectoryURL else {
            throw Failure.missingResource("Profiles")
        }
        let profileOverrides = try profileOverrides(
            document: document,
            profilesDirectory: profilesDirectory
        )

        let journalURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent("Ghostscript.log")
        var input = try openRegularFile(at: inputURL, flags: O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        var output = try openRegularFile(
            at: outputURL,
            flags: O_RDWR | O_CREAT | O_TRUNC | O_CLOEXEC | O_NOFOLLOW,
            mode: 0o600
        )
        var joboptions = try openRegularFile(
            at: joboptionsURL,
            flags: O_RDONLY | O_CLOEXEC | O_NOFOLLOW
        )
        var journal = try openRegularFile(
            at: journalURL,
            flags: O_RDWR | O_CREAT | O_TRUNC | O_CLOEXEC | O_NOFOLLOW,
            mode: 0o600
        )
        defer {
            [input, output, joboptions, journal]
                .filter { $0 >= 0 }
                .forEach { Darwin.close($0) }
        }

        let compatibilityLevel = allowedCompatibilityLevels.contains(
            document.value(forKey: "CompatibilityLevel")?.textualValue ?? ""
        ) ? document.value(forKey: "CompatibilityLevel")?.textualValue : nil
        let blendConversionStrategy = allowedBlendConversionStrategies.contains(
            document.value(forKey: "BlendConversionStrategy")?.textualValue ?? ""
        ) ? document.value(forKey: "BlendConversionStrategy")?.textualValue : nil
        let allowTransparency = document.value(forKey: "AllowTransparency")?.boolValue == true
        let epsCrop = document.value(forKey: "AutoPositionEPSFiles")?.boolValue == true
        let lastPage: Int32 = pageSelection == .first ? 1 : 0
        let timeout: TimeInterval = pageSelection == .first ? 20 : 60
        let maximumOutput: Int64 = pageSelection == .first ? 67_108_864 : 536_870_912

        var ghostscriptCode: Int32 = 0
        var stage: Int32 = 0
        gs_bridge_reset_cancellation()
        let status = "none".withCString { standardPointer in
            withOptionalCString(compatibilityLevel) { compatibilityPointer in
                withOptionalPath(ghostscriptDirectory) { ghostscriptPointer in
                    withOptionalPath(profilesDirectory) { profileDirectoryPointer in
                        withOptionalCString(profileOverrides) { profileOverridesPointer in
                            withOptionalCString(blendConversionStrategy) { blendPointer in
                                gs_run_joboptions_with_fds(
                                    input,
                                    output,
                                    joboptions,
                                    journal,
                                    0,
                                    allowTransparency ? 1 : 0,
                                    epsCrop ? 1 : 0,
                                    pageSelection == .first ? 1 : 0,
                                    lastPage,
                                    compatibilityPointer,
                                    standardPointer,
                                    nil,
                                    ghostscriptPointer,
                                    profileDirectoryPointer,
                                    profileOverridesPointer,
                                    nil,
                                    blendPointer,
                                    1,
                                    1,
                                    Int64(Date().addingTimeInterval(timeout).timeIntervalSince1970),
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

        [input, output, joboptions, journal]
            .filter { $0 >= 0 }
            .forEach { Darwin.close($0) }
        input = -1
        output = -1
        joboptions = -1
        journal = -1

        guard status == 0 else {
            let diagnostics = (try? String(contentsOf: journalURL, encoding: .utf8)) ?? ""
            throw Failure.conversion(
                returnCode: ghostscriptCode,
                stage: stage,
                diagnostics: diagnostics
            )
        }
    }

    private static func profileOverrides(
        document: LosslessJoboptionsDocument,
        profilesDirectory: URL
    ) throws -> String? {
        let resolver = try GhostscriptProfileResolver(directoryURL: profilesDirectory)
        let entries = try profileKeys.compactMap { key -> String? in
            guard let name = document.value(forKey: key)?.textualValue,
                  !name.isEmpty,
                  name.caseInsensitiveCompare("None") != .orderedSame
            else { return nil }
            let url = try resolver.resolve(name)
            return "/\(key) (\(postScriptLiteral(url.path)))"
        }
        guard !entries.isEmpty else { return nil }
        return "<< \(entries.joined(separator: " ")) >> setdistillerparams"
    }

    private static func openRegularFile(
        at url: URL,
        flags: Int32,
        mode: mode_t? = nil
    ) throws -> Int32 {
        let descriptor = mode.map { Darwin.open(url.path, flags, $0) }
            ?? Darwin.open(url.path, flags)
        guard descriptor >= 0 else {
            throw Failure.fileAccess(
                "Could not open \(url.lastPathComponent): \(String(cString: strerror(errno)))."
            )
        }

        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0 else {
            Darwin.close(descriptor)
            throw Failure.fileAccess(
                "Could not inspect \(url.lastPathComponent): \(String(cString: strerror(errno)))."
            )
        }
        guard metadata.st_mode & S_IFMT == S_IFREG else {
            Darwin.close(descriptor)
            throw Failure.fileAccess("The file \(url.lastPathComponent) is not a regular file.")
        }
        return descriptor
    }

    private static func postScriptLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
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

    private static let profileKeys = [
        "CalGrayProfile", "CalRGBProfile", "CalCMYKProfile", "sRGBProfile",
        "OutputICCProfile", "GraphicICCProfile", "ImageICCProfile",
        "TextICCProfile", "PDFXOutputIntentProfile"
    ]

    private static let allowedCompatibilityLevels = Set([
        "1.1", "1.2", "1.3", "1.4", "1.5", "1.6", "1.7", "2.0"
    ])

    private static let allowedBlendConversionStrategies = Set([
        "None", "Simple", "Managed"
    ])
}
