public struct Request: Equatable, Sendable {
    public let principal: EntityUID
    public let action: EntityUID
    public let resource: EntityUID
    public let context: RestrictedExpr

    public init(
        principal: EntityUID,
        action: EntityUID,
        resource: EntityUID,
        context: RestrictedExpr = .emptyRecord
    ) {
        self.principal = principal
        self.action = action
        self.resource = resource
        self.context = context
    }
}
