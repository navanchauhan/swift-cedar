import XCTest
@testable import CedarSpecSwift

final class ExtFunTests: XCTestCase {
    func testAllCasesMatchLeanDeclarationOrder() {
        XCTAssertEqual(ExtFun.allCases, [
            .decimal,
            .lessThan,
            .lessThanOrEqual,
            .greaterThan,
            .greaterThanOrEqual,
            .ip,
            .isIpv4,
            .isIpv6,
            .isLoopback,
            .isMulticast,
            .isInRange,
            .datetime,
            .duration,
            .offset,
            .durationSince,
            .toDate,
            .toTime,
            .toMilliseconds,
            .toSeconds,
            .toMinutes,
            .toHours,
            .toDays,
        ])
    }

    func testComparableTracksCaseOrder() {
        XCTAssertLessThan(ExtFun.decimal, .ip)
        XCTAssertLessThan(ExtFun.isInRange, .datetime)
        XCTAssertLessThan(ExtFun.toHours, .toDays)
    }
}