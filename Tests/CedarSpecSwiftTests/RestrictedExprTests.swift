import XCTest
@testable import CedarSpecSwift

final class RestrictedExprTests: XCTestCase {
    func testRestrictedExprRestrictAcceptsPrimitiveSetRecordAndConstructorCalls() throws {
        let user = EntityUID(ty: Name(id: "User"), eid: "alice")
        let expr = Expr.record([
            (key: "flag", value: .lit(.prim(.bool(true)))),
            (key: "owner", value: .lit(.prim(.entityUID(user)))),
            (key: "values", value: .set([
                .lit(.prim(.int(1))),
                .lit(.prim(.string("two"))),
            ])),
            (key: "ttl", value: .call(.duration, [.lit(.prim(.string("1h")))])),
            (key: "shifted", value: .call(
                .offset,
                [
                    .call(.datetime, [.lit(.prim(.string("2024-01-01")))]),
                    .call(.duration, [.lit(.prim(.string("1h")))]),
                ]
            )),
        ])

        let restricted = try RestrictedExpr.restrict(expr).get()

        XCTAssertEqual(
            restricted,
            .record(CedarMap.make([
                (key: "flag", value: .bool(true)),
                (key: "owner", value: .entityUID(user)),
                (key: "shifted", value: .call(
                    .offset,
                    [
                        .call(.datetime, [.string("2024-01-01")]),
                        .call(.duration, [.string("1h")]),
                    ]
                )),
                (key: "ttl", value: .call(.duration, [.string("1h")])),
                (key: "values", value: .set(CedarSet.make([
                    .int(1),
                    .string("two"),
                ]))),
            ]))
        )
        XCTAssertEqual(
            try restricted.materialize().get(),
            .record(CedarMap.make([
                (key: "flag", value: .prim(.bool(true))),
                (key: "owner", value: .prim(.entityUID(user))),
                (key: "shifted", value: .ext(.datetime(.init(rawValue: "2024-01-01T01:00:00.000Z")))),
                (key: "ttl", value: .ext(.duration(.init(rawValue: "1h")))),
                (key: "values", value: .set(CedarSet.make([
                    .prim(.int(1)),
                    .prim(.string("two")),
                ]))),
            ]))
        )
    }

    func testRestrictedExprRestrictRejectsUnrestrictedExprConstructors() {
        let uid = EntityUID(ty: Name(id: "User"), eid: "alice")
        let pattern = Pattern([.wildcard])
        let cases: [(Expr, RestrictedExprError)] = [
            (.variable(.context), .unsupportedExprConstructor(.variable)),
            (.unaryApp(.not, .lit(.prim(.bool(true)))), .unsupportedExprConstructor(.unaryApp)),
            (.binaryApp(.equal, .lit(.prim(.int(1))), .lit(.prim(.int(1)))), .unsupportedExprConstructor(.binaryApp)),
            (.ifThenElse(.lit(.prim(.bool(true))), .lit(.prim(.int(1))), .lit(.prim(.int(0)))), .unsupportedExprConstructor(.ifThenElse)),
            (.hasAttr(.variable(.principal), "department"), .unsupportedExprConstructor(.hasAttr)),
            (.getAttr(.variable(.principal), "department"), .unsupportedExprConstructor(.getAttr)),
            (.like(.lit(.prim(.string("alice"))), pattern), .unsupportedExprConstructor(.like)),
            (.isEntityType(.lit(.prim(.entityUID(uid))), Name(id: "User")), .unsupportedExprConstructor(.isEntityType)),
            (.lit(.ext(.decimal(.init(rawValue: "1.23")))), .unsupportedLiteral(.ext(.decimal(.init(rawValue: "1.23"))))),
            (.call(.lessThan, [.lit(.prim(.int(1))), .lit(.prim(.int(2)))]), .unsupportedExtensionFunction(.lessThan)),
        ]

        for (expr, expectedError) in cases {
            XCTAssertEqual(failure(of: RestrictedExpr.restrict(expr)), expectedError)
        }
    }

    func testRestrictedExprMaterializeReportsDeterministicFailures() {
        XCTAssertEqual(
            failure(of: RestrictedExpr.call(.lessThan, [.int(1), .int(2)]).materialize()),
            .unsupportedExtensionFunction(.lessThan)
        )
        XCTAssertEqual(
            failure(of: RestrictedExpr.call(.decimal, [.bool(true)]).materialize()),
            .invalidExtensionCallArguments(.decimal)
        )
        XCTAssertEqual(
            failure(of: RestrictedExpr.call(.duration, [.string("PT1H")]).materialize()),
            .extensionConstructorError(.duration)
        )
        XCTAssertEqual(
            failure(of: RestrictedExpr.bool(true).materializeRecord()),
            .contextMustBeRecord
        )
    }

    private func failure<T>(of result: Result<T, RestrictedExprError>) -> RestrictedExprError {
        switch result {
        case .success:
            XCTFail("Expected failure")
            return .contextMustBeRecord
        case let .failure(error):
            return error
        }
    }
}