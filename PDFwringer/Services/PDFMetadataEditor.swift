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
        flattenAnnotations: Bool = false
    ) throws {
        guard FileManager.default.isReadableFile(atPath: source.path(percentEncoded: false)) else {
            throw PDFwringerError.fileNotReadable(source.lastPathComponent)
        }

        guard let doc = PDFDocument(url: source) else {
            throw PDFwringerError.cannotOpenDocument
        }
        if doc.isLocked { throw PDFwringerError.documentIsLocked }

        Log.metadata.info("Writing metadata: title=\(metadata.title.isEmpty ? "(empty)" : metadata.title), encrypted=\(password != nil), flatten=\(flattenAnnotations)")

        if flattenAnnotations {
            try writeFlattenedPDF(doc: doc, metadata: metadata, destination: destination, password: password)
        } else {
            try writeNormalPDF(doc: doc, metadata: metadata, destination: destination, password: password)
        }
    }

    private func writeNormalPDF(
        doc: PDFDocument,
        metadata: Metadata,
        destination: URL,
        password: String?
    ) throws {
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

        doc.documentAttributes = attrs

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
        password: String?
    ) throws {
        let pageCount = doc.pageCount
        guard pageCount > 0 else { throw PDFwringerError.cannotOpenDocument }

        let dpi: CGFloat = 300
        let quality: CGFloat = 0.92

        let tempURL = URL.temporaryDirectory.appending(component: UUID().uuidString + ".pdf")
        var emptyBox = CGRect.zero
        guard let outputCtx = CGContext(tempURL as CFURL, mediaBox: &emptyBox, nil) else {
            throw PDFwringerError.cannotCreateOutput
        }

        for i in 0..<pageCount {
            autoreleasepool {
                guard let page = doc.page(at: i) else { return }
                let bounds = page.bounds(for: .cropBox)
                let rotation = page.rotation

                let displaySize: CGSize
                let angle = ((rotation % 360) + 360) % 360
                if angle == 90 || angle == 270 {
                    displaySize = CGSize(width: bounds.height, height: bounds.width)
                } else {
                    displaySize = bounds.size
                }

                let scale = dpi / 72.0
                let pixelW = max(1, Int(displaySize.width * scale))
                let pixelH = max(1, Int(displaySize.height * scale))

                guard let bitmap = CGContext(
                    data: nil, width: pixelW, height: pixelH,
                    bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return }

                bitmap.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
                bitmap.fill(CGRect(x: 0, y: 0, width: pixelW, height: pixelH))

                let nsSize = NSSize(width: pixelW, height: pixelH)
                let image = NSImage(size: nsSize)
                image.lockFocus()
                if let ctx = NSGraphicsContext.current?.cgContext {
                    ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
                    ctx.fill(CGRect(origin: .zero, size: nsSize))

                    ctx.saveGState()
                    ctx.scaleBy(x: scale, y: scale)
                    page.draw(with: .cropBox, to: ctx)
                    ctx.restoreGState()
                }
                image.unlockFocus()

                guard let tiffData = image.tiffRepresentation,
                      let bitmapRep = NSBitmapImageRep(data: tiffData),
                      let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: quality])
                else { return }

                guard let provider = CGDataProvider(data: jpegData as CFData),
                      let jpegImage = CGImage(
                          jpegDataProviderSource: provider,
                          decode: nil,
                          shouldInterpolate: true,
                          intent: .defaultIntent
                      )
                else { return }

                var outBox = CGRect(origin: .zero, size: displaySize)
                outputCtx.beginPage(mediaBox: &outBox)
                outputCtx.draw(jpegImage, in: outBox)
                outputCtx.endPage()
            }
        }

        outputCtx.closePDF()

        // Apply metadata to the flattened PDF
        guard let flatDoc = PDFDocument(url: tempURL) else {
            try? FileManager.default.removeItem(at: tempURL)
            throw PDFwringerError.cannotWriteOutput
        }

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
        flatDoc.documentAttributes = attrs

        var writeOptions: [PDFDocumentWriteOption: Any] = [:]
        if let pw = password, !pw.isEmpty {
            writeOptions[.ownerPasswordOption] = pw
            writeOptions[.userPasswordOption] = pw
        }

        let finalTempURL = URL.temporaryDirectory.appending(component: UUID().uuidString + ".pdf")
        let writeSuccess: Bool
        if writeOptions.isEmpty {
            writeSuccess = flatDoc.write(to: finalTempURL)
        } else {
            writeSuccess = flatDoc.write(to: finalTempURL, withOptions: writeOptions)
        }

        try? FileManager.default.removeItem(at: tempURL)

        guard writeSuccess else {
            try? FileManager.default.removeItem(at: finalTempURL)
            throw PDFwringerError.cannotWriteOutput
        }

        do {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: finalTempURL)
        } catch {
            try? FileManager.default.removeItem(at: finalTempURL)
            throw error
        }
    }
}
