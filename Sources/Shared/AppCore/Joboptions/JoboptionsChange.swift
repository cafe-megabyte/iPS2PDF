import Foundation

struct JoboptionsChange: Equatable, Sendable {
    let path: JoboptionsKeyPath
    let value: JoboptionsValue
    let stringInsertionStyle: LosslessJoboptionsDocument.StringInsertionStyle

    init(
        _ path: String,
        _ value: JoboptionsValue,
        stringInsertionStyle: LosslessJoboptionsDocument.StringInsertionStyle = .automatic
    ) {
        self.path = JoboptionsKeyPath(path)
        self.value = value
        self.stringInsertionStyle = stringInsertionStyle
    }
}
