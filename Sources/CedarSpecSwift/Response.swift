public enum Decision: Int, CaseIterable, Equatable, Hashable, Comparable, Sendable {
    case allow
    case deny

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct Response: Equatable, Hashable, Sendable {
    public let decision: Decision
    public let determining: CedarSet<PolicyID>
    public let erroring: CedarSet<PolicyID>

    public init(
        decision: Decision,
        determining: CedarSet<PolicyID> = .empty,
        erroring: CedarSet<PolicyID> = .empty
    ) {
        self.decision = decision
        self.determining = determining
        self.erroring = erroring
    }
}