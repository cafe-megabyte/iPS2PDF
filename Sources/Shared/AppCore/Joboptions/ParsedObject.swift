import Foundation

struct ParsedObject {
    let value: JoboptionsValue
    let unitRange: Range<Int>
    let dictionaryClosingUnit: Int?
    let stringRepresentation: PostScriptStringCodec.Representation?

    init(
        value: JoboptionsValue,
        unitRange: Range<Int>,
        dictionaryClosingUnit: Int?,
        stringRepresentation: PostScriptStringCodec.Representation? = nil
    ) {
        self.value = value
        self.unitRange = unitRange
        self.dictionaryClosingUnit = dictionaryClosingUnit
        self.stringRepresentation = stringRepresentation
    }
}
