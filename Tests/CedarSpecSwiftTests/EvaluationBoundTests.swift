import XCTest
@testable import CedarSpecSwift

final class EvaluationBoundTests: XCTestCase {
    private let request = Request(
        principal: EntityUID(ty: Name(id: "Group"), eid: "chain-0"),
        action: EntityUID(ty: Name(id: "Action"), eid: "view"),
        resource: EntityUID(ty: Name(id: "Photo"), eid: "vacation")
    )

    func testPublicEvaluateUsesFrozenDefaultBoundForDeepProgrammaticExpression() {
        let deepestPassingExpression = nestedIf(depth: (defaultEvaluationStepLimit - 1) / 2)
        let firstFailingExpression = nestedIf(depth: (defaultEvaluationStepLimit / 2) + 2)

        XCTAssertEqual(
            unwrapResult(evaluate(deepestPassingExpression, request: request, entities: Entities())),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            failure(of: evaluate(firstFailingExpression, request: request, entities: Entities())),
            .evaluationLimitError
        )
    }

    func testLoadedHierarchyTraversalUsesFrozenDefaultBound() {
        let passingDepth = defaultEvaluationStepLimit - 3
        let failingDepth = defaultEvaluationStepLimit - 2
        let successEntities = unwrapLoad(loadEntities(LoaderFixtures.longChainEntitiesJSON(length: passingDepth)))
        let failureEntities = unwrapLoad(loadEntities(LoaderFixtures.longChainEntitiesJSON(length: failingDepth)))
        let targetPass = EntityUID(ty: Name(id: "Group"), eid: "chain-\(passingDepth)")
        let targetFail = EntityUID(ty: Name(id: "Group"), eid: "chain-\(failingDepth)")

        XCTAssertEqual(
            unwrapResult(evaluate(.binaryApp(.in, .variable(.principal), .lit(.prim(.entityUID(targetPass)))), request: request, entities: successEntities)),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            failure(of: evaluate(.binaryApp(.in, .variable(.principal), .lit(.prim(.entityUID(targetFail)))), request: request, entities: failureEntities)),
            .evaluationLimitError
        )
    }

    private func nestedIf(depth: Int) -> Expr {
        guard depth > 0 else {
            return .lit(.prim(.bool(true)))
        }

        return .ifThenElse(.lit(.prim(.bool(true))), nestedIf(depth: depth - 1), .lit(.prim(.bool(false))))
    }

    private func failure<T>(of result: CedarResult<T>) -> CedarError {
        switch result {
        case .success:
            XCTFail("Expected failure")
            return .typeError
        case let .failure(error):
            return error
        }
    }
}