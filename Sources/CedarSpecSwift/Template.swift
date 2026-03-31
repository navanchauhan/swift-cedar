public typealias TemplateID = PolicyID
public typealias Templates = CedarMap<TemplateID, Template>
public typealias TemplateLinkedPolicies = [TemplateLinkedPolicy]

public struct Slot: Hashable, Sendable {
    public let id: String

    public init(_ id: String) {
        self.id = id
    }

    public static let principal = Self("principal")
    public static let resource = Self("resource")
}

extension Slot: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        cedarStringEqual(lhs.id, rhs.id)
    }
}

extension Slot: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        cedarStringLess(lhs.id, rhs.id)
    }
}

extension Slot: CustomStringConvertible {
    public var description: String {
        id
    }
}

public typealias SlotEnv = CedarMap<Slot, EntityUID>

public enum EntityUIDOrSlot: Equatable, Hashable, Sendable {
    case entityUID(EntityUID)
    case slot(Slot)
}

public enum ScopeTemplate: Equatable, Hashable, Sendable {
    case any
    case eq(EntityUIDOrSlot)
    case `in`(EntityUIDOrSlot)
    case isEntityType(EntityType)
    case isEntityTypeIn(EntityType, EntityUIDOrSlot)
}

public struct PrincipalScopeTemplate: Equatable, Hashable, Sendable {
    public let scope: ScopeTemplate

    public init(_ scope: ScopeTemplate) {
        self.scope = scope
    }
}

public struct ResourceScopeTemplate: Equatable, Hashable, Sendable {
    public let scope: ScopeTemplate

    public init(_ scope: ScopeTemplate) {
        self.scope = scope
    }
}

public struct Template: Equatable, Hashable, Sendable {
    public let id: TemplateID
    public let annotations: CedarMap<String, String>
    public let effect: Effect
    public let principalScope: PrincipalScopeTemplate
    public let actionScope: ActionScope
    public let resourceScope: ResourceScopeTemplate
    public let conditions: [Condition]

    public init(
        id: TemplateID,
        annotations: CedarMap<String, String> = .empty,
        effect: Effect,
        principalScope: PrincipalScopeTemplate,
        actionScope: ActionScope,
        resourceScope: ResourceScopeTemplate,
        conditions: [Condition] = []
    ) {
        self.id = id
        self.annotations = annotations
        self.effect = effect
        self.principalScope = principalScope
        self.actionScope = actionScope
        self.resourceScope = resourceScope
        self.conditions = conditions
    }
}

public struct TemplateLinkedPolicy: Equatable, Hashable, Sendable {
    public let id: PolicyID
    public let templateID: TemplateID
    public let slotEnv: SlotEnv
    public let annotations: CedarMap<String, String>

    public init(
        id: PolicyID,
        templateID: TemplateID,
        slotEnv: SlotEnv = .empty,
        annotations: CedarMap<String, String> = .empty
    ) {
        self.id = id
        self.templateID = templateID
        self.slotEnv = slotEnv
        self.annotations = annotations
    }
}