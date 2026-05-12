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

    /// Reads metadata from a PDF file.
    func read(from url: URL) -> Metadata {
        guard let doc = PDFDocument(url: url),
              let attrs = doc.documentAttributes else {
            return .empty
        }

        return Metadata(
            title: attrs[PDFDocumentAttribute.titleAttribute] as? String ?? "",
            author: attrs[PDFDocumentAttribute.authorAttribute] as? String ?? "",
            subject: attrs[PDFDocumentAttribute.subjectAttribute] as? String ?? "",
            keywords: (attrs[PDFDocumentAttribute.keywordsAttribute] as? [String])?.joined(separator: ", ") ?? "",
            creator: attrs[PDFDocumentAttribute.creatorAttribute] as? String ?? ""
        )
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
        guard source.standardizedFileURL != destination.standardizedFileURL else {
            throw PDFwringerError.sourceEqualsDestination
        }

        guard FileManager.default.isReadableFile(atPath: source.path(percentEncoded: false)) else {
            throw PDFwringerError.fileNotReadable(source.lastPathComponent)
        }

        guard let doc = PDFDocument(url: source) else {
            throw PDFwringerError.cannotOpenDocument
        }
        if doc.isLocked { throw PDFwringerError.documentIsLocked }

        Log.metadata.info("Writing metadata: title=\(metadata.title.isEmpty ? "(empty)" : metadata.title), encrypted=\(password != nil), flatten=\(flattenAnnotations)")

        if flattenAnnotations {
            try await writeFlattenedPDF(doc: doc, metadata: metadata, destination: destination, password: password, progress: progress)
        } else {
            try writeNormalPDF(doc: doc, metadata: metadata, destination: destination, password: password)
            progress?(1.0)
        }
    }

    private func buildAttributes(from metadata: Metadata) -> [PDFDocumentAttribute: Any] {
        var attrs: [PDFDocumentAttribute: Any] = [:]
        if !metadata.title.isEmpty { attrs[.titleAttribute] = metadata.title }
        if !metadata.author.isEmpty { attrs[.authorAttribute] = metadata.author }
        if !metadata.subject.isEmpty { attrs[.subjectAttribute] = metadata.subject }
        if !metadata.keywords.isEmpty {
            attrs[.keywordsAttribute] = metadata.keywords
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
        if !metadata.creator.isEmpty { attrs[.creatorAttribute] = metadata.creator }
        return attrs
    }

    private func writeNormalPDF(
        doc: PDFDocument,
        metadata: Metadata,
        destination: URL,
        password: String?
    ) throws {
        doc.documentAttributes = buildAttributes(from: metadata)

        var writeOptions: [PDFDocumentWriteOption: Any] = [:]
        if let pw = password, !pw.isEmpty {
            writeOptions[.ownerPasswordOption] = pw
            writeOptions[.userPasswordOption] = pw
        }

        try AtomicFileWriter.write(to: destination) { tempURL in
            if writeOptions.isEmpty {
                doc.write(to: tempURL)
            } else {
                doc.write(to: tempURL, withOptions: writeOptions)
            }
        }
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

        let tempURL = AtomicFileWriter.tempDirectory.appending(component: UUID().uuidString + ".pdf")
        var emptyBox = CGRect.zero
        guard let outputCtx = CGContext(tempURL as CFURL, mediaBox: &emptyBox, nil) else {
            throw PDFwringerError.cannotCreateOutput
        }

        var skippedPages = 0

        for i in 0..<pageCount {
            try Task.checkCancellation()

            autoreleasepool {
                guard let page = doc.page(at: i) else { skippedPages += 1; return }
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
                ) else { skippedPages += 1; return }

                bitmap.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
                bitmap.fill(CGRect(x: 0, y: 0, width: pixelW, height: pixelH))

                bitmap.scaleBy(x: effectiveScale, y: effectiveScale)
                page.transform(bitmap, for: .cropBox)
                page.draw(with: .cropBox, to: bitmap)

                guard let rendered = bitmap.makeImage() else { skippedPages += 1; return }
                guard let jpegData = PDFCompressor.jpegEncode(image: rendered, quality: quality) else { skippedPages += 1; return }

                guard let provider = CGDataProvider(data: jpegData as CFData),
                      let jpegImage = CGImage(
                          jpegDataProviderSource: provider,
                          decode: nil,
                          shouldInterpolate: true,
                          intent: .defaultIntent
                      )
                else { skippedPages += 1; return }

                var outBox = CGRect(origin: .zero, size: displaySize)
                outputCtx.beginPage(mediaBox: &outBox)
                outputCtx.draw(jpegImage, in: outBox)
                outputCtx.endPage()
            }

            progress?(Double(i + 1) / Double(pageCount))
            await Task.yield()
        }

        if skippedPages == pageCount {
            outputCtx.closePDF()
            try? FileManager.default.removeItem(at: tempURL)
            throw PDFwringerError.cannotWriteOutput
        }

        if skippedPages > 0 {
            Log.metadata.warning("Flatten skipped \(skippedPages) of \(pageCount) pages")
        }

        outputCtx.closePDF()

        // Apply metadata to the flattened PDF
        guard let flatDoc = PDFDocument(url: tempURL) else {
            try? FileManager.default.removeItem(at: tempURL)
            throw PDFwringerError.cannotWriteOutput
        }

        flatDoc.documentAttributes = buildAttributes(from: metadata)

        var writeOptions: [PDFDocumentWriteOption: Any] = [:]
        if let pw = password, !pw.isEmpty {
            writeOptions[.ownerPasswordOption] = pw
            writeOptions[.userPasswordOption] = pw
        }

        try AtomicFileWriter.write(to: destination) { finalTemp in
            if writeOptions.isEmpty {
                flatDoc.write(to: finalTemp)
            } else {
                flatDoc.write(to: finalTemp, withOptions: writeOptions)
            }
        }

        try? FileManager.default.removeItem(at: tempURL)
    }
}
