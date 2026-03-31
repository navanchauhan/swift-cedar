public enum RestrictedExprSourceConstructor: Int, CaseIterable, Equatable, Hashable, Comparable, Sendable {
    case lit
    case variable
    case unaryApp
    case binaryApp
    case ifThenElse
    case set
    case record
    case hasAttr
    case getAttr
    case like
    case isEntityType
    case call

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum RestrictedExprError: Error, Equatable, Hashable, Sendable {
    case unsupportedExprConstructor(RestrictedExprSourceConstructor)
    case unsupportedLiteral(CedarValue)
    case unsupportedExtensionFunction(ExtFun)
    case invalidExtensionCallArguments(ExtFun)
    case extensionConstructorError(ExtFun)
    case contextMustBeRecord
}

public indirect enum RestrictedExpr: Sendable {
    case bool(Bool)
    case int(Int64)
    case string(String)
    case entityUID(EntityUID)
    case set(CedarSet<RestrictedExpr>)
    case record(CedarMap<Attr, RestrictedExpr>)
    case call(ExtFun, [RestrictedExpr])

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
        case .set:
            4
        case .record:
            5
        case .call:
            6
        }
    }

    public static var emptyRecord: Self {
        .record(.empty)
    }

    public init(restricting expr: Expr) throws {
        self = try Self.restrict(expr).get()
    }

    public static func restrict(_ expr: Expr) -> Result<Self, RestrictedExprError> {
        switch expr {
        case let .lit(value):
            switch value {
            case let .prim(.bool(booleanValue)):
                return .success(.bool(booleanValue))
            case let .prim(.int(intValue)):
                return .success(.int(intValue))
            case let .prim(.string(stringValue)):
                return .success(.string(stringValue))
            case let .prim(.entityUID(uid)):
                return .success(.entityUID(uid))
            default:
                return .failure(.unsupportedLiteral(value))
            }
        case let .set(expressions):
            var restrictedElements: [RestrictedExpr] = []
            restrictedElements.reserveCapacity(expressions.count)

            for expression in expressions {
                switch restrict(expression) {
                case let .success(restrictedExpression):
                    restrictedElements.append(restrictedExpression)
                case let .failure(error):
                    return .failure(error)
                }
            }

            return .success(.set(CedarSet.make(restrictedElements)))
        case let .record(entries):
            var restrictedEntries: [(key: Attr, value: RestrictedExpr)] = []
            restrictedEntries.reserveCapacity(entries.count)

            for entry in entries {
                switch restrict(entry.value) {
                case let .success(restrictedValue):
                    restrictedEntries.append((key: entry.key, value: restrictedValue))
                case let .failure(error):
                    return .failure(error)
                }
            }

            return .success(.record(CedarMap.make(restrictedEntries)))
        case let .call(function, arguments):
            guard restrictedConstructorFunctions.contains(function) else {
                return .failure(.unsupportedExtensionFunction(function))
            }

            var restrictedArguments: [RestrictedExpr] = []
            restrictedArguments.reserveCapacity(arguments.count)

            for argument in arguments {
                switch restrict(argument) {
                case let .success(restrictedArgument):
                    restrictedArguments.append(restrictedArgument)
                case let .failure(error):
                    return .failure(error)
                }
            }

            return .success(.call(function, restrictedArguments))
        case .variable:
            return .failure(.unsupportedExprConstructor(.variable))
        case .unaryApp:
            return .failure(.unsupportedExprConstructor(.unaryApp))
        case .binaryApp:
            return .failure(.unsupportedExprConstructor(.binaryApp))
        case .ifThenElse:
            return .failure(.unsupportedExprConstructor(.ifThenElse))
        case .hasAttr:
            return .failure(.unsupportedExprConstructor(.hasAttr))
        case .getAttr:
            return .failure(.unsupportedExprConstructor(.getAttr))
        case .like:
            return .failure(.unsupportedExprConstructor(.like))
        case .isEntityType:
            return .failure(.unsupportedExprConstructor(.isEntityType))
        }
    }

    public func materialize() -> Result<CedarValue, RestrictedExprError> {
        switch self {
        case let .bool(value):
            return .success(.prim(.bool(value)))
        case let .int(value):
            return .success(.prim(.int(value)))
        case let .string(value):
            return .success(.prim(.string(value)))
        case let .entityUID(value):
            return .success(.prim(.entityUID(value)))
        case let .set(values):
            var materializedValues: [CedarValue] = []
            materializedValues.reserveCapacity(values.count)

            for value in values.elements {
                switch value.materialize() {
                case let .success(materializedValue):
                    materializedValues.append(materializedValue)
                case let .failure(error):
                    return .failure(error)
                }
            }

            return .success(.set(CedarSet.make(materializedValues)))
        case let .record(entries):
            switch materializeRecordEntries(entries) {
            case let .success(recordValue):
                return .success(.record(recordValue))
            case let .failure(error):
                return .failure(error)
            }
        case let .call(function, arguments):
            return materializeCall(function, arguments: arguments)
        }
    }

    internal func materializeRecord() -> Result<CedarMap<Attr, CedarValue>, RestrictedExprError> {
        guard case let .record(entries) = self else {
            return .failure(.contextMustBeRecord)
        }

        return materializeRecordEntries(entries)
    }
}

extension RestrictedExpr: Equatable {
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
        case let (.set(left), .set(right)):
            return left == right
        case let (.record(left), .record(right)):
            return left == right
        case let (.call(leftFunction, leftArguments), .call(rightFunction, rightArguments)):
            return leftFunction == rightFunction && restrictedExprArrayEqual(leftArguments, rightArguments)
        default:
            return false
        }
    }
}

extension RestrictedExpr: Comparable {
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
        case let (.set(left), .set(right)):
            return left < right
        case let (.record(left), .record(right)):
            return left < right
        case let (.call(leftFunction, leftArguments), .call(rightFunction, rightArguments)):
            if leftFunction != rightFunction {
                return leftFunction < rightFunction
            }

            return restrictedExprArrayLess(leftArguments, rightArguments)
        default:
            return false
        }
    }
}

private let restrictedConstructorFunctions: CedarSet<ExtFun> = .make([
    .decimal,
    .ip,
    .datetime,
    .duration,
    .offset,
])

private func restrictedExprArrayEqual(_ lhs: [RestrictedExpr], _ rhs: [RestrictedExpr]) -> Bool {
    guard lhs.count == rhs.count else {
        return false
    }

    return zip(lhs, rhs).allSatisfy(==)
}

private func restrictedExprArrayLess(_ lhs: [RestrictedExpr], _ rhs: [RestrictedExpr]) -> Bool {
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

private func materializeRecordEntries(
    _ entries: CedarMap<Attr, RestrictedExpr>
) -> Result<CedarMap<Attr, CedarValue>, RestrictedExprError> {
    var materializedEntries: [(key: Attr, value: CedarValue)] = []
    materializedEntries.reserveCapacity(entries.count)

    for entry in entries {
        switch entry.value.materialize() {
        case let .success(value):
            materializedEntries.append((key: entry.key, value: value))
        case let .failure(error):
            return .failure(error)
        }
    }

    return .success(CedarMap.make(materializedEntries))
}

private func materializeCall(
    _ function: ExtFun,
    arguments: [RestrictedExpr]
) -> Result<CedarValue, RestrictedExprError> {
    switch function {
    case .decimal:
        switch materializeSingleStringArgument(function, arguments: arguments) {
        case let .success(rawValue):
            guard decimalParse(rawValue) != nil else {
                return .failure(.extensionConstructorError(function))
            }

            return .success(.ext(.decimal(.init(rawValue: rawValue))))
        case let .failure(error):
            return .failure(error)
        }
    case .ip:
        switch materializeSingleStringArgument(function, arguments: arguments) {
        case let .success(rawValue):
            guard ipaddrParse(rawValue) != nil else {
                return .failure(.extensionConstructorError(function))
            }

            return .success(.ext(.ipaddr(.init(rawValue: rawValue))))
        case let .failure(error):
            return .failure(error)
        }
    case .datetime:
        switch materializeSingleStringArgument(function, arguments: arguments) {
        case let .success(rawValue):
            guard datetimeParse(rawValue) != nil else {
                return .failure(.extensionConstructorError(function))
            }

            return .success(.ext(.datetime(.init(rawValue: rawValue))))
        case let .failure(error):
            return .failure(error)
        }
    case .duration:
        switch materializeSingleStringArgument(function, arguments: arguments) {
        case let .success(rawValue):
            guard durationParse(rawValue) != nil else {
                return .failure(.extensionConstructorError(function))
            }

            return .success(.ext(.duration(.init(rawValue: rawValue))))
        case let .failure(error):
            return .failure(error)
        }
    case .offset:
        guard arguments.count == 2 else {
            return .failure(.invalidExtensionCallArguments(function))
        }

        let firstValue: CedarValue
        switch arguments[0].materialize() {
        case let .success(value):
            firstValue = value
        case let .failure(error):
            return .failure(error)
        }

        let secondValue: CedarValue
        switch arguments[1].materialize() {
        case let .success(value):
            secondValue = value
        case let .failure(error):
            return .failure(error)
        }

        guard case let .ext(.datetime(datetimePayload)) = firstValue,
              case let .ext(.duration(durationPayload)) = secondValue
        else {
            return .failure(.invalidExtensionCallArguments(function))
        }

        switch datetimeOffsetResult(datetimePayload, durationPayload) {
        case let .success(value):
            return .success(value)
        case .failure:
            return .failure(.extensionConstructorError(function))
        }
    default:
        return .failure(.unsupportedExtensionFunction(function))
    }
}

private func materializeSingleStringArgument(
    _ function: ExtFun,
    arguments: [RestrictedExpr]
) -> Result<String, RestrictedExprError> {
    guard arguments.count == 1 else {
        return .failure(.invalidExtensionCallArguments(function))
    }

    switch arguments[0].materialize() {
    case let .success(.prim(.string(rawValue))):
        return .success(rawValue)
    case .success:
        return .failure(.invalidExtensionCallArguments(function))
    case let .failure(error):
        return .failure(error)
    }
}