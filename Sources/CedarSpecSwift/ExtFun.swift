public enum ExtFun: Int, CaseIterable, Equatable, Hashable, Comparable, Sendable {
    case decimal
    case lessThan
    case lessThanOrEqual
    case greaterThan
    case greaterThanOrEqual
    case ip
    case isIpv4
    case isIpv6
    case isLoopback
    case isMulticast
    case isInRange
    case datetime
    case duration
    case offset
    case durationSince
    case toDate
    case toTime
    case toMilliseconds
    case toSeconds
    case toMinutes
    case toHours
    case toDays

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}