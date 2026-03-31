import XCTest
@testable import CedarSpecSwift

final class ValueTests: XCTestCase {
    private let composedEAcute = "\u{00E9}"
    private let decomposedEAcute = "e\u{0301}"

    func testNameDescriptionAndOrderingFollowReferenceShape() {
        let user = Name(id: "User", path: ["App"])
        let group = Name(id: "Group", path: ["App"])

        XCTAssertEqual(user.description, "App::User")
        XCTAssertLessThan(group, user)
    }

    func testNameOrderingUsesIDThenPathLexicographicComparison() {
        XCTAssertLessThan(
            Name(id: "Alpha", path: ["Zoo"]),
            Name(id: "Beta", path: [])
        )
        XCTAssertLessThan(
            Name(id: "User", path: []),
            Name(id: "User", path: ["App"])
        )
        XCTAssertLessThan(
            Name(id: "User", path: ["App"]),
            Name(id: "User", path: ["Team"])
        )
    }

    func testEntityUIDOrderingUsesTypeThenEID() {
        let groupType = Name(id: "Group", path: ["App"])
        let userType = Name(id: "User", path: ["App"])
        let first = EntityUID(ty: groupType, eid: "alpha")
        let second = EntityUID(ty: userType, eid: "beta")
        let third = EntityUID(ty: userType, eid: "gamma")

        XCTAssertLessThan(first, second)
        XCTAssertLessThan(second, third)
    }

    func testScalarDistinctNamesAreNotEqualAndUseScalarOrdering() {
        let composed = Name(id: composedEAcute, path: ["Cafe"])
        let decomposed = Name(id: decomposedEAcute, path: ["Cafe"])

        XCTAssertNotEqual(composed, decomposed)
        XCTAssertLessThan(decomposed, composed)
    }

    func testScalarDistinctNamePathComponentsRemainDistinct() {
        let composed = Name(id: "User", path: [composedEAcute])
        let decomposed = Name(id: "User", path: [decomposedEAcute])

        XCTAssertNotEqual(composed, decomposed)
        XCTAssertLessThan(decomposed, composed)
    }

    func testScalarDistinctEntityUIDsRemainDistinct() {
        let type = Name(id: "User")
        let composed = EntityUID(ty: type, eid: composedEAcute)
        let decomposed = EntityUID(ty: type, eid: decomposedEAcute)

        XCTAssertNotEqual(composed, decomposed)
        XCTAssertLessThan(decomposed, composed)
    }

    func testPrimComparableUsesLeanConstructorOrder() {
        let typeName = Name(id: "User")
        let entity = EntityUID(ty: typeName, eid: "alice")
        let prims: [Prim] = [
            .entityUID(entity),
            .string("cedar"),
            .int(7),
            .bool(false),
        ]

        XCTAssertEqual(prims.sorted(), [
            .bool(false),
            .int(7),
            .string("cedar"),
            .entityUID(entity),
        ])
    }

    func testScalarDistinctPrimitiveStringsRemainDistinct() {
        let composed = Prim.string(composedEAcute)
        let decomposed = Prim.string(decomposedEAcute)

        XCTAssertNotEqual(composed, decomposed)
        XCTAssertLessThan(decomposed, composed)
    }

    func testRecordCanonicalizationUsesStringAttrOrder() {
        let zeta = "zeta"
        let alpha = "alpha"
        let record = CedarValue.record(CedarMap.make([
            (key: zeta, value: .prim(.string("last"))),
            (key: alpha, value: .prim(.string("first"))),
        ]))

        guard case let .record(map) = record else {
            return XCTFail("Expected record value")
        }

        XCTAssertEqual(map.entries.map(\.key), [alpha, zeta])
    }

    func testRecordCanonicalizationKeepsScalarDistinctAttrKeysSeparate() {
        let record = CedarValue.record(CedarMap.make([
            (key: composedEAcute, value: .prim(.string("composed"))),
            (key: decomposedEAcute, value: .prim(.string("decomposed"))),
        ]))

        guard case let .record(map) = record else {
            return XCTFail("Expected record value")
        }

        XCTAssertEqual(map.entries.map(\.key), [decomposedEAcute, composedEAcute])
        XCTAssertEqual(map.find(decomposedEAcute), .prim(.string("decomposed")))
        XCTAssertEqual(map.find(composedEAcute), .prim(.string("composed")))
    }

    func testRecordValueOrderingUsesCanonicalStringAttrOrder() {
        let alphaRecord = CedarValue.record(CedarMap.make([
            (key: "alpha", value: .prim(.int(1))),
        ]))
        let betaRecord = CedarValue.record(CedarMap.make([
            (key: "beta", value: .prim(.int(1))),
        ]))
        let higherValueRecord = CedarValue.record(CedarMap.make([
            (key: "alpha", value: .prim(.int(2))),
        ]))

        XCTAssertLessThan(alphaRecord, betaRecord)
        XCTAssertLessThan(alphaRecord, higherValueRecord)
    }

    func testCedarValueComparableUsesLeanConstructorOrder() {
        let values: [CedarValue] = [
            .ext(.duration(.init(rawValue: "1h"))),
            .record(CedarMap.make([(key: "role", value: .prim(.bool(true)))])),
            .set(CedarSet.make([.prim(.int(1))])),
            .prim(.bool(false)),
        ]

        XCTAssertEqual(values.sorted(), [
            .prim(.bool(false)),
            .set(CedarSet.make([.prim(.int(1))])),
            .record(CedarMap.make([(key: "role", value: .prim(.bool(true)))])),
            .ext(.duration(.init(rawValue: "1h"))),
        ])
    }

    func testNestedSetAndRecordEqualityAndHashAreCanonical() {
        let alpha = "alpha"
        let beta = "beta"
        let left: CedarValue = .set(CedarSet.make([
            .record(CedarMap.make([
                (key: beta, value: .prim(.bool(true))),
                (key: alpha, value: .prim(.int(42))),
            ])),
            .ext(.decimal(.init(rawValue: "1.2300"))),
        ]))
        let right: CedarValue = .set(CedarSet.make([
            .ext(.decimal(.init(rawValue: "1.23"))),
            .record(CedarMap.make([
                (key: alpha, value: .prim(.int(42))),
                (key: beta, value: .prim(.bool(true))),
            ])),
        ]))

        XCTAssertEqual(left, right)
        XCTAssertEqual(hash(of: left), hash(of: right))
    }

    func testDecimalCedarValueOrderingAndRecordEqualityUseSemanticComparison() {
        XCTAssertLessThan(
            CedarValue.ext(.decimal(.init(rawValue: "-1.5000"))),
            CedarValue.ext(.decimal(.init(rawValue: "-1.4999")))
        )

        let left = CedarValue.record(CedarMap.make([
            (key: "amount", value: .ext(.decimal(.init(rawValue: "1.2000")))),
        ]))
        let right = CedarValue.record(CedarMap.make([
            (key: "amount", value: .ext(.decimal(.init(rawValue: "1.2")))),
        ]))

        XCTAssertEqual(left, right)
        XCTAssertEqual(hash(of: left), hash(of: right))
    }

    func testIPAddrCedarValueOrderingAndContainersUseSemanticComparison() {
        XCTAssertLessThan(
            CedarValue.ext(.ipaddr(.init(rawValue: "10.0.0.0/24"))),
            CedarValue.ext(.ipaddr(.init(rawValue: "10.0.0.0")))
        )

        let left = CedarValue.record(CedarMap.make([
            (key: "addr", value: .ext(.ipaddr(.init(rawValue: "127.0.0.1")))),
        ]))
        let right = CedarValue.record(CedarMap.make([
            (key: "addr", value: .ext(.ipaddr(.init(rawValue: "127.0.0.1/32")))),
        ]))
        let preferred = CedarValue.ext(.ipaddr(.init(rawValue: "127.0.0.1")))
        let alias = CedarValue.ext(.ipaddr(.init(rawValue: "127.0.0.1/32")))
        let ipv6 = CedarValue.ext(.ipaddr(.init(rawValue: "::1")))
        let set = CedarSet.make([ipv6, preferred, alias])
        let map = CedarMap.make([
            (key: "other", value: ipv6),
            (key: "addr", value: preferred),
            (key: "addr", value: alias),
        ])

        XCTAssertEqual(left, right)
        XCTAssertEqual(hash(of: left), hash(of: right))
        XCTAssertEqual(set.elements, [preferred, ipv6])
        XCTAssertEqual(map.find("addr"), preferred)
    }

    func testDatetimeCedarValueOrderingAndContainersUseSemanticComparison() {
        XCTAssertLessThan(
            CedarValue.ext(.datetime(.init(rawValue: "2024-01-01T00:00:00Z"))),
            CedarValue.ext(.datetime(.init(rawValue: "2024-01-01T00:00:00.001Z")))
        )

        let left = CedarValue.record(CedarMap.make([
            (key: "when", value: .ext(.datetime(.init(rawValue: "2024-01-01")))),
        ]))
        let right = CedarValue.record(CedarMap.make([
            (key: "when", value: .ext(.datetime(.init(rawValue: "2024-01-01T00:00:00Z")))),
        ]))
        let preferred = CedarValue.ext(.datetime(.init(rawValue: "2024-01-01T01:00:00+0100")))
        let alias = CedarValue.ext(.datetime(.init(rawValue: "2024-01-01T00:00:00Z")))
        let later = CedarValue.ext(.datetime(.init(rawValue: "2024-01-01T00:00:00.001Z")))
        let set = CedarSet.make([later, preferred, alias])
        let map = CedarMap.make([
            (key: "other", value: later),
            (key: "when", value: preferred),
            (key: "when", value: alias),
        ])

        XCTAssertEqual(left, right)
        XCTAssertEqual(hash(of: left), hash(of: right))
        XCTAssertEqual(set.elements, [preferred, later])
        XCTAssertEqual(map.find("when"), preferred)
    }

    func testDurationCedarValueOrderingAndContainersUseSemanticComparison() {
        XCTAssertLessThan(
            CedarValue.ext(.duration(.init(rawValue: "59m59s999ms"))),
            CedarValue.ext(.duration(.init(rawValue: "1h")))
        )

        let left = CedarValue.record(CedarMap.make([
            (key: "ttl", value: .ext(.duration(.init(rawValue: "60m")))),
        ]))
        let right = CedarValue.record(CedarMap.make([
            (key: "ttl", value: .ext(.duration(.init(rawValue: "1h")))),
        ]))
        let preferred = CedarValue.ext(.duration(.init(rawValue: "60m")))
        let alias = CedarValue.ext(.duration(.init(rawValue: "1h")))
        let longer = CedarValue.ext(.duration(.init(rawValue: "1h1ms")))
        let set = CedarSet.make([longer, preferred, alias])
        let map = CedarMap.make([
            (key: "other", value: longer),
            (key: "ttl", value: preferred),
            (key: "ttl", value: alias),
        ])

        XCTAssertEqual(left, right)
        XCTAssertEqual(hash(of: left), hash(of: right))
        XCTAssertEqual(set.elements, [preferred, longer])
        XCTAssertEqual(map.find("ttl"), preferred)
    }

    func testSetOfScalarDistinctPrimitiveStringsStaysDeterministic() {
        let set = CedarSet.make([
            CedarValue.prim(.string(composedEAcute)),
            CedarValue.prim(.string(decomposedEAcute)),
            CedarValue.prim(.string(composedEAcute)),
        ])

        XCTAssertEqual(set.elements, [
            .prim(.string(decomposedEAcute)),
            .prim(.string(composedEAcute)),
        ])
    }

    func testAsBoolSuccessAndFailure() throws {
        XCTAssertEqual(try CedarValue.prim(.bool(true)).asBool().get(), true)
        XCTAssertEqual(failure(of: CedarValue.prim(.int(1)).asBool()), .typeError)
    }

    func testAsIntSuccessAndFailure() throws {
        XCTAssertEqual(try CedarValue.prim(.int(42)).asInt().get(), 42)
        XCTAssertEqual(failure(of: CedarValue.prim(.string("42")).asInt()), .typeError)
    }

    func testAsStringSuccessAndFailure() throws {
        XCTAssertEqual(try CedarValue.prim(.string("cedar")).asString().get(), "cedar")
        XCTAssertEqual(failure(of: CedarValue.prim(.bool(false)).asString()), .typeError)
    }

    func testAsEntityUIDSuccessAndFailure() throws {
        let uid = EntityUID(ty: Name(id: "User"), eid: "alice")

        XCTAssertEqual(try CedarValue.prim(.entityUID(uid)).asEntityUID().get(), uid)
        XCTAssertEqual(failure(of: CedarValue.prim(.string("alice")).asEntityUID()), .typeError)
    }

    func testAsSetSuccessAndFailure() throws {
        let set = CedarSet.make([CedarValue.prim(.int(1))])

        XCTAssertEqual(try CedarValue.set(set).asSet().get(), set)
        XCTAssertEqual(failure(of: CedarValue.record(.empty).asSet()), .typeError)
    }

    private func hash(of value: some Hashable) -> Int {
        var hasher = Hasher()
        hasher.combine(value)
        return hasher.finalize()
    }

    private func failure<T>(of result: CedarResult<T>) -> CedarError {
        switch result {
        case .success:
            XCTFail("Expected failure")
            return .typeError
        case let .failure(error):
            return error
        }
    }
}
