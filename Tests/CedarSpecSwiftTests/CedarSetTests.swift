import XCTest
@testable import CedarSpecSwift

final class CedarSetTests: XCTestCase {
    private enum TestError: Error, Equatable {
        case fixed
        case transformFailed
        case unused
    }

    private let composedEAcute = "\u{00E9}"
    private let decomposedEAcute = "e\u{0301}"

    func testMakeSortsAndDeduplicates() {
        let set = CedarSet.make([3, 1, 2, 3, 2, 1])

        XCTAssertEqual(set.elements, [1, 2, 3])
    }

    func testEmptySetIsEmpty() {
        XCTAssertTrue(CedarSet<Int>.empty.isEmpty)
    }

    func testContainsUsesCanonicalContents() {
        let set = CedarSet.make([5, 3, 5, 1])

        XCTAssertTrue(set.contains(3))
        XCTAssertFalse(set.contains(4))
    }

    func testSubsetReturnsTrueForIncludedSet() {
        let smaller = CedarSet.make([1, 2])
        let larger = CedarSet.make([3, 2, 1])

        XCTAssertTrue(smaller.subset(of: larger))
    }

    func testSubsetReturnsFalseForExcludedElement() {
        let lhs = CedarSet.make([1, 4])
        let rhs = CedarSet.make([1, 2, 3])

        XCTAssertFalse(lhs.subset(of: rhs))
    }

    func testIntersectsReturnsTrueWhenSetsOverlap() {
        let lhs = CedarSet.make([1, 4])
        let rhs = CedarSet.make([2, 4, 6])

        XCTAssertTrue(lhs.intersects(with: rhs))
    }

    func testIntersectsReturnsFalseWhenSetsAreDisjoint() {
        let lhs = CedarSet.make([1, 3])
        let rhs = CedarSet.make([2, 4])

        XCTAssertFalse(lhs.intersects(with: rhs))
    }

    func testAnyAndAllReflectPredicateResults() {
        let set = CedarSet.make([1, 2, 3])

        XCTAssertTrue(set.any { $0.isMultiple(of: 2) })
        XCTAssertTrue(set.all { $0 > 0 })
        XCTAssertFalse(set.all { $0.isMultiple(of: 2) })
    }

    func testFilterKeepsCanonicalOrdering() {
        let set = CedarSet.make([4, 1, 3, 2])

        XCTAssertEqual(set.filter { $0.isMultiple(of: 2) }.elements, [2, 4])
    }

    func testMapOrErrCanonicalizesMappedValues() {
        let set = CedarSet.make([1, 2, 3])
        let result = set.mapOrErr({ .success(4 - $0) }, error: TestError.unused)

        XCTAssertEqual(try result.get().elements, [1, 2, 3])
    }

    func testMapOrErrReturnsFixedError() {
        let set = CedarSet.make([1, 2, 3])
        let result = set.mapOrErr({ value in
            value == 2 ? .failure(TestError.transformFailed) : .success(value)
        }, error: TestError.fixed)

        switch result {
        case .success:
            XCTFail("Expected failure")
        case let .failure(error):
            XCTAssertEqual(error, .fixed)
        }
    }

    func testMakeKeepsCanonicalEquivalentButScalarDistinctStringsSeparate() {
        let set = CedarSet.make([composedEAcute, decomposedEAcute, composedEAcute])

        XCTAssertEqual(set.elements, [decomposedEAcute, composedEAcute])
        XCTAssertTrue(set.contains(decomposedEAcute))
        XCTAssertTrue(set.contains(composedEAcute))
    }
}
