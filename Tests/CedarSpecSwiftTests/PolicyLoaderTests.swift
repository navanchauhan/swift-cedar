import XCTest
@testable import CedarSpecSwift

final class PolicyLoaderTests: XCTestCase {
    func testLoadPoliciesParsesAnnotationsAndWildcardPatterns() {
        let policies = unwrapLoad(loadPolicies(LoaderFixtures.policiesJSON))
        let policy = policies.find("permit-view")

        XCTAssertEqual(policy?.annotations.find("owner"), "security")
        XCTAssertEqual(policy?.conditions.count, 2)
    }

    func testLoadPoliciesRejectsDuplicateIDs() {
        let diagnostics = unwrapFailure(loadPolicies(LoaderFixtures.duplicatePolicyIDsPoliciesJSON))
        XCTAssertEqual(diagnostics.elements.first?.code, "policy.duplicateID")
    }
}