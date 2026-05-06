import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Handles PDF compression via two strategies: lossless optimization (re-serialize with metadata stripped)
/// or lossy rasterization (render pages as JPEG at a target DPI).
@MainActor
struct PDFCompressor {

    nonisolated private static let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Compresses a PDF from `source` to `destination` using the selected strategy.
    func compress(
        source: URL,
        destination: URL,
        level: CompressionLevel,
        quality: JPEGQuality,
        grayscale: Bool,
        stripMetadata: Bool,
        progress: (Double) -> Void
    ) async throws {
        if level.isRasterize {
            try await compressRasterize(
                source: source,
                destination: destination,
                dpi: level.dpi,
                quality: quality.value,
                grayscale: grayscale,
                progress: progress
            )
        } else {
            try await compressOptimize(
                source: source,
                destination: destination,
                stripMetadata: stripMetadata,
                progress: progress
            )
        }
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
        source: URL,
        destination: URL,
        stripMetadata: Bool,
        progress: (Double) -> Void
    ) async throws {
        guard FileManager.default.isReadableFile(atPath: source.path(percentEncoded: false)) else {
            throw PDFwringerError.fileNotReadable(source.lastPathComponent)
        }

        guard let doc = PDFDocument(url: source) else {
            throw PDFwringerError.cannotOpenDocument
        }

        if doc.isLocked {
            throw PDFwringerError.documentIsLocked
        }

        guard doc.pageCount > 0 else {
            throw PDFwringerError.cannotOpenDocument
        }

        doc.documentAttributes?.removeAll()

        if stripMetadata {
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i) else { continue }
                for annotation in page.annotations {
                    page.removeAnnotation(annotation)
                }
            }
        }

        guard let data = doc.dataRepresentation() else {
            throw PDFwringerError.cannotWriteOutput
        }

        if let available = Formatting.availableDiskSpace(at: destination) {
            let needed = Int64(data.count)
            if needed > available {
                throw PDFwringerError.insufficientDiskSpace(needed: needed, available: available)
            }
        }

        try AtomicFileWriter.write(to: destination) { tempURL in
            try data.write(to: tempURL)
            return true
        }

        progress(1.0)
    }

    // MARK: - Rasterize path (maximum compression, flattens content)

    private func compressRasterize(
        source: URL,
        destination: URL,
        dpi: CGFloat,
        quality: CGFloat,
        grayscale: Bool,
        progress: (Double) -> Void
    ) async throws {
        guard FileManager.default.isReadableFile(atPath: source.path(percentEncoded: false)) else {
            throw PDFwringerError.fileNotReadable(source.lastPathComponent)
        }

        guard let doc = Self.openPDF(at: source) else {
            throw PDFwringerError.cannotOpenDocument
        }

        let pageCount = doc.numberOfPages
        guard pageCount > 0 else { throw PDFwringerError.cannotOpenDocument }

        // Estimate output size for disk space check (rough: source size * 0.5 as lower bound)
        if let available = Formatting.availableDiskSpace(at: destination) {
            let sourceSize = (try? FileManager.default.attributesOfItem(atPath: source.path(percentEncoded: false))[.size] as? Int64) ?? 0
            let estimatedNeeded = max(sourceSize / 2, Int64(pageCount) * 50_000)
            if estimatedNeeded > available {
                throw PDFwringerError.insufficientDiskSpace(needed: estimatedNeeded, available: available)
            }
        }

        let tempURL = URL.temporaryDirectory.appending(component: UUID().uuidString + ".pdf")

        var emptyBox = CGRect.zero
        guard let outputCtx = CGContext(tempURL as CFURL, mediaBox: &emptyBox, nil) else {
            throw PDFwringerError.cannotCreateOutput
        }

        do {
            for i in 1...pageCount {
                try Task.checkCancellation()

                autoreleasepool {
                    guard let page = doc.page(at: i) else { return }
                    guard let (rendered, displaySize) = Self.renderPage(page, dpi: dpi, grayscale: grayscale) else { return }
                    guard let jpegData = Self.jpegEncode(image: rendered, quality: quality) else { return }

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

                progress(Double(i) / Double(pageCount))
                await Task.yield()
            }

            outputCtx.closePDF()
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: tempURL)
        } catch {
            outputCtx.closePDF()
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }

    // MARK: - Helpers

    /// Opens a PDF by reading data into memory first — works reliably in sandbox
    /// where CGPDFDocument(url) may fail due to access restrictions.
    nonisolated static func openPDF(at url: URL) -> CGPDFDocument? {
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
    nonisolated static func renderPage(_ page: CGPDFPage, dpi: CGFloat, grayscale: Bool) -> (image: CGImage, displaySize: CGSize)? {
        let cropBox = page.getBoxRect(.cropBox)
        let rotation = page.rotationAngle
        let displaySize = Self.displaySize(for: cropBox.size, rotation: rotation)

        let scale = dpi / 72.0
        let pixelW = max(1, Int(displaySize.width * scale))
        let pixelH = max(1, Int(displaySize.height * scale))

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

        bitmap.scaleBy(x: scale, y: scale)
        let drawRect = CGRect(origin: .zero, size: displaySize)
        let transform = page.getDrawingTransform(.cropBox, rect: drawRect, rotate: 0, preserveAspectRatio: true)
        bitmap.concatenate(transform)
        bitmap.drawPDFPage(page)

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
}
