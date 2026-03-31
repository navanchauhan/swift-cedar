import XCTest
@testable import CedarSpecSwift

final class TemplateLinkingTests: XCTestCase {
    func testLinkPolicyBindsPrincipalAndResourceSlots() {
        let templates = unwrapLoad(loadTemplates(LoaderFixtures.templatesJSON))
        let template = templates.find("template-view")!
        let linked = unwrapLoad(linkPolicy(
            template: template,
            slotEnv: CedarMap.make([
                (key: .principal, value: EntityUID(ty: Name(id: "User"), eid: "alice")),
                (key: .resource, value: EntityUID(ty: Name(id: "Photo"), eid: "vacation")),
            ])
        ))

        XCTAssertEqual(linked.principalScope, .eq(entity: EntityUID(ty: Name(id: "User"), eid: "alice")))
        XCTAssertEqual(linked.resourceScope, .eq(entity: EntityUID(ty: Name(id: "Photo"), eid: "vacation")))
    }

    func testLoadTemplateLinksRejectsDuplicateIDs() {
        let diagnostics = unwrapFailure(loadTemplateLinks(LoaderFixtures.duplicatePolicyIDsTemplateLinksJSON))
        XCTAssertEqual(diagnostics.elements.first?.code, "template.duplicateLinkedID")
    }

    func testLinkFailsWhenSlotBindingIsMissing() {
        let templates = unwrapLoad(loadTemplates(LoaderFixtures.templatesJSON))
        let diagnostics = unwrapFailure(linkPolicy(
            template: templates.find("template-view")!,
            slotEnv: CedarMap.make([(key: .principal, value: EntityUID(ty: Name(id: "User"), eid: "alice"))])
        ))

        XCTAssertEqual(diagnostics.elements.first?.code, "template.missingSlotBinding")
    }
}