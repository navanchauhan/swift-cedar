internal struct DurationParsed: Equatable, Sendable {
    let milliseconds: Int64
}

internal enum DurationSemanticValue: Equatable, Sendable {
    case valid(DurationParsed)
    case invalid(String)
}

private let durationMillisecondsPerSecond: Int64 = 1_000
private let durationMillisecondsPerMinute: Int64 = 60_000
private let durationMillisecondsPerHour: Int64 = 3_600_000
private let durationMillisecondsPerDay: Int64 = 86_400_000

internal func durationFromMilliseconds(_ value: Int64) -> DurationParsed? {
    DurationParsed(milliseconds: value)
}

internal func durationNeg(_ duration: DurationParsed) -> DurationParsed? {
    guard let value = CedarInt64.neg(duration.milliseconds) else {
        return nil
    }

    return .init(milliseconds: value)
}

internal func durationUnits(_ value: Int64, suffix: String) -> Int64? {
    switch suffix {
    case "ms":
        return value
    case "s":
        return CedarInt64.mul(value, durationMillisecondsPerSecond)
    case "m":
        return CedarInt64.mul(value, durationMillisecondsPerMinute)
    case "h":
        return CedarInt64.mul(value, durationMillisecondsPerHour)
    case "d":
        return CedarInt64.mul(value, durationMillisecondsPerDay)
    default:
        return nil
    }
}

internal func durationParse(_ rawValue: String) -> DurationParsed? {
    guard !rawValue.isEmpty else {
        return nil
    }

    let isNegative = rawValue.first == "-"
    let remainder = isNegative ? String(rawValue.dropFirst()) : rawValue

    return parseDurationComponents(isNegative: isNegative, rawValue: remainder)
}

internal func durationCanonicalString(_ value: DurationParsed) -> String {
    if value.milliseconds == 0 {
        return "0ms"
    }

    let sign = value.milliseconds < 0 ? "-" : ""
    var remaining = value.milliseconds.magnitude
    let day = UInt64(durationMillisecondsPerDay)
    let hour = UInt64(durationMillisecondsPerHour)
    let minute = UInt64(durationMillisecondsPerMinute)
    let second = UInt64(durationMillisecondsPerSecond)
    var pieces: [String] = []

    let days = remaining / day
    if days > 0 {
        pieces.append("\(days)d")
        remaining %= day
    }

    let hours = remaining / hour
    if hours > 0 {
        pieces.append("\(hours)h")
        remaining %= hour
    }

    let minutes = remaining / minute
    if minutes > 0 {
        pieces.append("\(minutes)m")
        remaining %= minute
    }

    let seconds = remaining / second
    if seconds > 0 {
        pieces.append("\(seconds)s")
        remaining %= second
    }

    if remaining > 0 {
        pieces.append("\(remaining)ms")
    }

    return sign + pieces.joined()
}

internal func durationSemanticValue(_ payload: Ext.Duration) -> DurationSemanticValue {
    guard let parsed = durationParse(payload.rawValue) else {
        return .invalid(payload.rawValue)
    }

    return .valid(parsed)
}

internal func durationPayloadIsSupported(_ payload: Ext.Duration) -> Bool {
    durationParse(payload.rawValue) != nil
}

internal func durationSemanticEqual(_ lhs: Ext.Duration, _ rhs: Ext.Duration) -> Bool {
    switch (durationSemanticValue(lhs), durationSemanticValue(rhs)) {
    case let (.valid(left), .valid(right)):
        return left == right
    case let (.invalid(left), .invalid(right)):
        return cedarStringEqual(left, right)
    default:
        return false
    }
}

internal func durationSemanticLess(_ lhs: Ext.Duration, _ rhs: Ext.Duration) -> Bool {
    switch (durationSemanticValue(lhs), durationSemanticValue(rhs)) {
    case let (.valid(left), .valid(right)):
        return left.milliseconds < right.milliseconds
    case (.valid, .invalid):
        return true
    case (.invalid, .valid):
        return false
    case let (.invalid(left), .invalid(right)):
        return cedarStringLess(left, right)
    }
}

internal func durationSemanticHash(_ payload: Ext.Duration, into hasher: inout Hasher) {
    switch durationSemanticValue(payload) {
    case let .valid(value):
        hasher.combine(0)
        hasher.combine(value.milliseconds)
    case let .invalid(rawValue):
        hasher.combine(1)
        cedarHashString(rawValue, into: &hasher)
    }
}

internal func durationConstructorResult(_ rawValue: String) -> CedarResult<CedarValue> {
    extResult(durationParse(rawValue).map { _ in .duration(.init(rawValue: rawValue)) })
}

internal func durationComparisonResult(
    _ lhs: Ext.Duration,
    _ rhs: Ext.Duration,
    predicate: (Int64, Int64) -> Bool
) -> CedarResult<CedarValue> {
    guard let left = durationParse(lhs.rawValue), let right = durationParse(rhs.rawValue) else {
        return .failure(.extensionError)
    }

    return .success(.prim(.bool(predicate(left.milliseconds, right.milliseconds))))
}

internal func durationToMillisecondsResult(_ payload: Ext.Duration) -> CedarResult<CedarValue> {
    guard let parsed = durationParse(payload.rawValue) else {
        return .failure(.extensionError)
    }

    return .success(.prim(.int(parsed.milliseconds)))
}

internal func durationToSecondsResult(_ payload: Ext.Duration) -> CedarResult<CedarValue> {
    guard let parsed = durationParse(payload.rawValue) else {
        return .failure(.extensionError)
    }

    return .success(.prim(.int(parsed.milliseconds / durationMillisecondsPerSecond)))
}

internal func durationToMinutesResult(_ payload: Ext.Duration) -> CedarResult<CedarValue> {
    guard let parsed = durationParse(payload.rawValue) else {
        return .failure(.extensionError)
    }

    return .success(.prim(.int(parsed.milliseconds / durationMillisecondsPerMinute)))
}

internal func durationToHoursResult(_ payload: Ext.Duration) -> CedarResult<CedarValue> {
    guard let parsed = durationParse(payload.rawValue) else {
        return .failure(.extensionError)
    }

    return .success(.prim(.int(parsed.milliseconds / durationMillisecondsPerHour)))
}

internal func durationToDaysResult(_ payload: Ext.Duration) -> CedarResult<CedarValue> {
    guard let parsed = durationParse(payload.rawValue) else {
        return .failure(.extensionError)
    }

    return .success(.prim(.int(parsed.milliseconds / durationMillisecondsPerDay)))
}

private func parseDurationComponents(isNegative: Bool, rawValue: String) -> DurationParsed? {
    guard !rawValue.isEmpty else {
        return nil
    }

    guard let (milliseconds, millisecondsRemainder) = parseDurationUnit(isNegative: isNegative, rawValue: rawValue, suffix: "ms"),
          let (seconds, secondsRemainder) = parseDurationUnit(isNegative: isNegative, rawValue: millisecondsRemainder, suffix: "s"),
          let (minutes, minutesRemainder) = parseDurationUnit(isNegative: isNegative, rawValue: secondsRemainder, suffix: "m"),
          let (hours, hoursRemainder) = parseDurationUnit(isNegative: isNegative, rawValue: minutesRemainder, suffix: "h"),
          let (days, remainder) = parseDurationUnit(isNegative: isNegative, rawValue: hoursRemainder, suffix: "d"),
          remainder.isEmpty,
          let dayHour = CedarInt64.add(days, hours),
          let minuteSecond = CedarInt64.add(minutes, seconds),
          let firstSum = CedarInt64.add(dayHour, minuteSecond),
          let total = CedarInt64.add(firstSum, milliseconds)
    else {
        return nil
    }

    return durationFromMilliseconds(total)
}

private func parseDurationUnit(isNegative: Bool, rawValue: String, suffix: String) -> (Int64, String)? {
    guard rawValue.hasSuffix(suffix) else {
        return (0, rawValue)
    }

    let withoutSuffix = String(rawValue.dropLast(suffix.count))
    var digitsReversed: [Character] = []

    for character in withoutSuffix.reversed() {
        guard character.isWholeNumber else {
            break
        }

        digitsReversed.append(character)
    }

    guard !digitsReversed.isEmpty else {
        return nil
    }

    let digits = String(digitsReversed.reversed())
    let remainder = String(withoutSuffix.dropLast(digits.count))

    guard let unsigned = parseDurationInt64(digits) else {
        return nil
    }

    let signed: Int64
    if isNegative {
        guard let negated = CedarInt64.neg(unsigned) else {
            return nil
        }
        signed = negated
    } else {
        signed = unsigned
    }

    guard let units = durationUnits(signed, suffix: suffix) else {
        return nil
    }

    return (units, remainder)
}

private func parseDurationInt64(_ rawValue: String) -> Int64? {
    guard !rawValue.isEmpty else {
        return nil
    }

    var value: Int64 = 0

    for scalar in rawValue.unicodeScalars {
        guard scalar.value >= 48, scalar.value <= 57 else {
            return nil
        }

        guard let multiplied = CedarInt64.mul(value, 10),
              let added = CedarInt64.add(multiplied, Int64(scalar.value - 48))
        else {
            return nil
        }

        value = added
    }

    return value
}