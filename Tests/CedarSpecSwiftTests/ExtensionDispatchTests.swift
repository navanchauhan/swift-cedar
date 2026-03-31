import XCTest
@testable import CedarSpecSwift

final class ExtensionDispatchTests: XCTestCase {
    func testC3SharedComparisonSeamKeepsScalarEqualityBehavior() {
        XCTAssertEqual(
            applySharedComparison(
                .equal,
                lhs: .prim(.string("cedar")),
                rhs: .prim(.string("cedar"))
            ),
            .success(.prim(.bool(true)))
        )
    }

    func testC3SharedComparisonSeamKeepsScalarLessThanBehavior() {
        XCTAssertEqual(
            applySharedComparison(
                .lessThan,
                lhs: .prim(.int(1)),
                rhs: .prim(.int(2))
            ),
            .success(.prim(.bool(true)))
        )
    }

    func testC3SharedComparisonSeamKeepsScalarLessThanOrEqualBehavior() {
        XCTAssertEqual(
            applySharedComparison(
                .lessThanOrEqual,
                lhs: .prim(.int(2)),
                rhs: .prim(.int(2))
            ),
            .success(.prim(.bool(true)))
        )
    }

    func testC4aSharedComparisonSeamSupportsDecimalEqualityAndStillRejectsInvalidTemporalPayloads() {
        let normalized = CedarValue.record(CedarMap.make([
            (key: "nested", value: .ext(.decimal(.init(rawValue: "1.2300")))),
        ]))
        let differentlyScaled = CedarValue.record(CedarMap.make([
            (key: "nested", value: .ext(.decimal(.init(rawValue: "1.23")))),
        ]))
        let invalidTemporal = CedarValue.record(CedarMap.make([
            (key: "nested", value: .ext(.duration(.init(rawValue: "PT1H")))),
        ]))

        XCTAssertEqual(
            applySharedComparison(.equal, lhs: normalized, rhs: differentlyScaled),
            .success(.prim(.bool(true)))
        )
        XCTAssertEqual(
            applySharedComparison(.equal, lhs: invalidTemporal, rhs: invalidTemporal),
            .failure(.extensionError)
        )
    }

    func testC5SharedComparisonSeamSupportsDatetimeAndDurationEquality() {
        let normalizedDatetime = CedarValue.record(CedarMap.make([
            (key: "nested", value: .ext(.datetime(.init(rawValue: "2024-01-01")))),
        ]))
        let differentlySpelledDatetime = CedarValue.record(CedarMap.make([
            (key: "nested", value: .ext(.datetime(.init(rawValue: "2024-01-01T00:00:00Z")))),
        ]))
        let normalizedDuration = CedarValue.record(CedarMap.make([
            (key: "nested", value: .ext(.duration(.init(rawValue: "60m")))),
        ]))
        let differentlySpelledDuration = CedarValue.record(CedarMap.make([
            (key: "nested", value: .ext(.duration(.init(rawValue: "1h")))),
        ]))

        XCTAssertEqual(
            applySharedComparison(.equal, lhs: normalizedDatetime, rhs: differentlySpelledDatetime),
            .success(.prim(.bool(true)))
        )
        XCTAssertEqual(
            applySharedComparison(.equal, lhs: normalizedDuration, rhs: differentlySpelledDuration),
            .success(.prim(.bool(true)))
        )
    }

    func testC4bSharedComparisonSeamSupportsIPAddrEqualityAndTemporalFamiliesAreNowSupported() {
        let normalized = CedarValue.record(CedarMap.make([
            (key: "nested", value: .ext(.ipaddr(.init(rawValue: "127.0.0.1")))),
        ]))
        let differentlySpelled = CedarValue.record(CedarMap.make([
            (key: "nested", value: .ext(.ipaddr(.init(rawValue: "127.0.0.1/32")))),
        ]))
        let supportedTemporal = CedarValue.record(CedarMap.make([
            (key: "nested", value: .ext(.datetime(.init(rawValue: "2024-01-01T01:00:00+0100")))),
        ]))
        let supportedTemporalAlias = CedarValue.record(CedarMap.make([
            (key: "nested", value: .ext(.datetime(.init(rawValue: "2024-01-01T00:00:00Z")))),
        ]))

        XCTAssertEqual(
            applySharedComparison(.equal, lhs: normalized, rhs: differentlySpelled),
            .success(.prim(.bool(true)))
        )
        XCTAssertEqual(
            applySharedComparison(.equal, lhs: supportedTemporal, rhs: supportedTemporalAlias),
            .success(.prim(.bool(true)))
        )
    }

    func testC4aSharedComparisonSeamMapsUnsupportedDecimalLessOperatorsToTypeError() {
        let directDecimal = CedarValue.ext(.decimal(.init(rawValue: "1.23")))

        XCTAssertEqual(
            applySharedComparison(.lessThan, lhs: directDecimal, rhs: directDecimal),
            .failure(.typeError)
        )
        XCTAssertEqual(
            applySharedComparison(.lessThanOrEqual, lhs: directDecimal, rhs: directDecimal),
            .failure(.typeError)
        )
    }

    func testC4bSharedComparisonSeamMapsUnsupportedIPAddrAndMixedFamilyLessOperatorsToTypeError() {
        let directIPAddr = CedarValue.ext(.ipaddr(.init(rawValue: "127.0.0.1")))

        XCTAssertEqual(
            applySharedComparison(.lessThan, lhs: directIPAddr, rhs: directIPAddr),
            .failure(.typeError)
        )
        XCTAssertEqual(
            applySharedComparison(.lessThanOrEqual, lhs: directIPAddr, rhs: directIPAddr),
            .failure(.typeError)
        )
        XCTAssertEqual(
            applySharedComparison(
                .lessThan,
                lhs: .ext(.datetime(.init(rawValue: "2024-01-01T00:00:00Z"))),
                rhs: .ext(.duration(.init(rawValue: "1h")))
            ),
            .failure(.typeError)
        )
    }

    func testC5SharedComparisonSeamSupportsDirectTemporalLessOperators() {
        XCTAssertEqual(
            applySharedComparison(
                .lessThan,
                lhs: .ext(.datetime(.init(rawValue: "2024-01-01T00:00:00Z"))),
                rhs: .ext(.datetime(.init(rawValue: "2024-01-01T00:00:00.001Z")))
            ),
            .success(.prim(.bool(true)))
        )
        XCTAssertEqual(
            applySharedComparison(
                .lessThanOrEqual,
                lhs: .ext(.duration(.init(rawValue: "60m"))),
                rhs: .ext(.duration(.init(rawValue: "1h")))
            ),
            .success(.prim(.bool(true)))
        )
        XCTAssertEqual(
            applySharedComparison(
                .lessThan,
                lhs: .ext(.datetime(.init(rawValue: "2024-01-01T00:00:60Z"))),
                rhs: .ext(.datetime(.init(rawValue: "2024-01-01T00:00:00Z")))
            ),
            .failure(.extensionError)
        )
    }

    func testC4aSharedCallDispatchSupportsDecimalConstructorAndComparisonCases() {
        XCTAssertEqual(
            dispatchExtensionCall(.decimal, arguments: [.prim(.string("1.2300"))]),
            .success(.ext(.decimal(.init(rawValue: "1.2300"))))
        )
        XCTAssertEqual(
            dispatchExtensionCall(
                .greaterThan,
                arguments: [
                    .ext(.decimal(.init(rawValue: "1.2300"))),
                    .ext(.decimal(.init(rawValue: "1.2"))),
                ]
            ),
            .success(.prim(.bool(true)))
        )
    }

    func testC4bSharedCallDispatchSupportsIPAddrConstructorPredicatesAndRangeCases() {
        XCTAssertEqual(
            dispatchExtensionCall(.ip, arguments: [.prim(.string("127.0.0.1"))]),
            .success(.ext(.ipaddr(.init(rawValue: "127.0.0.1"))))
        )
        XCTAssertEqual(
            dispatchExtensionCall(.isIpv4, arguments: [.ext(.ipaddr(.init(rawValue: "127.0.0.1")))]),
            .success(.prim(.bool(true)))
        )
        XCTAssertEqual(
            dispatchExtensionCall(.isLoopback, arguments: [.ext(.ipaddr(.init(rawValue: "::1")))]),
            .success(.prim(.bool(true)))
        )
        XCTAssertEqual(
            dispatchExtensionCall(
                .isInRange,
                arguments: [
                    .ext(.ipaddr(.init(rawValue: "10.0.0.1"))),
                    .ext(.ipaddr(.init(rawValue: "10.0.0.0/24"))),
                ]
            ),
            .success(.prim(.bool(true)))
        )
    }

    func testC5SharedCallDispatchSupportsTemporalConstructorsAndTransforms() {
        XCTAssertEqual(
            dispatchExtensionCall(.datetime, arguments: [.prim(.string("2024-01-01"))]),
            .success(.ext(.datetime(.init(rawValue: "2024-01-01"))))
        )
        XCTAssertEqual(
            dispatchExtensionCall(.duration, arguments: [.prim(.string("1h"))]),
            .success(.ext(.duration(.init(rawValue: "1h"))))
        )
        XCTAssertEqual(
            dispatchExtensionCall(
                .offset,
                arguments: [
                    .ext(.datetime(.init(rawValue: "2024-01-01T00:00:00Z"))),
                    .ext(.duration(.init(rawValue: "1h"))),
                ]
            ),
            .success(.ext(.datetime(.init(rawValue: "2024-01-01T01:00:00.000Z"))))
        )
        XCTAssertEqual(
            dispatchExtensionCall(
                .toHours,
                arguments: [.ext(.duration(.init(rawValue: "1d2h")))]
            ),
            .success(.prim(.int(26)))
        )
    }

    func testC5SharedCallDispatchDistinguishesParseFailureAndTypeFailureForTemporalFamilies() {
        XCTAssertEqual(
            dispatchExtensionCall(.decimal, arguments: [.prim(.string("1.23456"))]),
            .failure(.extensionError)
        )
        XCTAssertEqual(
            dispatchExtensionCall(.decimal, arguments: []),
            .failure(.typeError)
        )
        XCTAssertEqual(
            dispatchExtensionCall(.lessThan, arguments: [.prim(.int(1)), .prim(.int(2))]),
            .failure(.typeError)
        )
        XCTAssertEqual(
            dispatchExtensionCall(.ip, arguments: [.prim(.string("::ffff:127.0.0.1"))]),
            .failure(.extensionError)
        )
        XCTAssertEqual(
            dispatchExtensionCall(.isInRange, arguments: [.prim(.int(1)), .prim(.int(2))]),
            .failure(.typeError)
        )
        XCTAssertEqual(
            dispatchExtensionCall(.datetime, arguments: [.prim(.string("2024-01-01T00:00:60Z"))]),
            .failure(.extensionError)
        )
        XCTAssertEqual(
            dispatchExtensionCall(.duration, arguments: [.prim(.string("PT1H"))]),
            .failure(.extensionError)
        )
        XCTAssertEqual(
            dispatchExtensionCall(.toDate, arguments: [.prim(.int(1))]),
            .failure(.typeError)
        )
    }

    func testC5ExtensionBearingSetMakeUsesTemporalSemanticEqualityAndFamilyOrder() {
        let decimal = CedarValue.ext(.decimal(.init(rawValue: "1.20")))
        let decimalAlias = CedarValue.ext(.decimal(.init(rawValue: "1.2000")))
        let ipaddr = CedarValue.ext(.ipaddr(.init(rawValue: "10.0.0.0/8")))
        let datetime = CedarValue.ext(.datetime(.init(rawValue: "2024-01-01T01:00:00+0100")))
        let datetimeAlias = CedarValue.ext(.datetime(.init(rawValue: "2024-01-01T00:00:00Z")))
        let duration = CedarValue.ext(.duration(.init(rawValue: "60m")))
        let durationAlias = CedarValue.ext(.duration(.init(rawValue: "1h")))

        let canonical = CedarSet.make([duration, datetime, decimal, ipaddr, durationAlias, decimalAlias, datetimeAlias])
        let reordered = CedarSet.make([ipaddr, durationAlias, datetimeAlias, decimalAlias])

        XCTAssertEqual(canonical.elements, [decimal, ipaddr, datetime, duration])
        XCTAssertEqual(canonical, reordered)
    }

    func testC4aExtensionBearingMapMakeKeepsEarliestDecimalSourceSpellingForDuplicateKeys() {
        let map = CedarMap.make([
            (key: "zeta", value: CedarValue.ext(.duration(.init(rawValue: "60m")))),
            (key: "alpha", value: CedarValue.ext(.decimal(.init(rawValue: "1.2000")))),
            (key: "alpha", value: CedarValue.ext(.decimal(.init(rawValue: "1.20")))),
            (key: "zeta", value: CedarValue.ext(.ipaddr(.init(rawValue: "10.0.0.0/8")))),
        ])

        XCTAssertEqual(map.entries.map(\.key), ["alpha", "zeta"])
        XCTAssertEqual(map.find("alpha"), .ext(.decimal(.init(rawValue: "1.2000"))))
        XCTAssertEqual(map.find("zeta"), .ext(.duration(.init(rawValue: "60m"))))
    }
}
