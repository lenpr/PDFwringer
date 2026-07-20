import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Handles PDF compression via two strategies: lossless optimization (re-serialize with metadata stripped)
/// or lossy rasterization (render pages as JPEG at a target DPI).
@MainActor
struct PDFCompressor {

    struct Result {
        var outputSize: Int64
    }

    nonisolated private static let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Compresses a PDF from `source` to `destination` using the selected strategy.
    @discardableResult
    func compress(
        source: URL,
        destination: URL,
        level: CompressionLevel,
        quality: JPEGQuality,
        grayscale: Bool,
        stripMetadata: Bool,
        progress: (Double) -> Void
    ) async throws -> Result {
        guard FileManager.default.isReadableFile(atPath: source.path(percentEncoded: false)) else {
            throw PDFwringerError.fileNotReadable(source.lastPathComponent)
        }
        guard let document = PDFDocument(url: source) else {
            throw PDFwringerError.cannotOpenDocument
        }
        if document.isLocked { throw PDFwringerError.documentIsLocked }

        return try await compress(
            document: document,
            source: source,
            destination: destination,
            level: level,
            quality: quality,
            grayscale: grayscale,
            stripMetadata: stripMetadata,
            progress: progress
        )
    }

    /// Compresses the supplied, already-open document. The URL is used only for
    /// source identity, naming, and size estimates; document content comes from `document`.
    @discardableResult
    func compress(
        document: PDFDocument,
        source: URL,
        destination: URL,
        level: CompressionLevel,
        quality: JPEGQuality,
        grayscale: Bool,
        stripMetadata: Bool,
        progress: (Double) -> Void
    ) async throws -> Result {
        let start = ContinuousClock.now
        Log.compress.info("Starting compression: level=\(level.title), quality=\(quality.title), grayscale=\(grayscale)")

        guard source.standardizedFileURL != destination.standardizedFileURL else {
            throw PDFwringerError.sourceEqualsDestination
        }
        if document.isLocked { throw PDFwringerError.documentIsLocked }
        guard document.pageCount > 0 else { throw PDFwringerError.cannotOpenDocument }

        if level.isRasterize {
            try await compressRasterize(
                document: document,
                source: source,
                destination: destination,
                dpi: level.dpi,
                quality: quality.value,
                grayscale: grayscale,
                progress: progress
            )
        } else {
            try await compressOptimize(
                document: document,
                destination: destination,
                stripMetadata: stripMetadata,
                progress: progress
            )
        }
        let outputSize = (try? FileManager.default.attributesOfItem(atPath: destination.path(percentEncoded: false))[.size] as? Int64) ?? 0
        guard outputSize > 0 else { throw PDFwringerError.cannotWriteOutput }
        let elapsed = ContinuousClock.now - start
        Log.compress.info("Compression complete: output=\(Formatting.fileSize(outputSize)), duration=\(elapsed)")
        return Result(outputSize: outputSize)
    }

    /// Compress a single page to estimate total output size without processing the entire document.
    /// Extrapolates from first-page JPEG size to all pages (assumes roughly uniform page content).
    /// Returns nil if the source cannot be read.
    nonisolated func compressFirstPage(source: URL, level: CompressionLevel, quality: JPEGQuality, grayscale: Bool) -> Int64? {
        guard level.isRasterize else {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: source.path(percentEncoded: false)),
                  let size = attrs[.size] as? Int64 else { return nil }
            return Int64(Double(size) * 0.95)
        }

        guard let doc = Self.openPDF(at: source),
              doc.numberOfPages > 0,
              let page = doc.page(at: 1) else { return nil }

        guard let (rendered, _) = Self.renderPage(page, dpi: level.dpi, grayscale: grayscale),
              let jpegData = Self.jpegEncode(image: rendered, quality: quality.value)
        else { return nil }

        let pageSize = Int64(jpegData.count)
        let pageCount = Int64(doc.numberOfPages)
        return (pageSize + 200) * pageCount + 1000
    }

    // MARK: - Optimize path (preserves text; strips annotations only when stripMetadata is true)

    private func compressOptimize(
        document: PDFDocument,
        destination: URL,
        stripMetadata: Bool,
        progress: (Double) -> Void
    ) async throws {
        try Task.checkCancellation()
        guard let doc = document.copy() as? PDFDocument else {
            throw PDFwringerError.cannotOpenDocument
        }

        guard doc.pageCount > 0 else {
            throw PDFwringerError.cannotOpenDocument
        }

        doc.documentAttributes?.removeAll()

        if stripMetadata {
            for i in 0..<doc.pageCount {
                try Task.checkCancellation()
                guard let page = doc.page(at: i) else {
                    throw PDFwringerError.cannotOpenDocument
                }
                for annotation in page.annotations {
                    page.removeAnnotation(annotation)
                }
                guard page.annotations.isEmpty else {
                    throw PDFwringerError.cannotWriteOutput
                }
            }
        }

        guard let data = doc.dataRepresentation() else {
            throw PDFwringerError.cannotWriteOutput
        }
        guard !data.isEmpty, let serializedOutput = PDFDocument(data: data) else {
            throw PDFwringerError.cannotWriteOutput
        }
        if serializedOutput.isLocked {
            guard serializedOutput.isEncrypted else {
                throw PDFwringerError.cannotWriteOutput
            }
        } else {
            try Self.validateOutput(
                serializedOutput,
                expectedPageCount: document.pageCount,
                requireNoAnnotations: stripMetadata
            )
        }

        if let available = Formatting.availableDiskSpace(at: destination) {
            let needed = Int64(data.count)
            if needed > available {
                throw PDFwringerError.insufficientDiskSpace(needed: needed, available: available)
            }
        }

        try Task.checkCancellation()
        try AtomicFileWriter.write(to: destination) { tempURL in
            try data.write(to: tempURL)
            guard let output = PDFDocument(url: tempURL) else { return false }
            if output.isLocked { return output.isEncrypted }
            do {
                try Self.validateOutput(
                    output,
                    expectedPageCount: document.pageCount,
                    requireNoAnnotations: stripMetadata
                )
                return true
            } catch {
                return false
            }
        }

        progress(1.0)
    }

    // MARK: - Rasterize path (maximum compression, flattens content)

    private func compressRasterize(
        document: PDFDocument,
        source: URL,
        destination: URL,
        dpi: CGFloat,
        quality: CGFloat,
        grayscale: Bool,
        progress: (Double) -> Void
    ) async throws {
        let pageCount = document.pageCount
        guard pageCount > 0 else { throw PDFwringerError.cannotOpenDocument }
        guard pageCount <= 10_000 else {
            throw PDFwringerError.documentTooLarge("\(pageCount) pages exceeds the 10,000 page limit for rasterization")
        }

        // Estimate output size for disk space check (rough: source size * 0.5 as lower bound)
        if let available = Formatting.availableDiskSpace(at: destination) {
            let sourceSize = (try? FileManager.default.attributesOfItem(atPath: source.path(percentEncoded: false))[.size] as? Int64) ?? 0
            let estimatedNeeded = max(sourceSize / 2, Int64(pageCount) * 50_000)
            if estimatedNeeded > available {
                throw PDFwringerError.insufficientDiskSpace(needed: estimatedNeeded, available: available)
            }
        }

        let tempURL = AtomicFileWriter.tempDirectory.appending(component: UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var emptyBox = CGRect.zero
        guard let outputCtx = CGContext(tempURL as CFURL, mediaBox: &emptyBox, nil) else {
            throw PDFwringerError.cannotCreateOutput
        }

        var outputIsClosed = false
        do {

            for i in 0..<pageCount {
                try Task.checkCancellation()

                let pageData = try autoreleasepool { () throws -> Data in
                    guard let page = document.page(at: i) else {
                        throw PDFwringerError.cannotOpenDocument
                    }
                    guard let data = page.dataRepresentation else {
                        throw PDFwringerError.cannotOpenDocument
                    }
                    return data
                }

                let encodedPage = try await PDFPageWorker.run(pageData: pageData) { page in
                    guard let (rendered, displaySize) = Self.renderPage(
                        page,
                        dpi: dpi,
                        grayscale: grayscale
                    ) else {
                        throw PDFwringerError.cannotCreateOutput
                    }
                    guard let jpegData = Self.jpegEncode(image: rendered, quality: quality) else {
                        throw PDFwringerError.cannotWriteOutput
                    }
                    return PDFPageWorker.EncodedPage(data: jpegData, displaySize: displaySize)
                }

                try autoreleasepool {
                    guard let provider = CGDataProvider(data: encodedPage.data as CFData),
                          let jpegImage = CGImage(
                              jpegDataProviderSource: provider,
                              decode: nil,
                              shouldInterpolate: true,
                              intent: .defaultIntent
                          )
                    else {
                        throw PDFwringerError.cannotWriteOutput
                    }

                    var outBox = CGRect(origin: .zero, size: encodedPage.displaySize)
                    outputCtx.beginPage(mediaBox: &outBox)
                    outputCtx.draw(jpegImage, in: outBox)
                    outputCtx.endPage()
                }

                progress(Double(i + 1) / Double(pageCount))
            }

            try Task.checkCancellation()
            outputCtx.closePDF()
            outputIsClosed = true

            try Self.validateOutput(at: tempURL, expectedPageCount: pageCount)

            try AtomicFileWriter.write(to: destination) { destTemp in
                try FileManager.default.copyItem(at: tempURL, to: destTemp)
                return true
            }
        } catch {
            if !outputIsClosed {
                outputCtx.closePDF()
            }
            throw error
        }
    }

    // MARK: - Helpers

    /// Maximum file size allowed for in-memory PDF loading (500 MB).
    /// Prevents memory exhaustion from PDF bombs or extremely large scans.
    nonisolated private static let maxFileSize: Int = 500_000_000

    /// Opens a PDF by reading data into memory first — works reliably in sandbox
    /// where CGPDFDocument(url) may fail due to access restrictions.
    /// Rejects files larger than `maxFileSize` to prevent memory exhaustion.
    nonisolated static func openPDF(at url: URL) -> CGPDFDocument? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)),
              let fileSize = attrs[.size] as? Int,
              fileSize <= maxFileSize else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGPDFDocument(provider)
    }

    /// Swaps width/height for 90° or 270° rotated pages so rendering uses the correct dimensions.
    nonisolated private static func displaySize(for size: CGSize, rotation: Int32) -> CGSize {
        let angle = ((rotation % 360) + 360) % 360
        if angle == 90 || angle == 270 {
            return CGSize(width: size.height, height: size.width)
        }
        return size
    }

    /// Renders a PDF page to a CGImage at the given DPI, optionally in grayscale.
    /// For oversized pages (common in scanned PDFs where point dimensions match scanner
    /// pixels rather than physical page size), caps the output to A3 dimensions to avoid
    /// producing absurdly large bitmaps that defeat the purpose of compression.
    nonisolated static func renderPage(_ page: CGPDFPage, dpi: CGFloat, grayscale: Bool) -> (image: CGImage, displaySize: CGSize)? {
        let cropBox = page.getBoxRect(.cropBox)
        let rotation = page.rotationAngle
        let displaySize = Self.displaySize(for: cropBox.size, rotation: rotation)

        guard Self.canRender(displaySize: displaySize, dpi: dpi) else { return nil }

        let scale = dpi / 72.0
        var pixelW = max(1, Int(displaySize.width * scale))
        var pixelH = max(1, Int(displaySize.height * scale))

        // Cap output pixels: the target DPI should produce pixels as if the page were
        // at most A3 size (11.7 x 16.5 inches). Pages larger than this in points are
        // typically scanned PDFs with raw pixel dimensions as page size.
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

        let colorSpace: CGColorSpace
        let bitmapInfo: UInt32
        if grayscale {
            colorSpace = CGColorSpaceCreateDeviceGray()
            bitmapInfo = CGImageAlphaInfo.none.rawValue
        } else {
            colorSpace = sRGBColorSpace
            bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        }

        guard let bitmap = CGContext(
            data: nil, width: pixelW, height: pixelH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else { return nil }

        if grayscale {
            bitmap.setFillColor(gray: 1.0, alpha: 1.0)
        } else {
            bitmap.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        }
        bitmap.fill(CGRect(x: 0, y: 0, width: pixelW, height: pixelH))

        bitmap.scaleBy(x: effectiveScale, y: effectiveScale)
        let drawRect = CGRect(origin: .zero, size: displaySize)
        let transform = page.getDrawingTransform(.cropBox, rect: drawRect, rotate: 0, preserveAspectRatio: true)
        bitmap.concatenate(transform)
        bitmap.drawPDFPage(page)

        guard let rendered = bitmap.makeImage() else { return nil }
        return (rendered, displaySize)
    }

    /// Renders a page from an already-open PDFKit document. This is the document-
    /// authoritative path used after a caller has unlocked a protected PDF.
    nonisolated static func renderPage(_ page: PDFPage, dpi: CGFloat, grayscale: Bool) -> (image: CGImage, displaySize: CGSize)? {
        let cropBox = page.bounds(for: .cropBox)
        let rotation = page.rotation
        let angle = ((rotation % 360) + 360) % 360
        let displaySize: CGSize
        if angle == 90 || angle == 270 {
            displaySize = CGSize(width: cropBox.height, height: cropBox.width)
        } else {
            displaySize = cropBox.size
        }

        guard Self.canRender(displaySize: displaySize, dpi: dpi) else { return nil }

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

        let colorSpace: CGColorSpace
        let bitmapInfo: UInt32
        if grayscale {
            colorSpace = CGColorSpaceCreateDeviceGray()
            bitmapInfo = CGImageAlphaInfo.none.rawValue
        } else {
            colorSpace = sRGBColorSpace
            bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        }

        guard let bitmap = CGContext(
            data: nil, width: pixelW, height: pixelH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else { return nil }

        if grayscale {
            bitmap.setFillColor(gray: 1.0, alpha: 1.0)
        } else {
            bitmap.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        }
        bitmap.fill(CGRect(x: 0, y: 0, width: pixelW, height: pixelH))

        bitmap.scaleBy(x: effectiveScale, y: effectiveScale)
        page.transform(bitmap, for: .cropBox)
        page.draw(with: .cropBox, to: bitmap)

        guard let rendered = bitmap.makeImage() else { return nil }
        return (rendered, displaySize)
    }

    nonisolated static func jpegEncode(image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(dest, image, options as CFDictionary)

        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    nonisolated private static func canRender(displaySize: CGSize, dpi: CGFloat) -> Bool {
        guard displaySize.width.isFinite,
              displaySize.height.isFinite,
              displaySize.width > 0,
              displaySize.height > 0,
              dpi.isFinite,
              dpi > 0 else { return false }

        let scale = dpi / 72.0
        let pixelWidth = displaySize.width * scale
        let pixelHeight = displaySize.height * scale
        let maxLongPixels = 16.5 * dpi
        let maxShortPixels = 11.7 * dpi
        return pixelWidth.isFinite
            && pixelHeight.isFinite
            && pixelWidth < CGFloat(Int.max)
            && pixelHeight < CGFloat(Int.max)
            && maxLongPixels.isFinite
            && maxShortPixels.isFinite
            && maxLongPixels > 0
            && maxShortPixels > 0
            && maxLongPixels < CGFloat(Int.max)
            && maxShortPixels < CGFloat(Int.max)
    }

    private static func validateOutput(
        data: Data,
        expectedPageCount: Int,
        requireNoAnnotations: Bool = false
    ) throws {
        guard let output = PDFDocument(data: data) else {
            throw PDFwringerError.cannotWriteOutput
        }
        try validateOutput(
            output,
            expectedPageCount: expectedPageCount,
            requireNoAnnotations: requireNoAnnotations
        )
    }

    private static func validateOutput(
        at url: URL,
        expectedPageCount: Int,
        requireNoAnnotations: Bool = false
    ) throws {
        guard let output = PDFDocument(url: url) else {
            throw PDFwringerError.cannotWriteOutput
        }
        try validateOutput(
            output,
            expectedPageCount: expectedPageCount,
            requireNoAnnotations: requireNoAnnotations
        )
    }

    private static func validateOutput(
        _ output: PDFDocument,
        expectedPageCount: Int,
        requireNoAnnotations: Bool
    ) throws {
        guard output.pageCount == expectedPageCount else {
            throw PDFwringerError.cannotWriteOutput
        }
        for index in 0..<expectedPageCount {
            guard let page = output.page(at: index) else {
                throw PDFwringerError.cannotWriteOutput
            }
            if requireNoAnnotations, !page.annotations.isEmpty {
                throw PDFwringerError.cannotWriteOutput
            }
        }
    }
}
