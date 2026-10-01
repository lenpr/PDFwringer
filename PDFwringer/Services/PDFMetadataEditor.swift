import Foundation
import PDFKit

/// Reads and writes PDF document metadata (title, author, subject, keywords, creator).
@MainActor
struct PDFMetadataEditor {

    struct Metadata: Equatable, Sendable {
        var title: String
        var author: String
        var subject: String
        var keywords: String
        var creator: String

        static let empty = Metadata(title: "", author: "", subject: "", keywords: "", creator: "")
    }

    /// Maximum length for metadata fields to prevent DoS from crafted PDFs with huge metadata.
    private nonisolated static let maxFieldLength = 10_000
    /// Maximum number of keywords to join before truncating.
    private nonisolated static let maxKeywords = 500

    /// Reads metadata from a PDF file. Truncates fields to prevent DoS.
    func read(from url: URL) -> Metadata {
        guard let document = PDFDocument(url: url) else {
            return .empty
        }

        return read(from: document)
    }

    /// Reads metadata from an already-open document, including one the caller unlocked.
    func read(from document: PDFDocument) -> Metadata {
        Self.readMetadata(from: document)
    }

    // Called only with a document owned by the current actor/worker.
    private nonisolated static func readMetadata(from document: PDFDocument) -> Metadata {
        guard !document.isLocked,
              let attrs = document.documentAttributes else { return .empty }

        let keywords: String
        if let kwArray = attrs[PDFDocumentAttribute.keywordsAttribute] as? [String] {
            keywords = kwArray.prefix(Self.maxKeywords).joined(separator: ", ")
        } else {
            keywords = ""
        }

        return Metadata(
            title: Self.truncate(attrs[PDFDocumentAttribute.titleAttribute] as? String ?? ""),
            author: Self.truncate(attrs[PDFDocumentAttribute.authorAttribute] as? String ?? ""),
            subject: Self.truncate(attrs[PDFDocumentAttribute.subjectAttribute] as? String ?? ""),
            keywords: Self.truncate(keywords),
            creator: Self.truncate(attrs[PDFDocumentAttribute.creatorAttribute] as? String ?? "")
        )
    }

    private nonisolated static func truncate(_ string: String) -> String {
        if string.count <= maxFieldLength { return string }
        return String(string.prefix(maxFieldLength))
    }

    /// Writes metadata to a PDF file, saving to destination.
    /// New password protection requires explicit flattening and verified AES-128 output.
    /// If `flattenAnnotations` is true, rasterizes each page at 300 DPI to burn annotations into content.
    func write(
        metadata: Metadata,
        source: URL,
        destination: URL,
        password: String? = nil,
        flattenAnnotations: Bool = false,
        progress: ((Double) -> Void)? = nil
    ) async throws {
        guard FileManager.default.isReadableFile(atPath: source.path(percentEncoded: false)) else {
            throw PDFwringerError.fileNotReadable(source.lastPathComponent)
        }
        guard let document = PDFDocument(url: source) else {
            throw PDFwringerError.cannotOpenDocument
        }
        if document.isLocked { throw PDFwringerError.documentIsLocked }

        try await write(
            metadata: metadata,
            document: document,
            source: source,
            destination: destination,
            password: password,
            removeProtection: false,
            flattenAnnotations: flattenAnnotations,
            progress: progress
        )
    }

    /// Writes metadata using an already-open document as the authoritative content.
    /// Set `removeProtection` explicitly to rebuild an encrypted input without protection.
    /// Ordinary encrypted saves retain their existing security settings; existingPassword
    /// unlocks the staged result for verification. `password` creates a new password only
    /// for explicitly flattened output, never through PDFKit's legacy RC4 writer.
    func write(
        metadata: Metadata,
        document: PDFDocument,
        source: URL,
        destination: URL,
        password: String? = nil,
        removeProtection: Bool = false,
        existingPassword: String? = nil,
        flattenAnnotations: Bool = false,
        progress: ((Double) -> Void)? = nil
    ) async throws {
        try FileSystemIdentity.requireDistinct(source, destination)

        if document.isLocked { throw PDFwringerError.documentIsLocked }
        guard document.pageCount > 0 else { throw PDFwringerError.cannotOpenDocument }
        if flattenAnnotations || removeProtection {
            try PDFPermissionPolicy.require(.copyContent, .changeDocument, for: document)
        } else {
            try PDFPermissionPolicy.require(.changeDocument, for: document)
        }
        try Task.checkCancellation()

        let outputPassword = removeProtection ? nil : password
        if let outputPassword, !outputPassword.isEmpty {
            guard flattenAnnotations else { throw PDFwringerError.passwordRequiresFlattening }
            try PDFEncryptionPolicy.validateNewPassword(outputPassword)
        }
        if document.isEncrypted && !removeProtection {
            if flattenAnnotations {
                guard outputPassword?.isEmpty == false else { throw PDFwringerError.outputPasswordRequired }
            }
        }

        Log.metadata.info("Writing metadata: encrypted=\(outputPassword != nil), removeProtection=\(removeProtection), flatten=\(flattenAnnotations)")

        if flattenAnnotations {
            try await writeFlattenedPDF(
                doc: document,
                metadata: metadata,
                destination: destination,
                password: outputPassword,
                progress: progress
            )
        } else {
            try await writeNormalPDF(
                sourceDocument: document,
                source: source,
                metadata: metadata,
                destination: destination,
                verificationPassword: existingPassword,
                removeProtection: removeProtection
            )
        }
        progress?(1.0)
    }

    private nonisolated static func buildAttributes(from metadata: Metadata) -> [PDFDocumentAttribute: Any] {
        var attrs: [PDFDocumentAttribute: Any] = [:]
        if !metadata.title.isEmpty { attrs[.titleAttribute] = metadata.title }
        if !metadata.author.isEmpty { attrs[.authorAttribute] = metadata.author }
        if !metadata.subject.isEmpty { attrs[.subjectAttribute] = metadata.subject }
        if !metadata.keywords.isEmpty {
            attrs[.keywordsAttribute] = Self.parsedKeywords(from: metadata)
        }
        if !metadata.creator.isEmpty { attrs[.creatorAttribute] = metadata.creator }
        return attrs
    }

    private func buildContextInfo(from metadata: Metadata, password: String?) -> [CFString: Any] {
        var info: [CFString: Any] = [:]
        if !metadata.title.isEmpty { info[kCGPDFContextTitle] = metadata.title }
        if !metadata.author.isEmpty { info[kCGPDFContextAuthor] = metadata.author }
        if !metadata.subject.isEmpty { info[kCGPDFContextSubject] = metadata.subject }
        if !metadata.keywords.isEmpty { info[kCGPDFContextKeywords] = Self.parsedKeywords(from: metadata) }
        if !metadata.creator.isEmpty { info[kCGPDFContextCreator] = metadata.creator }
        if let password, !password.isEmpty {
            info[kCGPDFContextOwnerPassword] = password
            info[kCGPDFContextUserPassword] = password
            info[kCGPDFContextEncryptionKeyLength] = 128
        }
        return info
    }

    private nonisolated static func parsedKeywords(from metadata: Metadata) -> [String] {
        metadata.keywords
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func writeNormalPDF(
        sourceDocument: PDFDocument,
        source: URL,
        metadata: Metadata,
        destination: URL,
        verificationPassword: String?,
        removeProtection: Bool
    ) async throws {
        if !sourceDocument.isEncrypted {
            // Keep the existing normalization snapshot, including unsaved edits.
            // Reopening, metadata edits, final serialization and verification are
            // performed on a worker that owns every PDFKit reference it uses.
            let staged = try AtomicFileWriter.StagedFile(destination: destination)
            defer { staged.cleanup() }
            let count = sourceDocument.pageCount
            guard let data = sourceDocument.dataRepresentation(), !data.isEmpty else {
                throw PDFwringerError.cannotWriteOutput
            }
            let worker = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                guard let output = PDFDocument(data: data), !output.isEncrypted,
                      output.pageCount == count else { throw PDFwringerError.cannotWriteOutput }
                output.documentAttributes = Self.buildAttributes(from: metadata)
                guard output.write(to: staged.url) else { throw PDFwringerError.cannotWriteOutput }
                try Task.checkCancellation()
                guard let verified = PDFDocument(url: staged.url), !verified.isEncrypted,
                      verified.pageCount == count else { throw PDFwringerError.cannotWriteOutput }
                try Self.verifyMetadata(metadata, in: verified)
                for index in 0..<count {
                    try Task.checkCancellation()
                    guard verified.page(at: index) != nil else { throw PDFwringerError.cannotWriteOutput }
                }
                try FileSystemIdentity.requireDistinct(source, destination)
                try staged.commit()
            }
            try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: { worker.cancel() }
            return
        }
        try Task.checkCancellation()
        let staged = try AtomicFileWriter.StagedFile(destination: destination)
        defer { staged.cleanup() }
        let doc = try outputDocument(from: sourceDocument, removeProtection: removeProtection)
        doc.documentAttributes = Self.buildAttributes(from: metadata)
        let count = sourceDocument.pageCount
        let encrypted = sourceDocument.isEncrypted
        let permissions = UInt(sourceDocument.accessPermissions.rawValue)
        await Task.yield()
        try Task.checkCancellation()
        guard let data = doc.dataRepresentation(), !data.isEmpty else {
            throw PDFwringerError.cannotWriteOutput
        }
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            try data.write(to: staged.url)
            try Task.checkCancellation()
            guard let verified = PDFDocument(url: staged.url) else { throw PDFwringerError.cannotWriteOutput }
            if encrypted && !removeProtection {
                try PDFEncryptionPolicy.requirePreservedProtection(
                    sourceIsEncrypted: encrypted, sourcePermissions: permissions, in: verified)
                guard !verified.isLocked || verified.unlock(withPassword: verificationPassword ?? "") else {
                    throw PDFwringerError.existingPasswordRequired
                }
                try PDFEncryptionPolicy.requirePreservedProtection(
                    sourceIsEncrypted: encrypted, sourcePermissions: permissions, in: verified)
            } else if verified.isEncrypted {
                throw PDFwringerError.cannotWriteOutput
            }
            guard !verified.isLocked, verified.pageCount == count else {
                throw PDFwringerError.metadataVerificationFailed
            }
            try Self.verifyMetadata(metadata, in: verified)
            for index in 0..<count {
                try Task.checkCancellation()
                guard verified.page(at: index) != nil else { throw PDFwringerError.cannotWriteOutput }
            }
            try FileSystemIdentity.requireDistinct(source, destination)
            try staged.commit()
        }
        try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: { worker.cancel() }
    }

    /// `PDFDocument.copy()` retains an unlocked document's protection settings.
    /// Removing protection therefore requires a fresh document populated with copied pages.
    private func outputDocument(from source: PDFDocument, removeProtection: Bool) throws -> PDFDocument {
        guard removeProtection else {
            guard let copiedDocument = source.copy() as? PDFDocument else {
                throw PDFwringerError.cannotOpenDocument
            }
            return copiedDocument
        }

        let unprotectedDocument = PDFDocument()
        for pageIndex in 0..<source.pageCount {
            guard let page = source.page(at: pageIndex),
                  let copiedPage = page.copy() as? PDFPage else {
                throw PDFwringerError.cannotOpenDocument
            }
            unprotectedDocument.insert(copiedPage, at: unprotectedDocument.pageCount)
        }
        return unprotectedDocument
    }

    private func writeFlattenedPDF(
        doc: PDFDocument,
        metadata: Metadata,
        destination: URL,
        password: String?,
        progress: ((Double) -> Void)?
    ) async throws {
        let pageCount = doc.pageCount
        guard pageCount > 0 else { throw PDFwringerError.cannotOpenDocument }

        let dpi: CGFloat = 300
        let quality: CGFloat = 0.92
        let contextInfo = buildContextInfo(from: metadata, password: password)
        let expectsEncryption = password?.isEmpty == false

        try await AtomicFileWriter.write(to: destination) { stagedURL in
            var emptyBox = CGRect.zero
            guard let outputCtx = CGContext(
                stagedURL as CFURL,
                mediaBox: &emptyBox,
                contextInfo as CFDictionary
            ) else {
                throw PDFwringerError.cannotCreateOutput
            }

            var didCloseOutput = false
            defer {
                if !didCloseOutput { outputCtx.closePDF() }
            }

            for i in 0..<pageCount {
                try Task.checkCancellation()

                let pageData = try autoreleasepool { () throws -> Data in
                    guard let page = doc.page(at: i) else {
                        throw PDFwringerError.cannotWriteOutput
                    }
                    guard let data = page.dataRepresentation else {
                        throw PDFwringerError.cannotWriteOutput
                    }
                    return data
                }

                let encodedPage = try await PDFPageWorker.run(pageData: pageData) { page in
                    guard let (rendered, displaySize) = PDFRasterizer.render(
                        page,
                        dpi: dpi,
                        grayscale: false
                    ), let jpegData = PDFRasterizer.jpegData(for: rendered, quality: quality)
                    else {
                        throw PDFwringerError.cannotWriteOutput
                    }
                    return PDFRasterizer.JPEGPage(data: jpegData, displaySize: displaySize)
                }

                try autoreleasepool {
                    try PDFRasterizer.append(encodedPage, to: outputCtx)
                }

                progress?(min(0.99, Double(i + 1) / Double(pageCount)))
            }

            try Task.checkCancellation()
            outputCtx.closePDF()
            didCloseOutput = true

            guard let verificationDocument = PDFDocument(url: stagedURL) else { return false }
            if expectsEncryption {
                guard PDFEncryptionPolicy.hasAES128Encryption(at: stagedURL) else {
                    throw PDFwringerError.unsupportedEncryption
                }
                guard verificationDocument.isEncrypted,
                      verificationDocument.isLocked,
                      let password,
                      verificationDocument.unlock(withPassword: password) else {
                    return false
                }
            } else if verificationDocument.isEncrypted || verificationDocument.isLocked {
                return false
            }
            guard verificationDocument.pageCount == pageCount,
                  (0..<pageCount).allSatisfy({ verificationDocument.page(at: $0) != nil }) else {
                return false
            }
            try Self.verifyMetadata(metadata, in: verificationDocument)
            try Task.checkCancellation()
            return true
        }
    }

    private nonisolated static func verifyMetadata(_ expected: Metadata, in document: PDFDocument) throws {
        let actual = Self.readMetadata(from: document)
        guard actual.title == expected.title,
              actual.author == expected.author,
              actual.subject == expected.subject,
              actual.creator == expected.creator,
              parsedKeywords(from: actual) == Self.parsedKeywords(from: expected) else {
            throw PDFwringerError.metadataVerificationFailed
        }
    }
}
