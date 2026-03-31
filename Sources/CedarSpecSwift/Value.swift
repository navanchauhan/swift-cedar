public enum CedarError: Error, Equatable, Hashable, Sendable {
    case entityDoesNotExist
    case attrDoesNotExist
    case tagDoesNotExist
    case typeError
    case arithBoundsError
    case evaluationLimitError
    case extensionError
    case restrictedExprError(RestrictedExprError)
}

public typealias CedarResult<Success> = Result<Success, CedarError>
public typealias EntityType = Name
public typealias Attr = String

private func cedarStringArrayEqual(_ lhs: [String], _ rhs: [String]) -> Bool {
    guard lhs.count == rhs.count else {
        return false
    }

    return zip(lhs, rhs).allSatisfy(cedarStringEqual)
}

private func cedarStringArrayLess(_ lhs: [String], _ rhs: [String]) -> Bool {
    var index = 0

    while index < lhs.count, index < rhs.count {
        let left = lhs[index]
        let right = rhs[index]

        if cedarStringLess(left, right) {
            return true
        }

        if cedarStringLess(right, left) {
            return false
        }

        index += 1
    }

    return lhs.count < rhs.count
}

public struct Name: Hashable, Sendable {
    public let id: String
    public let path: [String]

    public init(id: String, path: [String] = []) {
        self.id = id
        self.path = path
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        cedarStringEqual(lhs.id, rhs.id)
            && cedarStringArrayEqual(lhs.path, rhs.path)
    }

    public func hash(into hasher: inout Hasher) {
        cedarHashString(id, into: &hasher)
        hasher.combine(path.count)

        for component in path {
            cedarHashString(component, into: &hasher)
        }
    }
}

extension Name: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if cedarStringLess(lhs.id, rhs.id) {
            return true
        }

        if cedarStringLess(rhs.id, lhs.id) {
            return false
        }

        return cedarStringArrayLess(lhs.path, rhs.path)
    }
}

extension Name: CustomStringConvertible {
    public var description: String {
        (path.map { "\($0)::" }.joined()) + id
    }
}

public struct EntityUID: Hashable, Sendable {
    public let ty: EntityType
    public let eid: String

    public init(ty: EntityType, eid: String) {
        self.ty = ty
        self.eid = eid
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.ty == rhs.ty && cedarStringEqual(lhs.eid, rhs.eid)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ty)
        cedarHashString(eid, into: &hasher)
    }
}

extension EntityUID: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.ty != rhs.ty {
            return lhs.ty < rhs.ty
        }

        return cedarStringLess(lhs.eid, rhs.eid)
    }
}

extension EntityUID: CustomStringConvertible {
    public var description: String {
        "\(ty)::\"\(eid)\""
    }
}

public enum Prim: Sendable {
    case bool(Bool)
    case int(Int64)
    case string(String)
    case entityUID(EntityUID)

    private var constructorRank: Int {
        switch self {
        case .bool:
            0
        case .int:
            1
        case .string:
            2
        case .entityUID:
            3
        }
    }
}

extension Prim: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.bool(left), .bool(right)):
            return left == right
        case let (.int(left), .int(right)):
            return left == right
        case let (.string(left), .string(right)):
            return cedarStringEqual(left, right)
        case let (.entityUID(left), .entityUID(right)):
            return left == right
        default:
            return false
        }
    }
}

extension Prim: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(constructorRank)

        switch self {
        case let .bool(value):
            hasher.combine(value)
        case let .int(value):
            hasher.combine(value)
        case let .string(value):
            cedarHashString(value, into: &hasher)
        case let .entityUID(value):
            hasher.combine(value)
        }
    }
}

extension Prim: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.constructorRank != rhs.constructorRank {
            return lhs.constructorRank < rhs.constructorRank
        }

        switch (lhs, rhs) {
        case let (.bool(left), .bool(right)):
            return left == false && right == true
        case let (.int(left), .int(right)):
            return left < right
        case let (.string(left), .string(right)):
            return cedarStringLess(left, right)
        case let (.entityUID(left), .entityUID(right)):
            return left < right
        default:
            return false
        }
    }
}

public indirect enum CedarValue: Sendable {
    case prim(Prim)
    case set(CedarSet<CedarValue>)
    case record(CedarMap<Attr, CedarValue>)
    case ext(Ext)

    private var constructorRank: Int {
        switch self {
        case .prim:
            0
        case .set:
            1
        case .record:
            2
        case .ext:
            3
        }
    }

    public func asEntityUID() -> CedarResult<EntityUID> {
        guard case let .prim(.entityUID(uid)) = self else {
            return .failure(.typeError)
        }

        return .success(uid)
    }

    public func asSet() -> CedarResult<CedarSet<CedarValue>> {
        guard case let .set(set) = self else {
            return .failure(.typeError)
        }

        return .success(set)
    }

    public func asBool() -> CedarResult<Bool> {
        guard case let .prim(.bool(value)) = self else {
            return .failure(.typeError)
        }

        return .success(value)
    }

    public func asString() -> CedarResult<String> {
        guard case let .prim(.string(value)) = self else {
            return .failure(.typeError)
        }

        return .success(value)
    }

    public func asInt() -> CedarResult<Int64> {
        guard case let .prim(.int(value)) = self else {
            return .failure(.typeError)
        }

        return .success(value)
    }
}

extension CedarValue: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.prim(left), .prim(right)):
            return left == right
        case let (.set(left), .set(right)):
            return left == right
        case let (.record(left), .record(right)):
            return left == right
        case let (.ext(left), .ext(right)):
            return left == right
        default:
            return false
        }
    }
}

extension CedarValue: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(constructorRank)

        switch self {
        case let .prim(value):
            hasher.combine(value)
        case let .set(value):
            hasher.combine(value)
        case let .record(value):
            hasher.combine(value)
        case let .ext(value):
            hasher.combine(value)
        }
    }
}

extension CedarValue: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.constructorRank != rhs.constructorRank {
            return lhs.constructorRank < rhs.constructorRank
        }

        switch (lhs, rhs) {
        case let (.prim(left), .prim(right)):
            return left < right
        case let (.set(left), .set(right)):
            return left < right
        case let (.record(left), .record(right)):
            return left < right
        case let (.ext(left), .ext(right)):
            return left < right
        default:
            return false
        }
    }
}
