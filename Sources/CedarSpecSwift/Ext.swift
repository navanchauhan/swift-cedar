public enum Ext: Sendable {
    public struct Decimal: Equatable, Hashable, Comparable, Sendable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public struct IPAddr: Equatable, Hashable, Comparable, Sendable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public struct Datetime: Equatable, Hashable, Comparable, Sendable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public struct Duration: Equatable, Hashable, Comparable, Sendable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    case decimal(Decimal)
    case ipaddr(IPAddr)
    case datetime(Datetime)
    case duration(Duration)

}

extension Ext: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        extensionValuesEqual(lhs, rhs)
    }
}

extension Ext: Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .decimal(value):
            hasher.combine(0)
            decimalSemanticHash(value, into: &hasher)
        case let .ipaddr(value):
            hasher.combine(1)
            ipaddrSemanticHash(value, into: &hasher)
        case let .datetime(value):
            hasher.combine(2)
            datetimeSemanticHash(value, into: &hasher)
        case let .duration(value):
            hasher.combine(3)
            durationSemanticHash(value, into: &hasher)
        }
    }
}

extension Ext: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        extensionValuesLess(lhs, rhs)
    }
}
