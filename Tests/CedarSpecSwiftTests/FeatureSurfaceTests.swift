import XCTest
import CedarSpecSwift

final class FeatureSurfaceTests: XCTestCase {
    func testPublicBatchFormattingAndSlicingSurfaceCompiles() throws {
        let alice = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(principal: alice, action: action, resource: resource)
        let policy = Policy(
            id: "allow-alice",
            effect: .permit,
            principalScope: .eq(entity: alice),
            actionScope: .eq(entity: action),
            resourceScope: .eq(entity: resource)
        )
        let policies: Policies = .make([(key: policy.id, value: policy)])
        let template = BatchRequestTemplate(
            principal: .variable("principal"),
            action: .value(action),
            resource: .value(resource),
            context: .value(.emptyRecord)
        )
        let domains: BatchVariableDomains = .make([
            (key: "principal", value: [.entityUID(alice)]),
        ])

        let formatted = try unwrapLoad(formatCedar(emitCedar(policies), source: "policies.cedar")).get()
        let expressionRefs = sliceEUIDs(policy.toExpr(), request: request)
        let requestRefs = sliceEUIDs(request)
        let batch = try batchAuthorize(template: template, domains: domains, entities: Entities(), policies: policies).get()

        XCTAssertTrue(formatted.contains("permit ("))
        XCTAssertEqual(expressionRefs, CedarSet.make([alice, action, resource]))
        XCTAssertEqual(requestRefs, CedarSet.make([alice, action, resource]))
        XCTAssertEqual(batch.count, 1)
    }

    private func unwrapLoad<T>(_ result: LoadResult<T>) -> Result<T, Error> {
        switch result {
        case let .success(value, diagnostics):
            if diagnostics.hasErrors {
                return .failure(diagnostics)
            }
            return .success(value)
        case let .failure(diagnostics):
            return .failure(diagnostics)
        }
    }
}