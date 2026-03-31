internal enum ExtensionComparisonOperation: Sendable {
    case equal
    case lessThan
    case lessThanOrEqual
}

internal func containsUnsupportedExtensionValue(_ value: CedarValue) -> Bool {
    switch value {
    case let .ext(ext):
        return !supportsDirectExtensionExecution(ext)
    case let .set(values):
        return values.elements.contains(where: containsUnsupportedExtensionValue)
    case let .record(record):
        return record.values.contains(where: containsUnsupportedExtensionValue)
    case .prim:
        return false
    }
}

internal func extensionValuesEqual(_ lhs: Ext, _ rhs: Ext) -> Bool {
    switch (lhs, rhs) {
    case let (.decimal(left), .decimal(right)):
        return decimalSemanticEqual(left, right)
    case let (.ipaddr(left), .ipaddr(right)):
        return ipaddrSemanticEqual(left, right)
    case let (.datetime(left), .datetime(right)):
        return datetimeSemanticEqual(left, right)
    case let (.duration(left), .duration(right)):
        return durationSemanticEqual(left, right)
    default:
        return false
    }
}

internal func extensionValuesLess(_ lhs: Ext, _ rhs: Ext) -> Bool {
    switch (lhs, rhs) {
    case let (.decimal(left), .decimal(right)):
        return decimalSemanticLess(left, right)
    case let (.ipaddr(left), .ipaddr(right)):
        return ipaddrSemanticLess(left, right)
    case let (.datetime(left), .datetime(right)):
        return datetimeSemanticLess(left, right)
    case let (.duration(left), .duration(right)):
        return durationSemanticLess(left, right)
    case (.decimal, _), (.ipaddr, .datetime), (.ipaddr, .duration), (.datetime, .duration):
        return true
    default:
        return false
    }
}

internal func supportsDirectExtensionExecution(_ ext: Ext) -> Bool {
    switch ext {
    case let .decimal(payload):
        return decimalPayloadIsSupported(payload)
    case let .ipaddr(payload):
        return ipaddrPayloadIsSupported(payload)
    case let .datetime(payload):
        return datetimePayloadIsSupported(payload)
    case let .duration(payload):
        return durationPayloadIsSupported(payload)
    }
}

internal func applySharedComparison(
    _ operation: ExtensionComparisonOperation,
    lhs: CedarValue,
    rhs: CedarValue
) -> CedarResult<CedarValue> {
    switch operation {
    case .equal:
        if containsUnsupportedExtensionValue(lhs) || containsUnsupportedExtensionValue(rhs) {
            return .failure(.extensionError)
        }

        return .success(.prim(.bool(lhs == rhs)))
    case .lessThan:
        switch (lhs, rhs) {
        case let (.prim(.int(left)), .prim(.int(right))):
            return .success(.prim(.bool(left < right)))
        case let (.ext(.datetime(left)), .ext(.datetime(right))):
            return datetimeComparisonResult(left, right, predicate: <)
        case let (.ext(.duration(left)), .ext(.duration(right))):
            return durationComparisonResult(left, right, predicate: <)
        default:
            return .failure(.typeError)
        }
    case .lessThanOrEqual:
        switch (lhs, rhs) {
        case let (.prim(.int(left)), .prim(.int(right))):
            return .success(.prim(.bool(left <= right)))
        case let (.ext(.datetime(left)), .ext(.datetime(right))):
            return datetimeComparisonResult(left, right, predicate: <=)
        case let (.ext(.duration(left)), .ext(.duration(right))):
            return durationComparisonResult(left, right, predicate: <=)
        default:
            return .failure(.typeError)
        }
    }
}

internal func dispatchExtensionCall(_ function: ExtFun, arguments: [CedarValue]) -> CedarResult<CedarValue> {
    switch function {
    case .decimal:
        guard arguments.count == 1 else {
            return .failure(.typeError)
        }

        guard case let .prim(.string(rawValue)) = arguments[0] else {
            return .failure(.typeError)
        }

        return extResult(decimalParse(rawValue).map { _ in .decimal(.init(rawValue: rawValue)) })
    case .ip:
        guard arguments.count == 1 else {
            return .failure(.typeError)
        }

        guard case let .prim(.string(rawValue)) = arguments[0] else {
            return .failure(.typeError)
        }

        return ipaddrConstructorResult(rawValue)
    case .datetime:
        guard arguments.count == 1 else {
            return .failure(.typeError)
        }

        guard case let .prim(.string(rawValue)) = arguments[0] else {
            return .failure(.typeError)
        }

        return datetimeConstructorResult(rawValue)
    case .duration:
        guard arguments.count == 1 else {
            return .failure(.typeError)
        }

        guard case let .prim(.string(rawValue)) = arguments[0] else {
            return .failure(.typeError)
        }

        return durationConstructorResult(rawValue)
    case .lessThan:
        return dispatchDecimalComparison(arguments: arguments, predicate: <)
    case .lessThanOrEqual:
        return dispatchDecimalComparison(arguments: arguments, predicate: <=)
    case .greaterThan:
        return dispatchDecimalComparison(arguments: arguments, predicate: >)
    case .greaterThanOrEqual:
        return dispatchDecimalComparison(arguments: arguments, predicate: >=)
    case .isIpv4:
        return dispatchIPAddrPredicate(arguments: arguments, predicate: { parsed in
            if case .v4 = parsed {
                return true
            }

            return false
        })
    case .isIpv6:
        return dispatchIPAddrPredicate(arguments: arguments, predicate: { parsed in
            if case .v6 = parsed {
                return true
            }

            return false
        })
    case .isLoopback:
        return dispatchIPAddrPredicate(arguments: arguments, predicate: isIPAddrLoopback)
    case .isMulticast:
        return dispatchIPAddrPredicate(arguments: arguments, predicate: isIPAddrMulticast)
    case .isInRange:
        return dispatchIPAddrInRange(arguments: arguments)
    case .offset:
        guard arguments.count == 2 else {
            return .failure(.typeError)
        }

        guard case let .ext(.datetime(datetimeValue)) = arguments[0],
              case let .ext(.duration(durationValue)) = arguments[1]
        else {
            return .failure(.typeError)
        }

        return datetimeOffsetResult(datetimeValue, durationValue)
    case .durationSince:
        guard arguments.count == 2 else {
            return .failure(.typeError)
        }

        guard case let .ext(.datetime(left)) = arguments[0],
              case let .ext(.datetime(right)) = arguments[1]
        else {
            return .failure(.typeError)
        }

        return datetimeDurationSinceResult(left, right)
    case .toDate:
        guard arguments.count == 1 else {
            return .failure(.typeError)
        }

        guard case let .ext(.datetime(value)) = arguments[0] else {
            return .failure(.typeError)
        }

        return datetimeToDateResult(value)
    case .toTime:
        guard arguments.count == 1 else {
            return .failure(.typeError)
        }

        guard case let .ext(.datetime(value)) = arguments[0] else {
            return .failure(.typeError)
        }

        return datetimeToTimeResult(value)
    case .toMilliseconds:
        guard arguments.count == 1 else {
            return .failure(.typeError)
        }

        guard case let .ext(.duration(value)) = arguments[0] else {
            return .failure(.typeError)
        }

        return durationToMillisecondsResult(value)
    case .toSeconds:
        guard arguments.count == 1 else {
            return .failure(.typeError)
        }

        guard case let .ext(.duration(value)) = arguments[0] else {
            return .failure(.typeError)
        }

        return durationToSecondsResult(value)
    case .toMinutes:
        guard arguments.count == 1 else {
            return .failure(.typeError)
        }

        guard case let .ext(.duration(value)) = arguments[0] else {
            return .failure(.typeError)
        }

        return durationToMinutesResult(value)
    case .toHours:
        guard arguments.count == 1 else {
            return .failure(.typeError)
        }

        guard case let .ext(.duration(value)) = arguments[0] else {
            return .failure(.typeError)
        }

        return durationToHoursResult(value)
    case .toDays:
        guard arguments.count == 1 else {
            return .failure(.typeError)
        }

        guard case let .ext(.duration(value)) = arguments[0] else {
            return .failure(.typeError)
        }

        return durationToDaysResult(value)
    }
}

private func dispatchDecimalComparison(
    arguments: [CedarValue],
    predicate: (Int64, Int64) -> Bool
) -> CedarResult<CedarValue> {
    guard arguments.count == 2 else {
        return .failure(.typeError)
    }

    guard case let .ext(.decimal(left)) = arguments[0], case let .ext(.decimal(right)) = arguments[1] else {
        return .failure(.typeError)
    }

    return decimalComparisonResult(left, right, predicate: predicate)
}

private func dispatchIPAddrPredicate(
    arguments: [CedarValue],
    predicate: (IPAddrParsed) -> Bool
) -> CedarResult<CedarValue> {
    guard arguments.count == 1 else {
        return .failure(.typeError)
    }

    guard case let .ext(.ipaddr(value)) = arguments[0] else {
        return .failure(.typeError)
    }

    return ipaddrPredicateResult(value, predicate: predicate)
}

private func dispatchIPAddrInRange(arguments: [CedarValue]) -> CedarResult<CedarValue> {
    guard arguments.count == 2 else {
        return .failure(.typeError)
    }

    guard case let .ext(.ipaddr(left)) = arguments[0], case let .ext(.ipaddr(right)) = arguments[1] else {
        return .failure(.typeError)
    }

    return ipaddrInRangeResult(left, right)
}

private func isIPAddrLoopback(_ value: IPAddrParsed) -> Bool {
    switch value {
    case .v4:
        return ipaddrInRange(value, .v4(address: 0x7F00_0000, prefix: 8))
    case .v6:
        return ipaddrInRange(value, .v6(segments: [0, 0, 0, 0, 0, 0, 0, 1], prefix: 128))
    }
}

private func isIPAddrMulticast(_ value: IPAddrParsed) -> Bool {
    switch value {
    case .v4:
        return ipaddrInRange(value, .v4(address: 0xE000_0000, prefix: 4))
    case .v6:
        return ipaddrInRange(value, .v6(segments: [0xFF00, 0, 0, 0, 0, 0, 0, 0], prefix: 8))
    }
}
