import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Reads and writes PDF document metadata (title, author, subject, keywords, creator).
@MainActor
struct PDFMetadataEditor {

    struct Metadata: Equatable {
        var title: String
        var author: String
        var subject: String
        var keywords: String
        var creator: String

        static let empty = Metadata(title: "", author: "", subject: "", keywords: "", creator: "")
    }

    /// Maximum length for metadata fields to prevent DoS from crafted PDFs with huge metadata.
    private static let maxFieldLength = 10_000
    /// Maximum number of keywords to join before truncating.
    private static let maxKeywords = 500

    /// Reads metadata from a PDF file. Truncates fields to prevent DoS.
    func read(from url: URL) -> Metadata {
        guard let document = PDFDocument(url: url) else {
            return .empty
        }

        return read(from: document)
    }

    /// Reads metadata from an already-open document, including one the caller unlocked.
    func read(from document: PDFDocument) -> Metadata {
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

    private static func truncate(_ string: String) -> String {
        if string.count <= maxFieldLength { return string }
        return String(string.prefix(maxFieldLength))
    }

    /// Writes metadata to a PDF file, saving to destination.
    /// If `password` is non-nil and non-empty, encrypts the output with that password.
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
    func write(
        metadata: Metadata,
        document: PDFDocument,
        source: URL,
        destination: URL,
        password: String? = nil,
        removeProtection: Bool = false,
        flattenAnnotations: Bool = false,
        progress: ((Double) -> Void)? = nil
    ) async throws {
        guard source.standardizedFileURL != destination.standardizedFileURL else {
            throw PDFwringerError.sourceEqualsDestination
        }

        if document.isLocked { throw PDFwringerError.documentIsLocked }
        guard document.pageCount > 0 else { throw PDFwringerError.cannotOpenDocument }
        try Task.checkCancellation()

        let outputPassword = removeProtection ? nil : password

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
            try writeNormalPDF(
                sourceDocument: document,
                metadata: metadata,
                destination: destination,
                password: outputPassword,
                removeProtection: removeProtection
            )
            progress?(1.0)
        }
    }

    private func buildAttributes(from metadata: Metadata) -> [PDFDocumentAttribute: Any] {
        var attrs: [PDFDocumentAttribute: Any] = [:]
        if !metadata.title.isEmpty { attrs[.titleAttribute] = metadata.title }
        if !metadata.author.isEmpty { attrs[.authorAttribute] = metadata.author }
        if !metadata.subject.isEmpty { attrs[.subjectAttribute] = metadata.subject }
        if !metadata.keywords.isEmpty {
            attrs[.keywordsAttribute] = parsedKeywords(from: metadata)
        }
        if !metadata.creator.isEmpty { attrs[.creatorAttribute] = metadata.creator }
        return attrs
    }

    private func buildContextInfo(from metadata: Metadata, password: String?) -> [CFString: Any] {
        var info: [CFString: Any] = [:]
        if !metadata.title.isEmpty { info[kCGPDFContextTitle] = metadata.title }
        if !metadata.author.isEmpty { info[kCGPDFContextAuthor] = metadata.author }
        if !metadata.subject.isEmpty { info[kCGPDFContextSubject] = metadata.subject }
        if !metadata.keywords.isEmpty { info[kCGPDFContextKeywords] = parsedKeywords(from: metadata) }
        if !metadata.creator.isEmpty { info[kCGPDFContextCreator] = metadata.creator }
        if let password, !password.isEmpty {
            info[kCGPDFContextOwnerPassword] = password
            info[kCGPDFContextUserPassword] = password
            info[kCGPDFContextEncryptionKeyLength] = 128
        }
        return info
    }

    private func parsedKeywords(from metadata: Metadata) -> [String] {
        metadata.keywords
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func writeNormalPDF(
        sourceDocument: PDFDocument,
        metadata: Metadata,
        destination: URL,
        password: String?,
        removeProtection: Bool
    ) throws {
        let doc = try outputDocument(from: sourceDocument, removeProtection: removeProtection)
        doc.documentAttributes = buildAttributes(from: metadata)

        var writeOptions: [PDFDocumentWriteOption: Any] = [:]
        if let pw = password, !pw.isEmpty {
            writeOptions[.ownerPasswordOption] = pw
            writeOptions[.userPasswordOption] = pw
        }

        try AtomicFileWriter.write(to: destination) { tempURL in
            let didWrite: Bool
            if writeOptions.isEmpty {
                didWrite = doc.write(to: tempURL)
            } else {
                didWrite = doc.write(to: tempURL, withOptions: writeOptions)
            }
            guard didWrite, let verificationDocument = PDFDocument(url: tempURL) else {
                return false
            }
            if let password, !password.isEmpty {
                guard verificationDocument.isEncrypted,
                      verificationDocument.isLocked,
                      verificationDocument.unlock(withPassword: password) else { return false }
                return verificationDocument.pageCount == sourceDocument.pageCount
            }
            if verificationDocument.isLocked {
                return verificationDocument.isEncrypted
            }
            return verificationDocument.pageCount == sourceDocument.pageCount
        }
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

                try autoreleasepool {
                    guard let page = doc.page(at: i) else {
                        throw PDFwringerError.cannotWriteOutput
                    }
                    let bounds = page.bounds(for: .cropBox)
                    let rotation = page.rotation
                    let angle = ((rotation % 360) + 360) % 360

                    let displaySize: CGSize
                    if angle == 90 || angle == 270 {
                        displaySize = CGSize(width: bounds.height, height: bounds.width)
                    } else {
                        displaySize = bounds.size
                    }

                    let scale = dpi / 72.0
                    let rawPixelWidth = displaySize.width * scale
                    let rawPixelHeight = displaySize.height * scale
                    let rawMaxLong = 16.5 * dpi
                    let rawMaxShort = 11.7 * dpi
                    guard displaySize.width.isFinite, displaySize.height.isFinite,
                          displaySize.width > 0, displaySize.height > 0,
                          rawPixelWidth.isFinite, rawPixelHeight.isFinite,
                          rawPixelWidth < CGFloat(Int.max), rawPixelHeight < CGFloat(Int.max),
                          rawMaxLong.isFinite, rawMaxShort.isFinite,
                          rawMaxLong > 0, rawMaxShort > 0,
                          rawMaxLong < CGFloat(Int.max), rawMaxShort < CGFloat(Int.max)
                    else {
                        throw PDFwringerError.cannotWriteOutput
                    }

                    var pixelW = max(1, Int(displaySize.width * scale))
                    var pixelH = max(1, Int(displaySize.height * scale))

                    let maxLong = Int(16.5 * dpi)
                    let maxShort = Int(11.7 * dpi)
                    let longSide = max(pixelW, pixelH)
                    let shortSide = min(pixelW, pixelH)
                    var effectiveScale = scale
                    if longSide > maxLong || shortSide > maxShort {
                        let downscale = min(Double(maxLong) / Double(longSide), Double(maxShort) / Double(shortSide))
                        pixelW = max(1, Int(Double(pixelW) * downscale))
                        pixelH = max(1, Int(Double(pixelH) * downscale))
                        effectiveScale = scale * downscale
                    }

                    guard let bitmap = CGContext(
                        data: nil, width: pixelW, height: pixelH,
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    ) else {
                        throw PDFwringerError.cannotWriteOutput
                    }

                    bitmap.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
                    bitmap.fill(CGRect(x: 0, y: 0, width: pixelW, height: pixelH))

                    bitmap.scaleBy(x: effectiveScale, y: effectiveScale)
                    page.transform(bitmap, for: .cropBox)
                    page.draw(with: .cropBox, to: bitmap)

                    guard let rendered = bitmap.makeImage(),
                          let jpegData = PDFCompressor.jpegEncode(image: rendered, quality: quality)
                    else {
                        throw PDFwringerError.cannotWriteOutput
                    }

                    guard let provider = CGDataProvider(data: jpegData as CFData),
                          let jpegImage = CGImage(
                              jpegDataProviderSource: provider,
                              decode: nil,
                              shouldInterpolate: true,
                              intent: .defaultIntent
                          )
                    else {
                        throw PDFwringerError.cannotWriteOutput
                    }

                    var outBox = CGRect(origin: .zero, size: displaySize)
                    outputCtx.beginPage(mediaBox: &outBox)
                    outputCtx.draw(jpegImage, in: outBox)
                    outputCtx.endPage()
                }

                progress?(Double(i + 1) / Double(pageCount))
                await Task.yield()
            }

            try Task.checkCancellation()
            outputCtx.closePDF()
            didCloseOutput = true

            guard let verificationDocument = PDFDocument(url: stagedURL) else { return false }
            if expectsEncryption {
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
            try Task.checkCancellation()
            return true
        }
    }
}
