import XCTest
@testable import CedarSpecSwift

final class CedarInt64Tests: XCTestCase {
    func testMinAndMaxExposeInt64Bounds() {
        XCTAssertEqual(CedarInt64.MIN, Int64.min)
        XCTAssertEqual(CedarInt64.MAX, Int64.max)
    }

    func testAddReturnsResultWhenInRange() {
        XCTAssertEqual(CedarInt64.add(40, 2), 42)
    }

    func testAddReturnsNilOnOverflow() {
        XCTAssertNil(CedarInt64.add(Int64.max, 1))
    }

    func testSubReturnsResultWhenInRange() {
        XCTAssertEqual(CedarInt64.sub(40, -2), 42)
    }

    func testSubReturnsNilOnUnderflow() {
        XCTAssertNil(CedarInt64.sub(Int64.min, 1))
    }

    func testMulReturnsResultWhenInRange() {
        XCTAssertEqual(CedarInt64.mul(6, 7), 42)
    }

    func testMulReturnsNilOnOverflow() {
        XCTAssertNil(CedarInt64.mul(Int64.max, 2))
    }

    func testNegReturnsResultWhenInRange() {
        XCTAssertEqual(CedarInt64.neg(-42), 42)
    }

    func testNegReturnsNilForMinimumValue() {
        XCTAssertNil(CedarInt64.neg(Int64.min))
    }
}