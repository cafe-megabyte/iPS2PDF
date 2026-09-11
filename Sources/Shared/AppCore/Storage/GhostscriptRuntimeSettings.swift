import Combine
import Foundation

@MainActor
final class GhostscriptRuntimeSettings: ObservableObject {
    private enum DefaultsKey {
        static let securityLimitsEnabled = "securityLimitsEnabled"
        static let initializedSecurityLimits = "initializedSecurityLimits"
        static let automaticRandomSeed = "automaticRandomSeed"
        static let manualRandomSeed = "manualRandomSeed"
    }

    @Published var securityLimitsEnabled: Bool {
        didSet { defaults.set(securityLimitsEnabled, forKey: DefaultsKey.securityLimitsEnabled) }
    }
    @Published private(set) var automaticRandomSeed: Bool
    @Published private(set) var manualRandomSeed: Int

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.bool(forKey: DefaultsKey.initializedSecurityLimits) {
            securityLimitsEnabled = defaults.bool(forKey: DefaultsKey.securityLimitsEnabled)
        } else {
            securityLimitsEnabled = true
            defaults.set(true, forKey: DefaultsKey.initializedSecurityLimits)
            defaults.set(true, forKey: DefaultsKey.securityLimitsEnabled)
        }
        automaticRandomSeed = defaults.object(forKey: DefaultsKey.automaticRandomSeed) == nil
            ? true
            : defaults.bool(forKey: DefaultsKey.automaticRandomSeed)
        manualRandomSeed = defaults.object(forKey: DefaultsKey.manualRandomSeed) == nil
            ? PostScriptRandomSeedSettings.defaultManualSeed
            : PostScriptRandomSeedSettings.clampedSeed(
                defaults.integer(forKey: DefaultsKey.manualRandomSeed)
            )
    }

    func setAutomaticRandomSeed(_ enabled: Bool) {
        automaticRandomSeed = enabled
        defaults.set(enabled, forKey: DefaultsKey.automaticRandomSeed)
    }

    func setManualRandomSeed(_ seed: Int) {
        let clampedSeed = PostScriptRandomSeedSettings.clampedSeed(seed)
        manualRandomSeed = clampedSeed
        defaults.set(clampedSeed, forKey: DefaultsKey.manualRandomSeed)
    }

    func snapshot() -> GhostscriptRuntimeSettingsSnapshot {
        GhostscriptRuntimeSettingsSnapshot(
            securityLimitsEnabled: securityLimitsEnabled,
            postScriptRandomSeed: PostScriptRandomSeedSettings(
                usesAutomaticSeed: automaticRandomSeed,
                manualSeed: manualRandomSeed
            ).resolvedSeed
        )
    }
}
