public struct SourceLocation: Hashable, Sendable {
    public let line: Int
    public let column: Int
    public let offset: Int

    public init(line: Int, column: Int, offset: Int) {
        self.line = line
        self.column = column
        self.offset = offset
    }
}

extension SourceLocation: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.line != rhs.line {
            return lhs.line < rhs.line
        }

        if lhs.column != rhs.column {
            return lhs.column < rhs.column
        }

        return lhs.offset < rhs.offset
    }
}

public struct SourceSpan: Sendable {
    public let start: SourceLocation
    public let end: SourceLocation
    public let source: String?

    public init(start: SourceLocation, end: SourceLocation, source: String? = nil) {
        self.start = start
        self.end = end
        self.source = source
    }
}

extension SourceSpan: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.start == rhs.start
            && lhs.end == rhs.end
            && optionalCedarStringEqual(lhs.source, rhs.source)
    }
}

extension SourceSpan: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(start)
        hasher.combine(end)

        switch source {
        case let .some(source):
            hasher.combine(true)
            cedarHashString(source, into: &hasher)
        case .none:
            hasher.combine(false)
        }
    }
}

extension SourceSpan: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if optionalCedarStringLess(lhs.source, rhs.source) {
            return true
        }

        if optionalCedarStringLess(rhs.source, lhs.source) {
            return false
        }

        if lhs.start != rhs.start {
            return lhs.start < rhs.start
        }

        return lhs.end < rhs.end
    }
}

@inline(__always)
private func optionalCedarStringEqual(_ lhs: String?, _ rhs: String?) -> Bool {
    switch (lhs, rhs) {
    case (.none, .none):
        return true
    case let (.some(left), .some(right)):
        return cedarStringEqual(left, right)
    default:
        return false
    }
}

@inline(__always)
private func optionalCedarStringLess(_ lhs: String?, _ rhs: String?) -> Bool {
    switch (lhs, rhs) {
    case let (.some(left), .some(right)):
        return cedarStringLess(left, right)
    case (.some, .none):
        return true
    case (.none, .some):
        return false
    case (.none, .none):
        return false
    }
}