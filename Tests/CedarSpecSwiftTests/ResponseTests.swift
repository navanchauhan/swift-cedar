import XCTest
@testable import CedarSpecSwift

final class ResponseTests: XCTestCase {
    private let composedEAcute = "\u{00E9}"
    private let decomposedEAcute = "e\u{0301}"

    func testDecisionComparableUsesLeanConstructorOrder() {
        XCTAssertEqual(Decision.allCases, [.allow, .deny])
        XCTAssertEqual([Decision.deny, .allow].sorted(), Decision.allCases)
    }

    func testResponseInitializerDefaultsToEmptyPolicySets() {
        let response = Response(decision: .deny)

        XCTAssertEqual(response.decision, .deny)
        XCTAssertEqual(response.determining, .empty)
        XCTAssertEqual(response.erroring, .empty)
    }

    func testResponseEqualityAndHashableCollectionInteroperability() {
        let lhs = Response(
            decision: .allow,
            determining: CedarSet.make(["policy-b", "policy-a", "policy-a"]),
            erroring: CedarSet.make(["policy-error"])
        )
        let rhs = Response(
            decision: .allow,
            determining: CedarSet.make(["policy-a", "policy-b"]),
            erroring: CedarSet.make(["policy-error"])
        )
        let table = [lhs: "matched"]

        XCTAssertEqual(lhs, rhs)
        XCTAssertEqual(hash(of: lhs), hash(of: rhs))
        XCTAssertEqual(table[rhs], "matched")
    }

    func testScalarDistinctPolicyIDsRemainDistinctInResponseSets() {
        let response = Response(
            decision: .allow,
            determining: CedarSet.make([composedEAcute, decomposedEAcute, composedEAcute])
        )

        XCTAssertEqual(response.determining.elements, [decomposedEAcute, composedEAcute])
        XCTAssertTrue(response.determining.contains(decomposedEAcute))
        XCTAssertTrue(response.determining.contains(composedEAcute))
    }

    func testResponseRetainsDeterministicCedarSetOrdering() {
        let response = Response(
            decision: .allow,
            determining: CedarSet.make(["zeta", "alpha", "beta", "alpha"]),
            erroring: CedarSet.make(["err-b", "err-a"])
        )

        XCTAssertEqual(response.determining.elements, ["alpha", "beta", "zeta"])
        XCTAssertEqual(response.erroring.elements, ["err-a", "err-b"])
    }

    func testDirectConstructionPreservesOverlapBetweenDeterminingAndErroring() {
        let shared = "policy-overlap"
        let response = Response(
            decision: .deny,
            determining: CedarSet.make([shared, "policy-allow"]),
            erroring: CedarSet.make(["policy-error", shared])
        )

        XCTAssertEqual(response.determining.elements, ["policy-allow", shared])
        XCTAssertEqual(response.erroring.elements, ["policy-error", shared])
        XCTAssertTrue(response.determining.contains(shared))
        XCTAssertTrue(response.erroring.contains(shared))
    }

    private func hash(of value: some Hashable) -> Int {
        var hasher = Hasher()
        hasher.combine(value)
        return hasher.finalize()
    }
}