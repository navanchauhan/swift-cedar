import XCTest
@testable import CedarSpecSwift

final class ExprTests: XCTestCase {
    private let composedEAcute = "\u{00E9}"
    private let decomposedEAcute = "e\u{0301}"

    func testVarComparableUsesConstructorOrder() {
        XCTAssertEqual(Var.allCases, [.principal, .action, .resource, .context])
        XCTAssertEqual([Var.context, .resource, .principal, .action].sorted(), Var.allCases)
    }

    func testUnaryOpComparableUsesConstructorOrder() {
        XCTAssertEqual(UnaryOp.allCases, [.not, .neg, .isEmpty])
        XCTAssertEqual([UnaryOp.isEmpty, .neg, .not].sorted(), UnaryOp.allCases)
    }

    func testBinaryOpComparableUsesConstructorOrder() {
        let expected: [BinaryOp] = [
            .and,
            .or,
            .equal,
            .lessThan,
            .lessThanOrEqual,
            .add,
            .sub,
            .mul,
            .in,
            .contains,
            .containsAll,
            .containsAny,
            .hasTag,
            .getTag,
        ]

        XCTAssertEqual(BinaryOp.allCases, expected)
        XCTAssertEqual(expected.reversed().sorted(), expected)
    }

    func testExprComparableUsesConstructorOrderAcrossCases() {
        let pattern = Pattern([.wildcard])
        let name = Name(id: "User")
        let literal = Expr.lit(.prim(.bool(false)))
        let variable = Expr.variable(.principal)
        let unary = Expr.unaryApp(.not, literal)
        let binary = Expr.binaryApp(.and, literal, variable)
        let conditional = Expr.ifThenElse(literal, variable, unary)
        let set = Expr.set([literal])
        let record = Expr.record([(key: "department", value: literal)])
        let hasAttr = Expr.hasAttr(variable, "department")
        let getAttr = Expr.getAttr(variable, "department")
        let like = Expr.like(variable, pattern)
        let isEntityType = Expr.isEntityType(variable, name)
        let call = Expr.call(.decimal, [literal])

        XCTAssertEqual([
            call,
            isEntityType,
            like,
            getAttr,
            hasAttr,
            record,
            set,
            conditional,
            binary,
            unary,
            variable,
            literal,
        ].sorted(), [
            literal,
            variable,
            unary,
            binary,
            conditional,
            set,
            record,
            hasAttr,
            getAttr,
            like,
            isEntityType,
            call,
        ])
    }

    func testExprSameConstructorComparisonsUseAssociatedValues() {
        let falseLiteral = Expr.lit(.prim(.bool(false)))
        let trueLiteral = Expr.lit(.prim(.bool(true)))
        let composedPattern = Pattern(composedEAcute.unicodeScalars.map(PatElem.literal))
        let decomposedPattern = Pattern(decomposedEAcute.unicodeScalars.map(PatElem.literal))

        XCTAssertLessThan(Expr.variable(.principal), Expr.variable(.context))
        XCTAssertLessThan(Expr.unaryApp(.not, falseLiteral), Expr.unaryApp(.neg, falseLiteral))
        XCTAssertLessThan(Expr.unaryApp(.neg, falseLiteral), Expr.unaryApp(.isEmpty, falseLiteral))
        XCTAssertLessThan(Expr.binaryApp(.and, falseLiteral, trueLiteral), Expr.binaryApp(.or, falseLiteral, trueLiteral))
        XCTAssertLessThan(
            Expr.ifThenElse(falseLiteral, falseLiteral, falseLiteral),
            Expr.ifThenElse(falseLiteral, falseLiteral, trueLiteral)
        )
        XCTAssertLessThan(Expr.set([falseLiteral]), Expr.set([trueLiteral]))
        XCTAssertLessThan(
            Expr.record([(key: "alpha", value: falseLiteral)]),
            Expr.record([(key: "beta", value: falseLiteral)])
        )
        XCTAssertLessThan(Expr.hasAttr(falseLiteral, "alpha"), Expr.hasAttr(falseLiteral, "beta"))
        XCTAssertLessThan(Expr.getAttr(falseLiteral, "alpha"), Expr.getAttr(falseLiteral, "beta"))
        XCTAssertLessThan(Expr.like(falseLiteral, decomposedPattern), Expr.like(falseLiteral, composedPattern))
        XCTAssertLessThan(
            Expr.isEntityType(falseLiteral, Name(id: "Admin")),
            Expr.isEntityType(falseLiteral, Name(id: "User"))
        )
        XCTAssertLessThan(Expr.call(.decimal, [falseLiteral]), Expr.call(.ip, [falseLiteral]))
    }

    func testExprAttrNamesUseScalarStrictStringSemantics() {
        let base = Expr.variable(.context)
        let composed = Expr.hasAttr(base, composedEAcute)
        let decomposed = Expr.hasAttr(base, decomposedEAcute)

        XCTAssertNotEqual(composed, decomposed)
        XCTAssertLessThan(decomposed, composed)
    }

    func testExprLogicalConditionalAndMembershipMappingsStayFrozen() {
        let lhs = Expr.lit(.prim(.bool(true)))
        let rhs = Expr.lit(.prim(.bool(false)))
        let andExpr = Expr.binaryApp(.and, lhs, rhs)
        let orExpr = Expr.binaryApp(.or, lhs, rhs)
        let inExpr = Expr.binaryApp(.in, .variable(.principal), .variable(.resource))
        let conditional = Expr.ifThenElse(lhs, .variable(.action), .variable(.context))

        guard case let .binaryApp(andOp, andLHS, andRHS) = andExpr else {
            return XCTFail("Expected binary and expression")
        }

        guard case let .binaryApp(orOp, orLHS, orRHS) = orExpr else {
            return XCTFail("Expected binary or expression")
        }

        guard case let .binaryApp(inOp, inLHS, inRHS) = inExpr else {
            return XCTFail("Expected binary membership expression")
        }

        guard case let .ifThenElse(condition, thenExpr, elseExpr) = conditional else {
            return XCTFail("Expected conditional expression")
        }

        XCTAssertEqual(andOp, .and)
        XCTAssertEqual(andLHS, lhs)
        XCTAssertEqual(andRHS, rhs)
        XCTAssertEqual(orOp, .or)
        XCTAssertEqual(orLHS, lhs)
        XCTAssertEqual(orRHS, rhs)
        XCTAssertEqual(inOp, .in)
        XCTAssertEqual(inLHS, .variable(.principal))
        XCTAssertEqual(inRHS, .variable(.resource))
        XCTAssertEqual(condition, lhs)
        XCTAssertEqual(thenExpr, .variable(.action))
        XCTAssertEqual(elseExpr, .variable(.context))
    }

    func testExprDedicatedPredicateCasesRemainSeparateFromBinaryAndUnaryOperators() {
        let base = Expr.variable(.resource)
        let pattern = Pattern(Array("photo-*".unicodeScalars).map(PatElem.literal))
        let entityType = Name(id: "Photo")
        let like = Expr.like(base, pattern)
        let hasAttr = Expr.hasAttr(base, "owner")
        let getAttr = Expr.getAttr(base, "owner")
        let isEntityType = Expr.isEntityType(base, entityType)

        guard case let .like(likeExpr, likePattern) = like else {
            return XCTFail("Expected like expression")
        }

        guard case let .hasAttr(hasAttrExpr, hasAttrName) = hasAttr else {
            return XCTFail("Expected hasAttr expression")
        }

        guard case let .getAttr(getAttrExpr, getAttrName) = getAttr else {
            return XCTFail("Expected getAttr expression")
        }

        guard case let .isEntityType(typeExpr, typeName) = isEntityType else {
            return XCTFail("Expected isEntityType expression")
        }

        XCTAssertEqual(likeExpr, base)
        XCTAssertEqual(likePattern, pattern)
        XCTAssertEqual(hasAttrExpr, base)
        XCTAssertEqual(hasAttrName, "owner")
        XCTAssertEqual(getAttrExpr, base)
        XCTAssertEqual(getAttrName, "owner")
        XCTAssertEqual(typeExpr, base)
        XCTAssertEqual(typeName, entityType)
    }

    func testExprRecordLiteralPreservesSourceOrder() {
        let record = Expr.record([
            (key: composedEAcute, value: .lit(.prim(.string("composed")))),
            (key: decomposedEAcute, value: .lit(.prim(.string("decomposed")))),
        ])

        guard case let .record(entries) = record else {
            return XCTFail("Expected record expression")
        }

        XCTAssertEqual(entries.map(\.key), [composedEAcute, decomposedEAcute])
    }

    func testExprRecordLiteralPreservesDuplicateKeys() {
        let firstValue = Expr.lit(.prim(.string("first")))
        let secondValue = Expr.lit(.prim(.string("second")))
        let record = Expr.record([
            (key: "department", value: firstValue),
            (key: "department", value: secondValue),
        ])

        guard case let .record(map) = record else {
            return XCTFail("Expected record expression")
        }

        XCTAssertEqual(map.map(\.key), ["department", "department"])
        XCTAssertEqual(map.map(\.value), [firstValue, secondValue])
    }
}
