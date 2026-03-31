@inline(__always)
func cedarStringEqual(_ lhs: String, _ rhs: String) -> Bool {
    var lhsIterator = lhs.unicodeScalars.makeIterator()
    var rhsIterator = rhs.unicodeScalars.makeIterator()

    while true {
        switch (lhsIterator.next(), rhsIterator.next()) {
        case (nil, nil):
            return true
        case (nil, _), (_, nil):
            return false
        case let (left?, right?):
            if left != right {
                return false
            }
        }
    }
}

@inline(__always)
func cedarStringLess(_ lhs: String, _ rhs: String) -> Bool {
    var lhsIterator = lhs.unicodeScalars.makeIterator()
    var rhsIterator = rhs.unicodeScalars.makeIterator()

    while true {
        switch (lhsIterator.next(), rhsIterator.next()) {
        case (nil, nil):
            return false
        case (nil, _):
            return true
        case (_, nil):
            return false
        case let (left?, right?):
            if left.value != right.value {
                return left.value < right.value
            }
        }
    }
}

@inline(__always)
func cedarValuesEqual<T: Comparable>(_ lhs: T, _ rhs: T) -> Bool {
    if let left = lhs as? String, let right = rhs as? String {
        return cedarStringEqual(left, right)
    }

    return lhs == rhs
}

@inline(__always)
func cedarValuesLess<T: Comparable>(_ lhs: T, _ rhs: T) -> Bool {
    if let left = lhs as? String, let right = rhs as? String {
        return cedarStringLess(left, right)
    }

    return lhs < rhs
}

@inline(__always)
func cedarHashString(_ value: String, into hasher: inout Hasher) {
    hasher.combine(value.unicodeScalars.count)

    for scalar in value.unicodeScalars {
        hasher.combine(scalar.value)
    }
}

@inline(__always)
func cedarBinarySearchIndex<Element: Comparable>(_ storage: [Element], for target: Element) -> Int? {
    var lowerBound = 0
    var upperBound = storage.count

    while lowerBound < upperBound {
        let middle = lowerBound + ((upperBound - lowerBound) / 2)
        let candidate = storage[middle]

        if cedarValuesLess(candidate, target) {
            lowerBound = middle + 1
            continue
        }

        if cedarValuesLess(target, candidate) {
            upperBound = middle
            continue
        }

        return middle
    }

    return nil
}

@inline(__always)
func cedarInsertionIndex<Element: Comparable>(in storage: [Element], for target: Element) -> Int {
    var lowerBound = 0
    var upperBound = storage.count

    while lowerBound < upperBound {
        let middle = lowerBound + ((upperBound - lowerBound) / 2)
        if cedarValuesLess(storage[middle], target) {
            lowerBound = middle + 1
        } else {
            upperBound = middle
        }
    }

    return lowerBound
}

public struct CedarSet<Element: Comparable & Sendable>: Sendable {
    private let storage: [Element]

    public init(_ elements: [Element] = []) {
        self.storage = Self.canonicalize(elements)
    }

    private init(canonical elements: [Element]) {
        self.storage = elements
    }

    public static func make(_ elements: [Element]) -> Self {
        Self(canonical: canonicalize(elements))
    }

    public static var empty: Self {
        Self(canonical: [])
    }

    public var elements: [Element] {
        storage
    }

    public var isEmpty: Bool {
        storage.isEmpty
    }

    public func contains(_ element: Element) -> Bool {
        cedarBinarySearchIndex(storage, for: element) != nil
    }

    public func subset(of other: Self) -> Bool {
        var lhsIndex = storage.startIndex
        var rhsIndex = other.storage.startIndex

        while lhsIndex < storage.endIndex, rhsIndex < other.storage.endIndex {
            let lhsElement = storage[lhsIndex]
            let rhsElement = other.storage[rhsIndex]

            if cedarValuesLess(lhsElement, rhsElement) {
                return false
            }

            if cedarValuesLess(rhsElement, lhsElement) {
                rhsIndex = other.storage.index(after: rhsIndex)
                continue
            }

            lhsIndex = storage.index(after: lhsIndex)
            rhsIndex = other.storage.index(after: rhsIndex)
        }

        return lhsIndex == storage.endIndex
    }

    public func intersects(with other: Self) -> Bool {
        var lhsIndex = storage.startIndex
        var rhsIndex = other.storage.startIndex

        while lhsIndex < storage.endIndex, rhsIndex < other.storage.endIndex {
            let lhsElement = storage[lhsIndex]
            let rhsElement = other.storage[rhsIndex]

            if cedarValuesLess(lhsElement, rhsElement) {
                lhsIndex = storage.index(after: lhsIndex)
                continue
            }

            if cedarValuesLess(rhsElement, lhsElement) {
                rhsIndex = other.storage.index(after: rhsIndex)
                continue
            }

            return true
        }

        return false
    }

    public func any(_ predicate: (Element) -> Bool) -> Bool {
        storage.contains(where: predicate)
    }

    public func all(_ predicate: (Element) -> Bool) -> Bool {
        storage.allSatisfy(predicate)
    }

    public func mapOrErr<Mapped: Comparable & Sendable, Failure: Error>(
        _ transform: (Element) -> Result<Mapped, Failure>,
        error fixedError: Failure
    ) -> Result<CedarSet<Mapped>, Failure> {
        var mapped: [Mapped] = []
        mapped.reserveCapacity(storage.count)

        for element in storage {
            switch transform(element) {
            case let .success(value):
                mapped.append(value)
            case .failure:
                return .failure(fixedError)
            }
        }

        return .success(CedarSet<Mapped>.make(mapped))
    }

    public func filter(_ isIncluded: (Element) -> Bool) -> Self {
        Self(canonical: storage.filter(isIncluded))
    }

    private static func canonicalize(_ elements: [Element]) -> [Element] {
        var canonical: [Element] = []
        canonical.reserveCapacity(elements.count)

        for element in elements.reversed() {
            insertCanonical(element, into: &canonical)
        }

        return canonical
    }

    private static func insertCanonical(_ element: Element, into canonical: inout [Element]) {
        if let existingIndex = cedarBinarySearchIndex(canonical, for: element) {
            canonical[existingIndex] = element
            return
        }

        canonical.insert(element, at: cedarInsertionIndex(in: canonical, for: element))
    }
}

extension CedarSet: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.storage.elementsEqual(rhs.storage, by: cedarValuesEqual)
    }
}

extension CedarSet: Collection {
    public typealias Index = Array<Element>.Index

    public var startIndex: Index {
        storage.startIndex
    }

    public var endIndex: Index {
        storage.endIndex
    }

    public subscript(position: Index) -> Element {
        storage[position]
    }

    public func index(after i: Index) -> Index {
        storage.index(after: i)
    }
}

extension CedarSet: Hashable where Element: Hashable {}

extension CedarSet: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        var lhsIndex = lhs.storage.startIndex
        var rhsIndex = rhs.storage.startIndex

        while lhsIndex < lhs.storage.endIndex, rhsIndex < rhs.storage.endIndex {
            let left = lhs.storage[lhsIndex]
            let right = rhs.storage[rhsIndex]

            if cedarValuesLess(left, right) {
                return true
            }

            if cedarValuesLess(right, left) {
                return false
            }

            lhsIndex = lhs.storage.index(after: lhsIndex)
            rhsIndex = rhs.storage.index(after: rhsIndex)
        }

        return lhsIndex == lhs.storage.endIndex && rhsIndex < rhs.storage.endIndex
    }
}
