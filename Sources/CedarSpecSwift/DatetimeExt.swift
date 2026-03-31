internal struct DatetimeParsed: Equatable, Sendable {
    let millisecondsSinceUnixEpoch: Int64
}

internal enum DatetimeSemanticValue: Equatable, Sendable {
    case valid(DatetimeParsed)
    case invalid(String)
}

private let datetimeMillisecondsPerSecond: Int64 = 1_000
private let datetimeMillisecondsPerMinute: Int64 = 60_000
private let datetimeMillisecondsPerHour: Int64 = 3_600_000
private let datetimeMillisecondsPerDay: Int64 = 86_400_000

internal func datetimeFromMilliseconds(_ value: Int64) -> DatetimeParsed? {
    DatetimeParsed(millisecondsSinceUnixEpoch: value)
}

internal func datetimeDateContainsLeapSeconds(_ rawValue: String) -> Bool {
    let bytes = Array(rawValue.utf8)
    return bytes.count >= 20 && bytes[17] == 54 && bytes[18] == 48
}

internal func datetimeTZOffsetMinsLt60(_ rawValue: String) -> Bool {
    let bytes = Array(rawValue.utf8)

    if bytes.count <= 10 || bytes.last == 90 {
        return true
    }

    guard bytes.count >= 2,
          let tens = asciiDigitValue(bytes[bytes.count - 2]),
          let ones = asciiDigitValue(bytes[bytes.count - 1])
    else {
        return false
    }

    return tens * 10 + ones < 60
}

internal func datetimeCheckComponentLen(_ rawValue: String) -> Bool {
    let bytes = Array(rawValue.utf8)

    if bytes.count == 10 {
        return hasDatePrefix(bytes)
    }

    guard bytes.count >= 20, hasDatePrefix(bytes), bytes[10] == 84 else {
        return false
    }

    guard hasTimePrefix(bytes, start: 11) else {
        return false
    }

    switch bytes[19] {
    case 90:
        return bytes.count == 20
    case 43, 45:
        return bytes.count == 24 && hasOffset(bytes, start: 19)
    case 46:
        guard bytes.count == 24 || bytes.count == 28 else {
            return false
        }

        guard hasDigits(bytes, start: 20, length: 3) else {
            return false
        }

        if bytes.count == 24 {
            return bytes[23] == 90
        }

        return hasOffset(bytes, start: 23)
    default:
        return false
    }
}

internal func datetimeParse(_ rawValue: String) -> DatetimeParsed? {
    if datetimeDateContainsLeapSeconds(rawValue) || !datetimeCheckComponentLen(rawValue) || !datetimeTZOffsetMinsLt60(rawValue) {
        return nil
    }

    let bytes = Array(rawValue.utf8)

    guard let year = parseASCIIInt(bytes, start: 0, length: 4),
          let month = parseASCIIInt(bytes, start: 5, length: 2),
          let day = parseASCIIInt(bytes, start: 8, length: 2),
          isValidDate(year: year, month: month, day: day)
    else {
        return nil
    }

    if bytes.count == 10 {
        return datetimeComponentsToParsed(
            year: year,
            month: month,
            day: day,
            hour: 0,
            minute: 0,
            second: 0,
            millisecond: 0,
            offsetMinutes: 0
        )
    }

    guard let hour = parseASCIIInt(bytes, start: 11, length: 2),
          let minute = parseASCIIInt(bytes, start: 14, length: 2),
          let second = parseASCIIInt(bytes, start: 17, length: 2),
          hour < 24,
          minute < 60,
          second < 60
    else {
        return nil
    }

    let millisecond: Int
    let offsetMinutes: Int

    switch bytes[19] {
    case 90:
        millisecond = 0
        offsetMinutes = 0
    case 43, 45:
        millisecond = 0
        guard let parsedOffset = parseDatetimeOffset(bytes, start: 19) else {
            return nil
        }
        offsetMinutes = parsedOffset
    case 46:
        guard let parsedMillisecond = parseASCIIInt(bytes, start: 20, length: 3) else {
            return nil
        }

        millisecond = parsedMillisecond

        if bytes[23] == 90 {
            offsetMinutes = 0
        } else {
            guard let parsedOffset = parseDatetimeOffset(bytes, start: 23) else {
                return nil
            }
            offsetMinutes = parsedOffset
        }
    default:
        return nil
    }

    return datetimeComponentsToParsed(
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute,
        second: second,
        millisecond: millisecond,
        offsetMinutes: offsetMinutes
    )
}

internal func datetimeCanonicalString(_ value: DatetimeParsed) -> String {
    let days = floorDiv(value.millisecondsSinceUnixEpoch, datetimeMillisecondsPerDay)
    let dayMilliseconds = floorMod(value.millisecondsSinceUnixEpoch, datetimeMillisecondsPerDay)
    let (year, month, day) = civilFromDays(days)
    let hour = Int(dayMilliseconds / datetimeMillisecondsPerHour)
    let minute = Int((dayMilliseconds % datetimeMillisecondsPerHour) / datetimeMillisecondsPerMinute)
    let second = Int((dayMilliseconds % datetimeMillisecondsPerMinute) / datetimeMillisecondsPerSecond)
    let millisecond = Int(dayMilliseconds % datetimeMillisecondsPerSecond)

    return [
        zeroPad(year, width: 4),
        "-",
        zeroPad(month, width: 2),
        "-",
        zeroPad(day, width: 2),
        "T",
        zeroPad(hour, width: 2),
        ":",
        zeroPad(minute, width: 2),
        ":",
        zeroPad(second, width: 2),
        ".",
        zeroPad(millisecond, width: 3),
        "Z",
    ].joined()
}

internal func datetimeSemanticValue(_ payload: Ext.Datetime) -> DatetimeSemanticValue {
    guard let parsed = datetimeParse(payload.rawValue) else {
        return .invalid(payload.rawValue)
    }

    return .valid(parsed)
}

internal func datetimePayloadIsSupported(_ payload: Ext.Datetime) -> Bool {
    datetimeParse(payload.rawValue) != nil
}

internal func datetimeSemanticEqual(_ lhs: Ext.Datetime, _ rhs: Ext.Datetime) -> Bool {
    switch (datetimeSemanticValue(lhs), datetimeSemanticValue(rhs)) {
    case let (.valid(left), .valid(right)):
        return left == right
    case let (.invalid(left), .invalid(right)):
        return cedarStringEqual(left, right)
    default:
        return false
    }
}

internal func datetimeSemanticLess(_ lhs: Ext.Datetime, _ rhs: Ext.Datetime) -> Bool {
    switch (datetimeSemanticValue(lhs), datetimeSemanticValue(rhs)) {
    case let (.valid(left), .valid(right)):
        return left.millisecondsSinceUnixEpoch < right.millisecondsSinceUnixEpoch
    case (.valid, .invalid):
        return true
    case (.invalid, .valid):
        return false
    case let (.invalid(left), .invalid(right)):
        return cedarStringLess(left, right)
    }
}

internal func datetimeSemanticHash(_ payload: Ext.Datetime, into hasher: inout Hasher) {
    switch datetimeSemanticValue(payload) {
    case let .valid(value):
        hasher.combine(0)
        hasher.combine(value.millisecondsSinceUnixEpoch)
    case let .invalid(rawValue):
        hasher.combine(1)
        cedarHashString(rawValue, into: &hasher)
    }
}

internal func datetimeConstructorResult(_ rawValue: String) -> CedarResult<CedarValue> {
    extResult(datetimeParse(rawValue).map { _ in .datetime(.init(rawValue: rawValue)) })
}

internal func datetimeComparisonResult(
    _ lhs: Ext.Datetime,
    _ rhs: Ext.Datetime,
    predicate: (Int64, Int64) -> Bool
) -> CedarResult<CedarValue> {
    guard let left = datetimeParse(lhs.rawValue), let right = datetimeParse(rhs.rawValue) else {
        return .failure(.extensionError)
    }

    return .success(.prim(.bool(predicate(left.millisecondsSinceUnixEpoch, right.millisecondsSinceUnixEpoch))))
}

internal func datetimeOffsetResult(_ datetimePayload: Ext.Datetime, _ durationPayload: Ext.Duration) -> CedarResult<CedarValue> {
    guard let datetime = datetimeParse(datetimePayload.rawValue),
          let duration = durationParse(durationPayload.rawValue),
          let offsetValue = CedarInt64.add(datetime.millisecondsSinceUnixEpoch, duration.milliseconds)
    else {
        return .failure(.extensionError)
    }

    return .success(.ext(.datetime(.init(rawValue: datetimeCanonicalString(.init(millisecondsSinceUnixEpoch: offsetValue))))))
}

internal func datetimeDurationSinceResult(_ lhs: Ext.Datetime, _ rhs: Ext.Datetime) -> CedarResult<CedarValue> {
    guard let left = datetimeParse(lhs.rawValue),
          let right = datetimeParse(rhs.rawValue),
          let delta = CedarInt64.sub(left.millisecondsSinceUnixEpoch, right.millisecondsSinceUnixEpoch)
    else {
        return .failure(.extensionError)
    }

    return .success(.ext(.duration(.init(rawValue: durationCanonicalString(.init(milliseconds: delta))))))
}

internal func datetimeToDateResult(_ payload: Ext.Datetime) -> CedarResult<CedarValue> {
    guard let parsed = datetimeParse(payload.rawValue) else {
        return .failure(.extensionError)
    }

    let dayStart: Int64
    if parsed.millisecondsSinceUnixEpoch >= 0 {
        let quotient = parsed.millisecondsSinceUnixEpoch / datetimeMillisecondsPerDay
        guard let value = CedarInt64.mul(quotient, datetimeMillisecondsPerDay) else {
            return .failure(.extensionError)
        }
        dayStart = value
    } else {
        let remainder = parsed.millisecondsSinceUnixEpoch % datetimeMillisecondsPerDay
        if remainder == 0 {
            dayStart = parsed.millisecondsSinceUnixEpoch
        } else {
            let quotient = parsed.millisecondsSinceUnixEpoch / datetimeMillisecondsPerDay
            guard let adjusted = CedarInt64.sub(quotient, 1),
                  let value = CedarInt64.mul(adjusted, datetimeMillisecondsPerDay)
            else {
                return .failure(.extensionError)
            }
            dayStart = value
        }
    }

    return .success(.ext(.datetime(.init(rawValue: datetimeCanonicalString(.init(millisecondsSinceUnixEpoch: dayStart))))))
}

internal func datetimeToTimeResult(_ payload: Ext.Datetime) -> CedarResult<CedarValue> {
    guard let parsed = datetimeParse(payload.rawValue) else {
        return .failure(.extensionError)
    }

    let milliseconds: Int64
    if parsed.millisecondsSinceUnixEpoch >= 0 {
        milliseconds = parsed.millisecondsSinceUnixEpoch % datetimeMillisecondsPerDay
    } else {
        let remainder = parsed.millisecondsSinceUnixEpoch % datetimeMillisecondsPerDay
        if remainder == 0 {
            milliseconds = 0
        } else {
            guard let value = CedarInt64.add(remainder, datetimeMillisecondsPerDay) else {
                return .failure(.extensionError)
            }
            milliseconds = value
        }
    }

    return .success(.ext(.duration(.init(rawValue: durationCanonicalString(.init(milliseconds: milliseconds))))))
}

private func datetimeComponentsToParsed(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    minute: Int,
    second: Int,
    millisecond: Int,
    offsetMinutes: Int
) -> DatetimeParsed? {
    guard let days = daysFromCivil(year: year, month: month, day: day),
          let dateMilliseconds = CedarInt64.mul(days, datetimeMillisecondsPerDay)
    else {
        return nil
    }

    let timeMilliseconds = Int64(hour) * datetimeMillisecondsPerHour
        + Int64(minute) * datetimeMillisecondsPerMinute
        + Int64(second) * datetimeMillisecondsPerSecond
        + Int64(millisecond)
    let offsetMilliseconds = Int64(offsetMinutes) * datetimeMillisecondsPerMinute

    guard let localMilliseconds = CedarInt64.add(dateMilliseconds, timeMilliseconds),
          let utcMilliseconds = CedarInt64.sub(localMilliseconds, offsetMilliseconds)
    else {
        return nil
    }

    return datetimeFromMilliseconds(utcMilliseconds)
}

private func hasDatePrefix(_ bytes: [UInt8]) -> Bool {
    bytes.count >= 10
        && hasDigits(bytes, start: 0, length: 4)
        && bytes[4] == 45
        && hasDigits(bytes, start: 5, length: 2)
        && bytes[7] == 45
        && hasDigits(bytes, start: 8, length: 2)
}

private func hasTimePrefix(_ bytes: [UInt8], start: Int) -> Bool {
    bytes.count >= start + 8
        && hasDigits(bytes, start: start, length: 2)
        && bytes[start + 2] == 58
        && hasDigits(bytes, start: start + 3, length: 2)
        && bytes[start + 5] == 58
        && hasDigits(bytes, start: start + 6, length: 2)
}

private func hasOffset(_ bytes: [UInt8], start: Int) -> Bool {
    bytes.count == start + 5
        && (bytes[start] == 43 || bytes[start] == 45)
        && hasDigits(bytes, start: start + 1, length: 4)
}

private func hasDigits(_ bytes: [UInt8], start: Int, length: Int) -> Bool {
    guard start >= 0, length >= 0, start + length <= bytes.count else {
        return false
    }

    for index in start ..< start + length {
        guard asciiDigitValue(bytes[index]) != nil else {
            return false
        }
    }

    return true
}

private func parseASCIIInt(_ bytes: [UInt8], start: Int, length: Int) -> Int? {
    guard hasDigits(bytes, start: start, length: length) else {
        return nil
    }

    var value = 0

    for index in start ..< start + length {
        guard let digit = asciiDigitValue(bytes[index]) else {
            return nil
        }

        value = value * 10 + digit
    }

    return value
}

private func parseDatetimeOffset(_ bytes: [UInt8], start: Int) -> Int? {
    guard hasOffset(bytes, start: start),
          let hours = parseASCIIInt(bytes, start: start + 1, length: 2),
          let minutes = parseASCIIInt(bytes, start: start + 3, length: 2),
          hours < 24,
          minutes < 60
    else {
        return nil
    }

    let sign = bytes[start] == 45 ? -1 : 1
    return sign * (hours * 60 + minutes)
}

private func asciiDigitValue(_ byte: UInt8) -> Int? {
    guard byte >= 48, byte <= 57 else {
        return nil
    }

    return Int(byte - 48)
}

private func isValidDate(year: Int, month: Int, day: Int) -> Bool {
    guard month >= 1, month <= 12 else {
        return false
    }

    let maxDay: Int
    switch month {
    case 1, 3, 5, 7, 8, 10, 12:
        maxDay = 31
    case 4, 6, 9, 11:
        maxDay = 30
    case 2:
        maxDay = isLeapYear(year) ? 29 : 28
    default:
        return false
    }

    return day >= 1 && day <= maxDay
}

private func isLeapYear(_ year: Int) -> Bool {
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

private func daysFromCivil(year: Int, month: Int, day: Int) -> Int64? {
    var adjustedYear = Int64(year)
    let adjustedMonth = Int64(month)
    let adjustedDay = Int64(day)
    adjustedYear -= adjustedMonth <= 2 ? 1 : 0
    let era = adjustedYear >= 0 ? adjustedYear / 400 : (adjustedYear - 399) / 400
    let yearOfEra = adjustedYear - era * 400
    let monthPrime = adjustedMonth + (adjustedMonth > 2 ? -3 : 9)
    let dayOfYear = (153 * monthPrime + 2) / 5 + adjustedDay - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146_097 + dayOfEra - 719_468
}

private func civilFromDays(_ value: Int64) -> (Int, Int, Int) {
    let shifted = value + 719_468
    let era = shifted >= 0 ? shifted / 146_097 : (shifted - 146_096) / 146_097
    let dayOfEra = shifted - era * 146_097
    let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
    var year = Int(yearOfEra + era * 400)
    let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    let monthPrime = (5 * dayOfYear + 2) / 153
    let day = Int(dayOfYear - (153 * monthPrime + 2) / 5 + 1)
    let month = Int(monthPrime < 10 ? monthPrime + 3 : monthPrime - 9)
    year += month <= 2 ? 1 : 0
    return (year, month, day)
}

private func floorDiv(_ lhs: Int64, _ rhs: Int64) -> Int64 {
    let quotient = lhs / rhs
    let remainder = lhs % rhs
    if remainder >= 0 {
        return quotient
    }

    return quotient - 1
}

private func floorMod(_ lhs: Int64, _ rhs: Int64) -> Int64 {
    let remainder = lhs % rhs
    return remainder >= 0 ? remainder : remainder + rhs
}

private func zeroPad(_ value: Int, width: Int) -> String {
    let sign = value < 0 ? "-" : ""
    let digits = String(abs(value))
    return sign + String(repeating: "0", count: max(0, width - digits.count)) + digits
}