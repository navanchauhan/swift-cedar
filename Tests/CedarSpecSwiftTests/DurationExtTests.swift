import XCTest
@testable import CedarSpecSwift

final class DurationExtTests: XCTestCase {
    func testDurationParseMatchesReferenceOrderingAndCanonicalRendering() throws {
        XCTAssertEqual(try XCTUnwrap(durationParse("1d2h3m4s5ms")).milliseconds, 93_784_005)
        XCTAssertEqual(try XCTUnwrap(durationParse("-60m")).milliseconds, -3_600_000)
        XCTAssertEqual(durationCanonicalString(.init(milliseconds: 93_784_005)), "1d2h3m4s5ms")
        XCTAssertEqual(durationCanonicalString(.init(milliseconds: -3_600_000)), "-1h")
    }

    func testDurationParseRejectsMalformedInputs() {
        XCTAssertNil(durationParse(""))
        XCTAssertNil(durationParse("-"))
        XCTAssertNil(durationParse("ms"))
        XCTAssertNil(durationParse("1ms1s"))
        XCTAssertNil(durationParse("1h2h"))
        XCTAssertNil(durationParse("PT1H"))
    }

    func testDurationInvalidDirectPayloadFallbacksRemainDeterministicAcrossPublicSemanticSurfaces() {
        let valid = Ext.Duration(rawValue: "1h")
        let invalid = Ext.Duration(rawValue: "PT1H")
        let invalidAlias = Ext.Duration(rawValue: "PT1H")

        XCTAssertEqual(Ext.duration(invalid), Ext.duration(invalidAlias))
        XCTAssertEqual(CedarValue.ext(.duration(invalid)), CedarValue.ext(.duration(invalidAlias)))
        XCTAssertLessThan(Ext.duration(valid), Ext.duration(invalid))
        XCTAssertLessThan(CedarValue.ext(.duration(valid)), CedarValue.ext(.duration(invalid)))

        let map = CedarMap.make([
            (key: "beta", value: CedarValue.ext(.duration(invalid))),
            (key: "alpha", value: CedarValue.ext(.duration(valid))),
        ])

        XCTAssertEqual(map.entries.map(\.key), ["alpha", "beta"])
        XCTAssertEqual(map.find("beta"), .ext(.duration(invalid)))
    }

    func testDurationDispatchCoversConstructorConversionsAndShapeFailures() {
        XCTAssertEqual(
            dispatchExtensionCall(.duration, arguments: [.prim(.string("60m"))]),
            .success(.ext(.duration(.init(rawValue: "60m"))))
        )
        XCTAssertEqual(
            dispatchExtensionCall(.duration, arguments: [.prim(.string("PT1H"))]),
            .failure(.extensionError)
        )
        XCTAssertEqual(
            dispatchExtensionCall(.duration, arguments: []),
            .failure(.typeError)
        )
        XCTAssertEqual(
            dispatchExtensionCall(.duration, arguments: [.prim(.bool(true))]),
            .failure(.typeError)
        )

        let duration = CedarValue.ext(.duration(.init(rawValue: "1d2h3m4s5ms")))

        XCTAssertEqual(dispatchExtensionCall(.toMilliseconds, arguments: [duration]), .success(.prim(.int(93_784_005))))
        XCTAssertEqual(dispatchExtensionCall(.toSeconds, arguments: [duration]), .success(.prim(.int(93_784))))
        XCTAssertEqual(dispatchExtensionCall(.toMinutes, arguments: [duration]), .success(.prim(.int(1_563))))
        XCTAssertEqual(dispatchExtensionCall(.toHours, arguments: [duration]), .success(.prim(.int(26))))
        XCTAssertEqual(dispatchExtensionCall(.toDays, arguments: [duration]), .success(.prim(.int(1))))
        XCTAssertEqual(dispatchExtensionCall(.toHours, arguments: [.prim(.int(1))]), .failure(.typeError))
    }
}