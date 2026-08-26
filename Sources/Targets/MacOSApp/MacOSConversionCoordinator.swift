import Foundation

actor MacOSConversionCoordinator {
    private let client = GhostscriptExtensionClient()
    private var ownsWorkspace = false
    private var workspaceWaiters: [CheckedContinuation<Void, Never>] = []

    func convert(
        inputURL: URL,
        outputURL: URL,
        joboptionsURL: URL,
        settings: ConversionSettingsSnapshot
    ) async throws {
        await acquireWorkspace()
        defer { releaseWorkspace() }
        try await client.convert(
            inputURL: inputURL,
            outputURL: outputURL,
            joboptionsURL: joboptionsURL,
            standard: settings.standard,
            limitsEnabled: settings.securityLimitsEnabled,
            postScriptRandomSeed: settings.postScriptRandomSeed
        )
    }

    func validate(joboptionsURL: URL) async throws {
        await acquireWorkspace()
        defer { releaseWorkspace() }
        try await client.validate(joboptionsURL: joboptionsURL)
    }

    private func acquireWorkspace() async {
        if !ownsWorkspace {
            ownsWorkspace = true
            return
        }
        await withCheckedContinuation { continuation in
            workspaceWaiters.append(continuation)
        }
    }

    private func releaseWorkspace() {
        if workspaceWaiters.isEmpty {
            ownsWorkspace = false
        } else {
            workspaceWaiters.removeFirst().resume()
        }
    }
}
