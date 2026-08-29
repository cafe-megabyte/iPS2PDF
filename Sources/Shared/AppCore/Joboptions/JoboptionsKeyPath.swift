import Foundation

struct JoboptionsKeyPath: Hashable, Sendable, Comparable, CustomStringConvertible {
    let components: [String]

    init(_ components: [String]) {
        self.components = components.map(Self.normalizedComponent)
    }

    init(_ postScriptPath: String) {
        components = postScriptPath
            .split(whereSeparator: { $0 == "/" || $0.isWhitespace })
            .map { Self.normalizedComponent(String($0)) }
    }

    init(key: String) {
        self.init([key])
    }

    var description: String {
        components.map { "/\($0)" }.joined(separator: " ")
    }

    var key: String? { components.last }
    var parent: Self { Self(Array(components.dropLast())) }
    var isRoot: Bool { components.isEmpty }

    func appending(_ key: String) -> Self {
        Self(components + [key])
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.description < rhs.description
    }

    private static func normalizedComponent(_ component: String) -> String {
        component.hasPrefix("/") ? String(component.dropFirst()) : component
    }
}
