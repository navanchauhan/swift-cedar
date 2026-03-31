import XCTest
@testable import CedarSpecSwift

final class DatetimeExtTests: XCTestCase {
    func testDatetimeParseMatchesReferenceNormalizationAndCanonicalRendering() throws {
        XCTAssertEqual(
            datetimeCanonicalString(try XCTUnwrap(datetimeParse("2024-01-01"))),
            "2024-01-01T00:00:00.000Z"
        )
        XCTAssertEqual(
            datetimeCanonicalString(try XCTUnwrap(datetimeParse("2024-01-01T01:00:00+0100"))),
            "2024-01-01T00:00:00.000Z"
        )
        XCTAssertEqual(
            datetimeCanonicalString(try XCTUnwrap(datetimeParse("2024-01-01T00:00:00.045Z"))),
            "2024-01-01T00:00:00.045Z"
        )
    }

    func testDatetimeParseRejectsMalformedInputs() {
        XCTAssertNil(datetimeParse("2024-02-30"))
        XCTAssertNil(datetimeParse("2024-01-01T00:00:60Z"))
        XCTAssertNil(datetimeParse("2024-1-01"))
        XCTAssertNil(datetimeParse("2024-01-01T00:00:00+2460"))
        XCTAssertNil(datetimeParse("2024-01-01T00:00:00+2400"))
        XCTAssertNil(datetimeParse("2024-01-01T00:00:00.12Z"))
    }

    func testDatetimeInvalidDirectPayloadFallbacksRemainDeterministicAcrossPublicSemanticSurfaces() {
        let valid = Ext.Datetime(rawValue: "2024-01-01")
        let invalid = Ext.Datetime(rawValue: "2024-01-01T00:00:60Z")
        let invalidAlias = Ext.Datetime(rawValue: "2024-01-01T00:00:60Z")

        XCTAssertEqual(Ext.datetime(invalid), Ext.datetime(invalidAlias))
        XCTAssertEqual(CedarValue.ext(.datetime(invalid)), CedarValue.ext(.datetime(invalidAlias)))
        XCTAssertLessThan(Ext.datetime(valid), Ext.datetime(invalid))
        XCTAssertLessThan(CedarValue.ext(.datetime(valid)), CedarValue.ext(.datetime(invalid)))

        let set = CedarSet.make([
            CedarValue.ext(.datetime(invalid)),
            CedarValue.ext(.datetime(valid)),
            CedarValue.ext(.datetime(invalidAlias)),
        ])

        XCTAssertEqual(set.elements, [
            CedarValue.ext(.datetime(valid)),
            CedarValue.ext(.datetime(invalid)),
        ])
    }

    func testDatetimeDispatchCoversConstructorOffsetDurationSinceAndDateTimeViews() {
        XCTAssertEqual(
            dispatchExtensionCall(.datetime, arguments: [.prim(.string("2024-01-01T01:00:00+0100"))]),
            .success(.ext(.datetime(.init(rawValue: "2024-01-01T01:00:00+0100"))))
        )
        XCTAssertEqual(
            dispatchExtensionCall(.datetime, arguments: [.prim(.string("2024-01-01T00:00:60Z"))]),
            .failure(.extensionError)
        )
        XCTAssertEqual(
            dispatchExtensionCall(.datetime, arguments: []),
            .failure(.typeError)
        )
        XCTAssertEqual(
            dispatchExtensionCall(.datetime, arguments: [.prim(.int(1))]),
            .failure(.typeError)
        )

        XCTAssertEqual(
            dispatchExtensionCall(
                .offset,
                arguments: [
                    .ext(.datetime(.init(rawValue: "2024-01-01T00:00:00Z"))),
                    .ext(.duration(.init(rawValue: "90m"))),
                ]
            ),
            .success(.ext(.datetime(.init(rawValue: "2024-01-01T01:30:00.000Z"))))
        )
        XCTAssertEqual(
            dispatchExtensionCall(
                .durationSince,
                arguments: [
                    .ext(.datetime(.init(rawValue: "2024-01-01T01:30:00Z"))),
                    .ext(.datetime(.init(rawValue: "2024-01-01T00:00:00Z"))),
                ]
            ),
            .success(.ext(.duration(.init(rawValue: "1h30m"))))
        )
        XCTAssertEqual(
            dispatchExtensionCall(.toDate, arguments: [.ext(.datetime(.init(rawValue: "2024-01-01T18:20:30.045Z")))]),
            .success(.ext(.datetime(.init(rawValue: "2024-01-01T00:00:00.000Z"))))
        )
        XCTAssertEqual(
            dispatchExtensionCall(.toTime, arguments: [.ext(.datetime(.init(rawValue: "2024-01-01T18:20:30.045Z")))]),
            .success(.ext(.duration(.init(rawValue: "18h20m30s45ms"))))
        )
        XCTAssertEqual(
            dispatchExtensionCall(.offset, arguments: [.prim(.string("2024-01-01")), .ext(.duration(.init(rawValue: "1h")))]),
            .failure(.typeError)
        )
    }
}