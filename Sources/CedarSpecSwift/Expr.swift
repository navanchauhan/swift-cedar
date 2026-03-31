public enum Var: Int, CaseIterable, Equatable, Comparable, Sendable {
    case principal
    case action
    case resource
    case context

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum UnaryOp: Int, CaseIterable, Equatable, Comparable, Sendable {
    case not
    case neg
    case isEmpty

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum BinaryOp: Int, CaseIterable, Equatable, Comparable, Sendable {
    case and
    case or
    case equal
    case lessThan
    case lessThanOrEqual
    case add
    case sub
    case mul
    case `in`
    case contains
    case containsAll
    case containsAny
    case hasTag
    case getTag

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public indirect enum Expr: Sendable {
    case lit(CedarValue)
    case variable(Var)
    case unaryApp(UnaryOp, Expr)
    case binaryApp(BinaryOp, Expr, Expr)
    case ifThenElse(Expr, Expr, Expr)
    case set([Expr])
    case record([(key: Attr, value: Expr)])
    case hasAttr(Expr, Attr)
    case getAttr(Expr, Attr)
    case like(Expr, Pattern)
    case isEntityType(Expr, Name)
    case call(ExtFun, [Expr])

    private var constructorRank: Int {
        switch self {
        case .lit:
            0
        case .variable:
            1
        case .unaryApp:
            2
        case .binaryApp:
            3
        case .ifThenElse:
            4
        case .set:
            5
        case .record:
            6
        case .hasAttr:
            7
        case .getAttr:
            8
        case .like:
            9
        case .isEntityType:
            10
        case .call:
            11
        }
    }
}

extension Expr: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.lit(left), .lit(right)):
            return left == right
        case let (.variable(left), .variable(right)):
            return left == right
        case let (.unaryApp(leftOp, leftExpr), .unaryApp(rightOp, rightExpr)):
            return leftOp == rightOp && leftExpr == rightExpr
        case let (.binaryApp(leftOp, leftLHS, leftRHS), .binaryApp(rightOp, rightLHS, rightRHS)):
            return leftOp == rightOp && leftLHS == rightLHS && leftRHS == rightRHS
        case let (.ifThenElse(leftCond, leftThen, leftElse), .ifThenElse(rightCond, rightThen, rightElse)):
            return leftCond == rightCond && leftThen == rightThen && leftElse == rightElse
        case let (.set(left), .set(right)):
            return exprArrayEqual(left, right)
        case let (.record(left), .record(right)):
            return exprRecordEqual(left, right)
        case let (.hasAttr(leftExpr, leftAttr), .hasAttr(rightExpr, rightAttr)):
            return leftExpr == rightExpr && cedarStringEqual(leftAttr, rightAttr)
        case let (.getAttr(leftExpr, leftAttr), .getAttr(rightExpr, rightAttr)):
            return leftExpr == rightExpr && cedarStringEqual(leftAttr, rightAttr)
        case let (.like(leftExpr, leftPattern), .like(rightExpr, rightPattern)):
            return leftExpr == rightExpr && leftPattern == rightPattern
        case let (.isEntityType(leftExpr, leftType), .isEntityType(rightExpr, rightType)):
            return leftExpr == rightExpr && leftType == rightType
        case let (.call(leftFun, leftArgs), .call(rightFun, rightArgs)):
            return leftFun == rightFun && exprArrayEqual(leftArgs, rightArgs)
        default:
            return false
        }
    }
}

extension Expr: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(constructorRank)

        switch self {
        case let .lit(value):
            hasher.combine(value)
        case let .variable(value):
            hasher.combine(value)
        case let .unaryApp(op, expr):
            hasher.combine(op)
            hasher.combine(expr)
        case let .binaryApp(op, lhs, rhs):
            hasher.combine(op)
            hasher.combine(lhs)
            hasher.combine(rhs)
        case let .ifThenElse(condition, thenExpr, elseExpr):
            hasher.combine(condition)
            hasher.combine(thenExpr)
            hasher.combine(elseExpr)
        case let .set(expressions):
            hashExprArray(expressions, into: &hasher)
        case let .record(record):
            hashExprRecord(record, into: &hasher)
        case let .hasAttr(expr, attr):
            hasher.combine(expr)
            cedarHashString(attr, into: &hasher)
        case let .getAttr(expr, attr):
            hasher.combine(expr)
            cedarHashString(attr, into: &hasher)
        case let .like(expr, pattern):
            hasher.combine(expr)
            hashPattern(pattern, into: &hasher)
        case let .isEntityType(expr, entityType):
            hasher.combine(expr)
            hasher.combine(entityType)
        case let .call(function, arguments):
            hasher.combine(function)
            hashExprArray(arguments, into: &hasher)
        }
    }
}

extension Expr: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.constructorRank != rhs.constructorRank {
            return lhs.constructorRank < rhs.constructorRank
        }

        switch (lhs, rhs) {
        case let (.lit(left), .lit(right)):
            return left < right
        case let (.variable(left), .variable(right)):
            return left < right
        case let (.unaryApp(leftOp, leftExpr), .unaryApp(rightOp, rightExpr)):
            if leftOp != rightOp {
                return leftOp < rightOp
            }

            return leftExpr < rightExpr
        case let (.binaryApp(leftOp, leftLHS, leftRHS), .binaryApp(rightOp, rightLHS, rightRHS)):
            if leftOp != rightOp {
                return leftOp < rightOp
            }

            if leftLHS != rightLHS {
                return leftLHS < rightLHS
            }

            return leftRHS < rightRHS
        case let (.ifThenElse(leftCond, leftThen, leftElse), .ifThenElse(rightCond, rightThen, rightElse)):
            if leftCond != rightCond {
                return leftCond < rightCond
            }

            if leftThen != rightThen {
                return leftThen < rightThen
            }

            return leftElse < rightElse
        case let (.set(left), .set(right)):
            return exprArrayLess(left, right)
        case let (.record(left), .record(right)):
            return exprRecordLess(left, right)
        case let (.hasAttr(leftExpr, leftAttr), .hasAttr(rightExpr, rightAttr)):
            if leftExpr != rightExpr {
                return leftExpr < rightExpr
            }

            return cedarStringLess(leftAttr, rightAttr)
        case let (.getAttr(leftExpr, leftAttr), .getAttr(rightExpr, rightAttr)):
            if leftExpr != rightExpr {
                return leftExpr < rightExpr
            }

            return cedarStringLess(leftAttr, rightAttr)
        case let (.like(leftExpr, leftPattern), .like(rightExpr, rightPattern)):
            if leftExpr != rightExpr {
                return leftExpr < rightExpr
            }

            return leftPattern < rightPattern
        case let (.isEntityType(leftExpr, leftType), .isEntityType(rightExpr, rightType)):
            if leftExpr != rightExpr {
                return leftExpr < rightExpr
            }

            return leftType < rightType
        case let (.call(leftFun, leftArgs), .call(rightFun, rightArgs)):
            if leftFun != rightFun {
                return leftFun < rightFun
            }

            return exprArrayLess(leftArgs, rightArgs)
        default:
            return false
        }
    }
}

private func exprArrayEqual(_ lhs: [Expr], _ rhs: [Expr]) -> Bool {
    guard lhs.count == rhs.count else {
        return false
    }

    return zip(lhs, rhs).allSatisfy(==)
}

private func exprArrayLess(_ lhs: [Expr], _ rhs: [Expr]) -> Bool {
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

private func hashExprArray(_ expressions: [Expr], into hasher: inout Hasher) {
    hasher.combine(expressions.count)

    for expression in expressions {
        hasher.combine(expression)
    }
}

private func exprRecordEqual(
    _ lhs: [(key: Attr, value: Expr)],
    _ rhs: [(key: Attr, value: Expr)]
) -> Bool {
    guard lhs.count == rhs.count else {
        return false
    }

    for (left, right) in zip(lhs, rhs) {
        guard cedarStringEqual(left.key, right.key), left.value == right.value else {
            return false
        }
    }

    return true
}

private func exprRecordLess(
    _ lhs: [(key: Attr, value: Expr)],
    _ rhs: [(key: Attr, value: Expr)]
) -> Bool {
    var index = 0

    while index < lhs.count, index < rhs.count {
        let left = lhs[index]
        let right = rhs[index]

        if !cedarStringEqual(left.key, right.key) {
            return cedarStringLess(left.key, right.key)
        }

        if left.value != right.value {
            return left.value < right.value
        }

        index += 1
    }

    return lhs.count < rhs.count
}

private func hashExprRecord(
    _ record: [(key: Attr, value: Expr)],
    into hasher: inout Hasher
) {
    hasher.combine(record.count)

    for entry in record {
        cedarHashString(entry.key, into: &hasher)
        hasher.combine(entry.value)
    }
}

private func hashPattern(_ pattern: Pattern, into hasher: inout Hasher) {
    hasher.combine(pattern.elements.count)

    for element in pattern.elements {
        switch element {
        case .wildcard:
            hasher.combine(0)
        case let .literal(scalar):
            hasher.combine(1)
            hasher.combine(scalar.value)
        }
    }
}
