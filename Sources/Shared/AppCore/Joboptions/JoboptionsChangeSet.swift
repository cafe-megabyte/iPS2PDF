import Foundation

struct JoboptionsChangeSet: Equatable, Sendable {
    let changes: [JoboptionsChange]

    init(_ changes: [JoboptionsChange]) {
        var byPath: [JoboptionsKeyPath: JoboptionsChange] = [:]
        var order: [JoboptionsKeyPath] = []
        for change in changes {
            if byPath[change.path] == nil { order.append(change.path) }
            byPath[change.path] = change
        }
        self.changes = order.compactMap { byPath[$0] }
    }

    var paths: [JoboptionsKeyPath] { changes.map(\.path) }
    var isEmpty: Bool { changes.isEmpty }

    func applying(to document: LosslessJoboptionsDocument) throws -> LosslessJoboptionsDocument {
        try changes.reduce(document) { current, change in
            try current.replacingValue(
                forPath: change.path,
                with: change.value,
                stringInsertionStyle: change.stringInsertionStyle
            )
        }
    }
}
