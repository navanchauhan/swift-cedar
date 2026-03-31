public enum PatElem: Equatable, Comparable, Sendable {
    case wildcard
    case literal(Unicode.Scalar)

    private var constructorRank: Int {
        switch self {
        case .wildcard:
            0
        case .literal:
            1
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.constructorRank != rhs.constructorRank {
            return lhs.constructorRank < rhs.constructorRank
        }

        switch (lhs, rhs) {
        case let (.literal(left), .literal(right)):
            return left.value < right.value
        default:
            return false
        }
    }
}

public struct Pattern: Equatable, Comparable, Sendable {
    public let elements: [PatElem]

    public init(_ elements: [PatElem]) {
        self.elements = elements
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        patElemArrayLess(lhs.elements, rhs.elements)
    }
}

public func wildcardMatch(_ pattern: Pattern, value: [Unicode.Scalar]) -> Bool {
    let elements = pattern.elements
    var matches = Array(
        repeating: Array(repeating: false, count: value.count + 1),
        count: elements.count + 1
    )
    matches[0][0] = true

    if !elements.isEmpty {
        for patternIndex in 1...elements.count {
            if case .wildcard = elements[patternIndex - 1] {
                matches[patternIndex][0] = matches[patternIndex - 1][0]
            }
        }
    }

    if !elements.isEmpty, !value.isEmpty {
        for patternIndex in 1...elements.count {
            for valueIndex in 1...value.count {
                switch elements[patternIndex - 1] {
                case .wildcard:
                    matches[patternIndex][valueIndex] =
                        matches[patternIndex - 1][valueIndex]
                        || matches[patternIndex][valueIndex - 1]
                case let .literal(expected):
                    matches[patternIndex][valueIndex] =
                        matches[patternIndex - 1][valueIndex - 1]
                        && expected == value[valueIndex - 1]
                }
            }
        }
    }

    return matches[elements.count][value.count]
}

private func patElemArrayLess(_ lhs: [PatElem], _ rhs: [PatElem]) -> Bool {
    var index = 0

    while index < lhs.count, index < rhs.count {
        let left = lhs[index]
        let right = rhs[index]

        if left < right {
            return true
        }

        if right < left {
            return false
        }

        index += 1
    }

    return lhs.count < rhs.count
}