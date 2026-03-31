public typealias Tag = String

public struct EntityData: Equatable, Sendable {
    public let ancestors: CedarSet<EntityUID>
    public let attrs: CedarMap<Attr, CedarValue>
    public let tags: CedarMap<Tag, CedarValue>

    public init(
        ancestors: CedarSet<EntityUID> = .empty,
        attrs: CedarMap<Attr, CedarValue> = .empty,
        tags: CedarMap<Tag, CedarValue> = .empty
    ) {
        self.ancestors = ancestors
        self.attrs = attrs
        self.tags = tags
    }
}

public struct Entities: Equatable, Sendable {
    public let entries: CedarMap<EntityUID, EntityData>

    public init(_ entries: CedarMap<EntityUID, EntityData> = .empty) {
        self.entries = entries
    }

    public func ancestors(_ uid: EntityUID) -> CedarResult<CedarSet<EntityUID>> {
        guard let entity = entries.find(uid) else {
            return .failure(.entityDoesNotExist)
        }

        return .success(entity.ancestors)
    }

    public func ancestorsOrEmpty(_ uid: EntityUID) -> CedarSet<EntityUID> {
        entries.find(uid)?.ancestors ?? .empty
    }

    public func attrs(_ uid: EntityUID) -> CedarResult<CedarMap<Attr, CedarValue>> {
        guard let entity = entries.find(uid) else {
            return .failure(.entityDoesNotExist)
        }

        return .success(entity.attrs)
    }

    public func attrsOrEmpty(_ uid: EntityUID) -> CedarMap<Attr, CedarValue> {
        entries.find(uid)?.attrs ?? .empty
    }

    public func tags(_ uid: EntityUID) -> CedarResult<CedarMap<Tag, CedarValue>> {
        guard let entity = entries.find(uid) else {
            return .failure(.entityDoesNotExist)
        }

        return .success(entity.tags)
    }

    public func tagsOrEmpty(_ uid: EntityUID) -> CedarMap<Tag, CedarValue> {
        entries.find(uid)?.tags ?? .empty
    }

    public func contains(_ uid: EntityUID) -> Bool {
        entries.contains(uid)
    }
}
