public enum DiagnosticSeverity: Int, CaseIterable, Hashable, Sendable {
    case info
    case warning
    case error
}

extension DiagnosticSeverity: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum DiagnosticCategory: Int, CaseIterable, Hashable, Sendable {
    case io
    case parse
    case request
    case policy
    case template
    case entity
    case schema
    case validation
    case `internal`
}

extension DiagnosticCategory: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct Diagnostic: Sendable {
    public let code: String
    public let category: DiagnosticCategory
    public let severity: DiagnosticSeverity
    public let message: String
    public let sourceSpan: SourceSpan?

    public init(
        code: String,
        category: DiagnosticCategory,
        severity: DiagnosticSeverity,
        message: String,
        sourceSpan: SourceSpan? = nil
    ) {
        self.code = code
        self.category = category
        self.severity = severity
        self.message = message
        self.sourceSpan = sourceSpan
    }
}

extension Diagnostic: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        cedarStringEqual(lhs.code, rhs.code)
            && lhs.category == rhs.category
            && lhs.severity == rhs.severity
            && cedarStringEqual(lhs.message, rhs.message)
            && lhs.sourceSpan == rhs.sourceSpan
    }
}

extension Diagnostic: Hashable {
    public func hash(into hasher: inout Hasher) {
        cedarHashString(code, into: &hasher)
        hasher.combine(category)
        hasher.combine(severity)
        cedarHashString(message, into: &hasher)
        hasher.combine(sourceSpan)
    }
}

extension Diagnostic: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if optionalSourceSpanLess(lhs.sourceSpan, rhs.sourceSpan) {
            return true
        }

        if optionalSourceSpanLess(rhs.sourceSpan, lhs.sourceSpan) {
            return false
        }

        if lhs.severity != rhs.severity {
            return lhs.severity < rhs.severity
        }

        if lhs.category != rhs.category {
            return lhs.category < rhs.category
        }

        if cedarStringLess(lhs.code, rhs.code) {
            return true
        }

        if cedarStringLess(rhs.code, lhs.code) {
            return false
        }

        return cedarStringLess(lhs.message, rhs.message)
    }
}

public struct Diagnostics: Hashable, Sendable {
    private let storage: [Diagnostic]

    public init(_ diagnostics: [Diagnostic] = []) {
        self.storage = Self.canonicalize(diagnostics)
    }

    private init(canonical diagnostics: [Diagnostic]) {
        self.storage = diagnostics
    }

    public static var empty: Self {
        Self(canonical: [])
    }

    public var elements: [Diagnostic] {
        storage
    }

    public var isEmpty: Bool {
        storage.isEmpty
    }

    public var hasErrors: Bool {
        storage.contains(where: { $0.severity == .error })
    }

    public func appending(_ diagnostic: Diagnostic) -> Self {
        Self(canonical: Self.inserting(diagnostic, into: storage))
    }

    public func appending(contentsOf diagnostics: Self) -> Self {
        var combined = storage
        combined.reserveCapacity(storage.count + diagnostics.storage.count)

        for diagnostic in diagnostics.storage {
            combined = Self.inserting(diagnostic, into: combined)
        }

        return Self(canonical: combined)
    }

    private static func canonicalize(_ diagnostics: [Diagnostic]) -> [Diagnostic] {
        var canonical: [Diagnostic] = []
        canonical.reserveCapacity(diagnostics.count)

        for diagnostic in diagnostics {
            canonical = inserting(diagnostic, into: canonical)
        }

        return canonical
    }

    private static func inserting(_ diagnostic: Diagnostic, into canonical: [Diagnostic]) -> [Diagnostic] {
        var result = canonical

        for index in result.indices {
            if diagnostic < result[index] {
                result.insert(diagnostic, at: index)
                return result
            }
        }

        result.append(diagnostic)
        return result
    }
}

extension Diagnostics: Error {}
extension Diagnostic: Error {}

extension Diagnostics: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.storage == rhs.storage
    }
}

extension Diagnostics: Collection {
    public typealias Index = Array<Diagnostic>.Index
    public typealias Element = Diagnostic

    public var startIndex: Index {
        storage.startIndex
    }

    public var endIndex: Index {
        storage.endIndex
    }

    public subscript(position: Index) -> Diagnostic {
        storage[position]
    }

    public func index(after i: Index) -> Index {
        storage.index(after: i)
    }
}

public enum LoadResult<Success> {
    case success(Success, diagnostics: Diagnostics)
    case failure(Diagnostics)

    public var diagnostics: Diagnostics {
        switch self {
        case let .success(_, diagnostics):
            return diagnostics
        case let .failure(diagnostics):
            return diagnostics
        }
    }

    public var value: Success? {
        switch self {
        case let .success(value, diagnostics: _):
            return value
        case .failure:
            return nil
        }
    }

    public var isSuccess: Bool {
        switch self {
        case .success:
            return true
        case .failure:
            return false
        }
    }
}

extension LoadResult: Sendable where Success: Sendable {}
extension LoadResult: Equatable where Success: Equatable {}
extension LoadResult: Hashable where Success: Hashable {}

public struct ValidationResult: Hashable, Sendable {
    public let diagnostics: Diagnostics
    public let isValid: Bool

    public init(diagnostics: Diagnostics = .empty, isValid: Bool) {
        self.diagnostics = diagnostics
        self.isValid = isValid
    }

    public static func success(diagnostics: Diagnostics = .empty) -> Self {
        Self(diagnostics: diagnostics, isValid: true)
    }

    public static func failure(_ diagnostics: Diagnostics) -> Self {
        Self(diagnostics: diagnostics, isValid: false)
    }
}

@inline(__always)
private func optionalSourceSpanLess(_ lhs: SourceSpan?, _ rhs: SourceSpan?) -> Bool {
    switch (lhs, rhs) {
    case let (.some(left), .some(right)):
        return left < right
    case (.some, .none):
        return true
    case (.none, .some):
        return false
    case (.none, .none):
        return false
    }
}
