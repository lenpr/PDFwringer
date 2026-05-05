import Foundation

struct PageRangeParser {

    /// Parses a page range string like "1,3,4-10,5-" into an array of 0-based page indices.
    /// Preserves user order. Allows duplicates. Supports descending ranges and open-ended ranges.
    static func parse(_ input: String, pageCount: Int) throws -> [Int] {
        guard pageCount > 0 else { return [] }

        var result: [Int] = []
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        let components = trimmed.split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        for comp in components {
            guard !comp.isEmpty else { continue }

            if comp == "-" {
                throw PDFwringerError.invalidPageRange(comp)
            } else if comp.hasPrefix("-") {
                let numStr = String(comp.dropFirst())
                guard let end = Int(numStr), end >= 1 else {
                    throw PDFwringerError.invalidPageRange(comp)
                }
                guard end <= pageCount else {
                    throw PDFwringerError.invalidPageRange(comp)
                }
                result.append(contentsOf: 0..<end)
            } else if comp.hasSuffix("-") {
                let numStr = String(comp.dropLast())
                guard let start = Int(numStr), start >= 1 else {
                    throw PDFwringerError.invalidPageRange(comp)
                }
                guard start <= pageCount else {
                    throw PDFwringerError.invalidPageRange(comp)
                }
                result.append(contentsOf: (start - 1)..<pageCount)
            } else if comp.contains("-") {
                let parts = comp.split(separator: "-", maxSplits: 1)
                guard parts.count == 2,
                      let s = Int(parts[0]),
                      let e = Int(parts[1]),
                      s >= 1, e >= 1
                else {
                    throw PDFwringerError.invalidPageRange(comp)
                }
                guard s <= pageCount, e <= pageCount else {
                    throw PDFwringerError.invalidPageRange(comp)
                }
                if s <= e {
                    result.append(contentsOf: (s - 1)...(e - 1))
                } else {
                    result.append(contentsOf: stride(from: s - 1, through: e - 1, by: -1))
                }
            } else {
                guard let p = Int(comp), p >= 1 else {
                    throw PDFwringerError.invalidPageRange(comp)
                }
                guard p <= pageCount else {
                    throw PDFwringerError.invalidPageRange(comp)
                }
                result.append(p - 1)
            }
        }

        return result
    }
}
