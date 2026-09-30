import Foundation

enum CompressionMode: String, CaseIterable, Identifiable {
    case manual
    case targetSize
    var id: Self { self }
}

enum CompressionTarget {
    /// No grouping, exponent notation or partial parses. Six decimal places are
    /// enough to specify whole bytes, including locales with a decimal comma.
    static func bytes(from text: String, locale: Locale = .current) -> Int64? {
        let separator = locale.decimalSeparator ?? "."
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let escapedSeparator = NSRegularExpression.escapedPattern(for: separator)
        guard input.range(of: "^[0-9]+(?:\(escapedSeparator)[0-9]{1,6})?$", options: .regularExpression) != nil,
              let megabytes = Decimal(string: input.replacingOccurrences(of: separator, with: "."),
                                      locale: Locale(identifier: "en_US_POSIX")),
              megabytes >= Decimal(1) / 10, megabytes <= 1_000 else { return nil }
        return NSDecimalNumber(decimal: megabytes * 1_000_000).int64Value
    }
}
