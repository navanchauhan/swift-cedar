import XCTest
@testable import CedarSpecSwift

final class CedarMapTests: XCTestCase {
    private enum TestError: Error, Equatable {
        case missing
    }

    private let composedEAcute = "\u{00E9}"
    private let decomposedEAcute = "e\u{0301}"

    func testMakeSortsByKeyAndDeduplicatesKeepingFirstOccurrence() {
        let map = CedarMap.make([
            (key: 2, value: "first-two"),
            (key: 1, value: "first-one"),
            (key: 2, value: "second-two"),
            (key: 1, value: "second-one"),
        ])

        XCTAssertEqual(map.entries.map(\.key), [1, 2])
        XCTAssertEqual(map.values, ["first-one", "first-two"])
    }

    func testEmptyMapHasNoEntries() {
        XCTAssertTrue(CedarMap<Int, String>.empty.entries.isEmpty)
    }

    func testFindReturnsPresentValue() {
        let map = CedarMap.make([(key: 2, value: "two"), (key: 1, value: "one")])

        XCTAssertEqual(map.find(2), "two")
    }

    func testFindReturnsNilForMissingKey() {
        let map = CedarMap.make([(key: 1, value: "one")])

        XCTAssertNil(map.find(9))
    }

    func testFindOrErrReturnsValueForPresentKey() throws {
        let map = CedarMap.make([(key: 1, value: "one")])

        XCTAssertEqual(try map.findOrErr(1, error: TestError.missing).get(), "one")
    }

    func testFindOrErrReturnsProvidedErrorForMissingKey() {
        let map = CedarMap.make([(key: 1, value: "one")])

        switch map.findOrErr(2, error: TestError.missing) {
        case .success:
            XCTFail("Expected failure")
        case let .failure(error):
            XCTAssertEqual(error, .missing)
        }
    }

    func testContainsAndKeysReflectCanonicalMapContents() {
        let map = CedarMap.make([(key: 3, value: "three"), (key: 1, value: "one")])

        XCTAssertTrue(map.contains(1))
        XCTAssertFalse(map.contains(2))
        XCTAssertEqual(map.keys.elements, [1, 3])
    }

    func testFilterPreservesCanonicalOrder() {
        let map = CedarMap.make([
            (key: 3, value: "three"),
            (key: 1, value: "one"),
            (key: 2, value: "two"),
        ])

        let filtered = map.filter { key, _ in key >= 2 }
        XCTAssertEqual(filtered.entries.map(\.key), [2, 3])
        XCTAssertEqual(filtered.values, ["two", "three"])
    }

    func testMakeCanonicalizesStringAttrKeysForRecordMaps() {
        let attrs = CedarMap.make([
            (key: "zeta", value: 3),
            (key: "alpha", value: 1),
            (key: "beta", value: 2),
        ])

        XCTAssertEqual(attrs.entries.map(\.key), ["alpha", "beta", "zeta"])
        XCTAssertEqual(attrs.values, [1, 2, 3])
    }

    func testMakeKeepsCanonicalEquivalentButScalarDistinctStringKeysSeparate() {
        let attrs = CedarMap.make([
            (key: composedEAcute, value: "composed"),
            (key: decomposedEAcute, value: "decomposed"),
            (key: composedEAcute, value: "composed-updated"),
        ])

        XCTAssertEqual(attrs.entries.map(\.key), [decomposedEAcute, composedEAcute])
        XCTAssertEqual(attrs.values, ["decomposed", "composed"])
    }

    func testFindDistinguishesScalarDistinctStringKeys() {
        let attrs = CedarMap.make([
            (key: composedEAcute, value: 1),
            (key: decomposedEAcute, value: 2),
        ])

        XCTAssertEqual(attrs.find(decomposedEAcute), 2)
        XCTAssertEqual(attrs.find(composedEAcute), 1)
    }
}
