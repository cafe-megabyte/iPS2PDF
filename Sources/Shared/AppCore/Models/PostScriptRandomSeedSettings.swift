import Foundation

struct PostScriptRandomSeedSettings: Sendable, Equatable {
    static let range = 0...2_147_483_647
    static let defaultManualSeed = 1

    let usesAutomaticSeed: Bool
    let manualSeed: Int

    var resolvedSeed: Int {
        usesAutomaticSeed ? Int.random(in: Self.range) : manualSeed
    }

    init(usesAutomaticSeed: Bool = true, manualSeed: Int = Self.defaultManualSeed) {
        self.usesAutomaticSeed = usesAutomaticSeed
        self.manualSeed = Self.clampedSeed(manualSeed)
    }

    static func clampedSeed(_ seed: Int) -> Int {
        min(max(seed, range.lowerBound), range.upperBound)
    }
}
