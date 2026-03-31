public struct CedarMap<Key: Comparable & Sendable, Value: Sendable>: Sendable {
    public typealias Entry = (key: Key, value: Value)

    private let storage: [Entry]

    public init(_ entries: [Entry] = []) {
        self.storage = Self.canonicalize(entries)
    }

    private init(canonical entries: [Entry]) {
        self.storage = entries
    }

    public static func make(_ entries: [Entry]) -> Self {
        Self(canonical: canonicalize(entries))
    }

    public static var empty: Self {
        Self(canonical: [])
    }

    public var entries: [Entry] {
        storage
    }

    public func find(_ key: Key) -> Value? {
        guard let index = findIndex(for: key) else {
            return nil
        }

        return storage[index].value
    }

    public func findOrErr<Failure: Error>(_ key: Key, error: Failure) -> Result<Value, Failure> {
        guard let value = find(key) else {
            return .failure(error)
        }

        return .success(value)
    }

    public func contains(_ key: Key) -> Bool {
        findIndex(for: key) != nil
    }

    public var keys: CedarSet<Key> {
        CedarSet.make(storage.map(\.key))
    }

    public var values: [Value] {
        storage.map(\.value)
    }

    public func filter(_ isIncluded: (Key, Value) -> Bool) -> Self {
        Self(canonical: storage.filter { isIncluded($0.key, $0.value) })
    }

    private static func canonicalize(_ entries: [Entry]) -> [Entry] {
        var canonical: [Entry] = []
        canonical.reserveCapacity(entries.count)

        for entry in entries.reversed() {
            insertCanonical(entry, into: &canonical)
        }

        return canonical
    }

    private static func insertCanonical(_ entry: Entry, into canonical: inout [Entry]) {
        if let existingIndex = findIndex(for: entry.key, in: canonical) {
            canonical[existingIndex] = entry
            return
        }

        canonical.insert(entry, at: insertionIndex(for: entry.key, in: canonical))
    }

    @inline(__always)
    private func findIndex(for key: Key) -> Int? {
        Self.findIndex(for: key, in: storage)
    }

    @inline(__always)
    private static func findIndex(for key: Key, in storage: [Entry]) -> Int? {
        var lowerBound = 0
        var upperBound = storage.count

        while lowerBound < upperBound {
            let middle = lowerBound + ((upperBound - lowerBound) / 2)
            let candidateKey = storage[middle].key

            if cedarValuesLess(candidateKey, key) {
                lowerBound = middle + 1
                continue
            }

            if cedarValuesLess(key, candidateKey) {
                upperBound = middle
                continue
            }

            return middle
        }

        return nil
    }

    @inline(__always)
    private static func insertionIndex(for key: Key, in storage: [Entry]) -> Int {
        var lowerBound = 0
        var upperBound = storage.count

        while lowerBound < upperBound {
            let middle = lowerBound + ((upperBound - lowerBound) / 2)
            if cedarValuesLess(storage[middle].key, key) {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        return lowerBound
    }
}

extension CedarMap: Equatable where Value: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.storage.elementsEqual(rhs.storage, by: { left, right in
            cedarValuesEqual(left.key, right.key) && left.value == right.value
        })
    }
}

extension CedarMap: Hashable where Key: Hashable, Value: Hashable {
    public func hash(into hasher: inout Hasher) {
        for entry in storage {
            hasher.combine(entry.key)
            hasher.combine(entry.value)
        }
    }
}

extension CedarMap: Comparable where Value: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        var lhsIndex = lhs.storage.startIndex
        var rhsIndex = rhs.storage.startIndex

        while lhsIndex < lhs.storage.endIndex, rhsIndex < rhs.storage.endIndex {
            let left = lhs.storage[lhsIndex]
            let right = rhs.storage[rhsIndex]

            if cedarValuesLess(left.key, right.key) {
                return true
            }

            if cedarValuesLess(right.key, left.key) {
                return false
            }

            if left.value < right.value {
                return true
            }

            if right.value < left.value {
                return false
            }

            lhsIndex = lhs.storage.index(after: lhsIndex)
            rhsIndex = rhs.storage.index(after: rhsIndex)
        }

        return lhsIndex == lhs.storage.endIndex && rhsIndex < rhs.storage.endIndex
    }
}

extension CedarMap: Collection {
    public typealias Index = Array<Entry>.Index
    public typealias Element = Entry

    public var startIndex: Index {
        storage.startIndex
    }

    public var endIndex: Index {
        storage.endIndex
    }

    public subscript(position: Index) -> Entry {
        storage[position]
    }

    public func index(after i: Index) -> Index {
        storage.index(after: i)
    }
}
