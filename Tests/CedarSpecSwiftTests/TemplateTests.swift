import XCTest
@testable import CedarSpecSwift

final class TemplateTests: XCTestCase {
    func testTemplateModelPreservesAnnotationsAndSlots() {
        let template = Template(
            id: "template",
            annotations: CedarMap.make([(key: "owner", value: "security")]),
            effect: .permit,
            principalScope: PrincipalScopeTemplate(.eq(.slot(.principal))),
            actionScope: .any,
            resourceScope: ResourceScopeTemplate(.eq(.slot(.resource))),
            conditions: []
        )

        XCTAssertEqual(template.annotations.find("owner"), "security")
        XCTAssertEqual(Slot.principal, Slot("principal"))
        XCTAssertLessThan(Slot.principal, Slot.resource)
    }
}