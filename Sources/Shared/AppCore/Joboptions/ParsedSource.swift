import Foundation

struct ParsedSource: Sendable {
    var occurrences: [LosslessJoboptionsDocument.Occurrence] = []
    var primaryDictionaryClosingUnit: Int?
    var dictionaryClosingUnits: [JoboptionsKeyPath: Int] = [:]
    var unclassifiedFragments: [Range<Int>] = []
}
