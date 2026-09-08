import Foundation

struct JoboptionsConsistencyIssueIndex: Sendable {
    private let affectedPaths: Set<JoboptionsKeyPath>

    init(_ issues: [JoboptionsConsistencyIssue]) {
        affectedPaths = Set(issues.map(\.path))
    }

    func affects(_ path: JoboptionsKeyPath) -> Bool {
        affectedPaths.contains(path)
    }

    func affects(any paths: [JoboptionsKeyPath]) -> Bool {
        paths.contains(where: affectedPaths.contains)
    }
}
