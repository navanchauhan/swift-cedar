import XCTest
@testable import CedarSpecSwift

final class BatchAuthorizationTests: XCTestCase {
    private let alice = EntityUID(ty: Name(id: "User"), eid: "alice")
    private let bob = EntityUID(ty: Name(id: "User"), eid: "bob")
    private let view = EntityUID(ty: Name(id: "Action"), eid: "view")
    private let photo = EntityUID(ty: Name(id: "Photo"), eid: "vacation")

    private var policies: Policies {
        let policy = Policy(
            id: "permit-alice",
            effect: .permit,
            principalScope: .eq(entity: alice),
            actionScope: .eq(entity: view),
            resourceScope: .eq(entity: photo)
        )
        return .make([(key: policy.id, value: policy)])
    }

    func testBatchAuthorizeEnumeratesDomainsDeterministically() {
        let template = BatchRequestTemplate(
            principal: .variable("principal"),
            action: .value(view),
            resource: .value(photo)
        )
        let domains: BatchVariableDomains = .make([
            (key: "principal", value: [.entityUID(alice), .entityUID(bob)]),
        ])

        let results = unwrapBatchResult(batchAuthorize(template: template, domains: domains, entities: Entities(), policies: policies))

        XCTAssertEqual(results.map { $0.request.principal }, [alice, bob])
        XCTAssertEqual(results.map { $0.response.decision }, [Decision.allow, Decision.deny])
    }

    func testBatchAuthorizeRejectsUnboundUnusedEmptyAndInvalidDomains() {
        let template = BatchRequestTemplate(
            principal: .variable("principal"),
            action: .value(view),
            resource: .value(photo),
            context: .variable("context")
        )

        XCTAssertEqual(
            batchAuthorize(template: template, domains: .empty, entities: Entities(), policies: policies),
            .failure(.unboundVariables(CedarSet.make(["context", "principal"])))
        )
        XCTAssertEqual(
            batchAuthorize(
                template: BatchRequestTemplate(principal: .variable("principal"), action: .value(view), resource: .value(photo)),
                domains: .make([
                    (key: "principal", value: [.entityUID(alice)]),
                    (key: "unused", value: [.entityUID(bob)]),
                ]),
                entities: Entities(),
                policies: policies
            ),
            .failure(.unusedVariables(CedarSet.make(["unused"])))
        )
        XCTAssertEqual(
            batchAuthorize(
                template: BatchRequestTemplate(principal: .variable("principal"), action: .value(view), resource: .value(photo)),
                domains: .make([(key: "principal", value: [])]),
                entities: Entities(),
                policies: policies
            ),
            .failure(.emptyDomain("principal"))
        )
        XCTAssertEqual(
            batchAuthorize(
                template: BatchRequestTemplate(principal: .variable("principal"), action: .value(view), resource: .value(photo)),
                domains: .make([(key: "principal", value: [.context(.emptyRecord)])]),
                entities: Entities(),
                policies: policies
            ),
            .failure(.invalidBinding(variable: "principal", expected: .entityUID, actual: .context))
        )
    }

    private func unwrapBatchResult<Success>(
        _ result: Result<Success, BatchAuthorizationError>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Success {
        switch result {
        case let .success(value):
            return value
        case let .failure(error):
            XCTFail("Expected success, got error: \(error)", file: file, line: line)
            fatalError("unreachable")
        }
    }
}
