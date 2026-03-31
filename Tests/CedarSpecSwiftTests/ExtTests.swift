import XCTest
@testable import CedarSpecSwift

final class ExtTests: XCTestCase {
    func testComparableUsesLeanConstructorOrder() {
        let values: [Ext] = [
            .duration(.init(rawValue: "1h")),
            .ipaddr(.init(rawValue: "10.0.0.0/8")),
            .decimal(.init(rawValue: "1.23")),
            .datetime(.init(rawValue: "2024-01-01T00:00:00Z")),
        ]

        XCTAssertEqual(values.sorted(), [
            .decimal(.init(rawValue: "1.23")),
            .ipaddr(.init(rawValue: "10.0.0.0/8")),
            .datetime(.init(rawValue: "2024-01-01T00:00:00Z")),
            .duration(.init(rawValue: "1h")),
        ])
    }

    func testDecimalEqualityUsesSemanticValueInsteadOfRawScale() {
        XCTAssertEqual(
            Ext.decimal(.init(rawValue: "1.2300")),
            Ext.decimal(.init(rawValue: "1.23"))
        )
    }

    func testDecimalOrderingUsesSemanticValueIncludingNegativeValues() {
        XCTAssertLessThan(
            Ext.decimal(.init(rawValue: "-1.5000")),
            Ext.decimal(.init(rawValue: "-1.0500"))
        )
        XCTAssertLessThan(
            Ext.decimal(.init(rawValue: "1.2000")),
            Ext.decimal(.init(rawValue: "1.2001"))
        )
    }

    func testIPAddrEqualityUsesSemanticValueInsteadOfSourceSpelling() {
        XCTAssertEqual(
            Ext.ipaddr(.init(rawValue: "127.0.0.1")),
            Ext.ipaddr(.init(rawValue: "127.0.0.1/32"))
        )
        XCTAssertEqual(
            Ext.ipaddr(.init(rawValue: "F:AE::F:5:F:F:0")),
            Ext.ipaddr(.init(rawValue: "000f:00ae:0000:000f:0005:000f:000f:0000/128"))
        )
    }

    func testIPAddrOrderingUsesSemanticValueAndKeepsV4BeforeV6() {
        XCTAssertLessThan(
            Ext.ipaddr(.init(rawValue: "10.0.0.0/24")),
            Ext.ipaddr(.init(rawValue: "10.0.0.0"))
        )
        XCTAssertLessThan(
            Ext.ipaddr(.init(rawValue: "10.0.0.1")),
            Ext.ipaddr(.init(rawValue: "::1"))
        )
    }

    func testDatetimeEqualityUsesSemanticInstantInsteadOfSourceSpelling() {
        XCTAssertEqual(
            Ext.datetime(.init(rawValue: "2024-01-01")),
            Ext.datetime(.init(rawValue: "2024-01-01T00:00:00Z"))
        )
        XCTAssertEqual(
            Ext.datetime(.init(rawValue: "2024-01-01T01:00:00+0100")),
            Ext.datetime(.init(rawValue: "2024-01-01T00:00:00Z"))
        )
    }

    func testDurationEqualityUsesSemanticMillisecondsInsteadOfUnits() {
        XCTAssertEqual(
            Ext.duration(.init(rawValue: "60m")),
            Ext.duration(.init(rawValue: "1h"))
        )
    }

    func testDatetimeAndDurationOrderingUseSemanticValues() {
        XCTAssertLessThan(
            Ext.datetime(.init(rawValue: "2024-01-01T00:00:00Z")),
            Ext.datetime(.init(rawValue: "2024-01-01T00:00:00.001Z"))
        )
        XCTAssertLessThan(
            Ext.duration(.init(rawValue: "59m59s999ms")),
            Ext.duration(.init(rawValue: "1h"))
        )
    }

    func testHashableMatchesDecimalSemanticEquality() {
        XCTAssertEqual(
            hash(of: Ext.decimal(.init(rawValue: "1.2300"))),
            hash(of: Ext.decimal(.init(rawValue: "1.23")))
        )
    }

    func testHashableMatchesIPAddrSemanticEquality() {
        XCTAssertEqual(
            hash(of: Ext.ipaddr(.init(rawValue: "127.0.0.1"))),
            hash(of: Ext.ipaddr(.init(rawValue: "127.0.0.1/32")))
        )
        XCTAssertEqual(
            hash(of: Ext.ipaddr(.init(rawValue: "F:AE::F:5:F:F:0"))),
            hash(of: Ext.ipaddr(.init(rawValue: "000f:00ae:0000:000f:0005:000f:000f:0000/128")))
        )
    }

    func testHashableMatchesDatetimeSemanticEquality() {
        XCTAssertEqual(
            hash(of: Ext.datetime(.init(rawValue: "2024-01-01"))),
            hash(of: Ext.datetime(.init(rawValue: "2024-01-01T00:00:00Z")))
        )
    }

    func testHashableMatchesDurationSemanticEquality() {
        XCTAssertEqual(
            hash(of: Ext.duration(.init(rawValue: "60m"))),
            hash(of: Ext.duration(.init(rawValue: "1h")))
        )
    }

    func testPayloadScaffoldingRemainsMinimalAndPubliclyConstructible() {
        let decimal = Ext.Decimal(rawValue: "1.23")
        let address = Ext.IPAddr(rawValue: "10.0.0.1")
        let datetime = Ext.Datetime(rawValue: "2024-01-01T00:00:00Z")
        let duration = Ext.Duration(rawValue: "1h")

        XCTAssertEqual(decimal.rawValue, "1.23")
        XCTAssertEqual(address.rawValue, "10.0.0.1")
        XCTAssertEqual(datetime.rawValue, "2024-01-01T00:00:00Z")
        XCTAssertEqual(duration.rawValue, "1h")
    }

    private func hash(of value: some Hashable) -> Int {
        var hasher = Hasher()
        hasher.combine(value)
        return hasher.finalize()
    }
}
