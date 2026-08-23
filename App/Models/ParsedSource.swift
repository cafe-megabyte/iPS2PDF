import Foundation

struct ParsedSource: Sendable {
    var occurrences: [LosslessJoboptionsDocument.Occurrence] = []
    var primaryDictionaryClosingUnit: Int?
    var unclassifiedFragments: [Range<Int>] = []
}
