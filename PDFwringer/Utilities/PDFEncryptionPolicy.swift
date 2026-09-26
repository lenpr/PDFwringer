import Foundation
import PDFKit

/// New encryption is produced only by Core Graphics after explicit flattening.
/// PDFKit's ordinary password writer defaults to legacy RC4 and is not used.
enum PDFEncryptionPolicy {
    /// PDFKit can silently remove protection from some owner-restricted inputs.
    /// Locked outputs can be inspected further only by callers holding a password.
    @MainActor
    static func requirePreservedProtection(from source: PDFDocument, in output: PDFDocument) throws {
        guard source.isEncrypted else { return }
        guard output.isEncrypted,
              output.isLocked || output.accessPermissions == source.accessPermissions else {
            throw PDFwringerError.protectionPreservationFailed
        }
    }

    static func validateNewPassword(_ password: String) throws {
        guard let data = password.data(using: .ascii), (1...32).contains(data.count),
              data.allSatisfy({ (32...126).contains($0) }) else {
            throw PDFwringerError.invalidEncryptionPassword
        }
    }

    /// A deliberately strict check of OUR newly generated Quartz output, not a
    /// parser for arbitrary input PDFs. Resolve Encrypt through the final classic
    /// xref so text or image bytes cannot masquerade as a security dictionary.
    /// Unknown writer layouts fail closed rather than guessing their cipher.
    static func hasAES128Encryption(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }
        let tail = String(decoding: data.suffix(1024), as: UTF8.self)
        guard let offsetText = capture(#"startxref\s+(\d+)\s+%%EOF\s*$"#, in: tail),
              let xrefOffset = Int(offsetText), (0..<data.count).contains(xrefOffset) else { return false }
        let xref = String(decoding: data[xrefOffset...], as: UTF8.self)
        let lines = xref.components(separatedBy: .newlines)
        guard lines.count >= 3, lines[0] == "xref" else { return false }
        let subsection = lines[1].split(whereSeparator: \.isWhitespace)
        guard subsection.count == 2, subsection[0] == "0",
              let count = Int(subsection[1]), count > 0, count < lines.count - 2,
              lines[count + 2] == "trailer" else { return false }
        let trailer = lines[(count + 3)...].joined(separator: "\n")
        guard let objectText = capture(#"/Encrypt\s+(\d+)\s+0\s+R\b"#, in: trailer),
              let object = Int(objectText), (1..<count).contains(object) else { return false }
        let entry = lines[object + 2].split(whereSeparator: \.isWhitespace)
        guard entry.count == 3, entry[1] == "00000", entry[2] == "n",
              let offset = Int(entry[0]), (0..<xrefOffset).contains(offset),
              xrefOffset - offset <= 4096 else { return false }
        let security = String(decoding: data[offset..<xrefOffset], as: UTF8.self)
        // Exact dictionary emitted by the supported Quartz AES-128 writer. The
        // key material remains local and is never logged or returned to the UI.
        let pattern = #"^OBJECT\s+0\s+obj\s*<<\s*/Filter\s*/Standard\s*/V\s+4\s*/R\s+4\s*/Length\s+128\s*/CF\s*<<\s*/StdCF\s*<<\s*/AuthEvent\s*/DocOpen\s*/CFM\s*/AESV2\s*/Length\s+16\s*>>\s*>>\s*/StmF\s*/StdCF\s*/StrF\s*/StdCF\s*/EncryptMetadata\s+true\s*/O\s*<[0-9a-fA-F]{64}>\s*/U\s*<[0-9a-fA-F]{64}>\s*/P\s+-4\s*>>\s*endobj\s*$"#
            .replacingOccurrences(of: "OBJECT", with: String(object))
        return security.range(of: pattern, options: .regularExpression) != nil
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
