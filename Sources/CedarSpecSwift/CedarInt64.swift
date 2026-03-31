public enum CedarInt64 {
    public static let MIN = Int64.min
    public static let MAX = Int64.max

    public static func add(_ lhs: Int64, _ rhs: Int64) -> Int64? {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? nil : result
    }

    public static func sub(_ lhs: Int64, _ rhs: Int64) -> Int64? {
        let (result, overflow) = lhs.subtractingReportingOverflow(rhs)
        return overflow ? nil : result
    }

    public static func mul(_ lhs: Int64, _ rhs: Int64) -> Int64? {
        let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        return overflow ? nil : result
    }

    public static func neg(_ value: Int64) -> Int64? {
        let (result, overflow) = Int64.zero.subtractingReportingOverflow(value)
        return overflow ? nil : result
    }
}
