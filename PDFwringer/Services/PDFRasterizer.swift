import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Shared page rendering and image encoding used by PDF raster workflows.
@MainActor
enum PDFRasterizer {
    struct JPEGPage: Sendable {
        let data: Data
        let displaySize: CGSize
    }

    struct PixelDimensions: Equatable, Sendable {
        let width: Int
        let height: Int
    }

    /// Maximum file size allowed for in-memory Core Graphics PDF loading.
    nonisolated private static let maxFileSize = 500_000_000
    nonisolated private static let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Opens a PDF through an in-memory data provider, which works reliably for
    /// sandbox-scoped files. Large files are rejected before allocating their data.
    nonisolated static func openDocument(at url: URL) -> CGPDFDocument? {
        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: url.path(percentEncoded: false)
        ), let fileSize = attributes[.size] as? Int,
           fileSize <= maxFileSize,
           let data = try? Data(contentsOf: url),
           let provider = CGDataProvider(data: data as CFData) else {
            return nil
        }
        return CGPDFDocument(provider)
    }

    /// Renders a Core Graphics page. Used by compression size estimation.
    nonisolated static func render(
        _ page: CGPDFPage,
        dpi: CGFloat,
        grayscale: Bool
    ) -> (image: CGImage, displaySize: CGSize)? {
        let cropBox = page.getBoxRect(.cropBox)
        let displaySize = rotatedDisplaySize(
            cropBox.size,
            rotation: Int(page.rotationAngle)
        )
        return renderCanvas(displaySize: displaySize, dpi: dpi, grayscale: grayscale) {
            context, drawRect in
            let transform = page.getDrawingTransform(
                .cropBox,
                rect: drawRect,
                rotate: 0,
                preserveAspectRatio: true
            )
            context.concatenate(transform)
            context.drawPDFPage(page)
        }
    }

    /// Renders a PDFKit page reconstructed inside a page worker. PDFKit drawing
    /// includes annotation appearances, which is required for flattening workflows.
    nonisolated static func render(
        _ page: PDFPage,
        dpi: CGFloat,
        grayscale: Bool
    ) -> (image: CGImage, displaySize: CGSize)? {
        let cropBox = page.bounds(for: .cropBox)
        let displaySize = rotatedDisplaySize(cropBox.size, rotation: page.rotation)
        return renderCanvas(displaySize: displaySize, dpi: dpi, grayscale: grayscale) {
            context, _ in
            page.draw(with: .cropBox, to: context)
        }
    }

    nonisolated static func jpegData(for image: CGImage, quality: CGFloat) -> Data? {
        guard quality.isFinite, (0...1).contains(quality) else { return nil }
        let properties = [
            kCGImageDestinationLossyCompressionQuality: quality
        ] as CFDictionary
        return encode(image, as: .jpeg, properties: properties)
    }

    nonisolated static func pngData(for image: CGImage) -> Data? {
        encode(image, as: .png, properties: nil)
    }

    /// Conservatively estimates encoded output from the exact capped bitmap
    /// dimensions used by rendering. The per-page allowance includes container
    /// and compression overhead in addition to the caller's pixel budget.
    static func estimatedEncodedOutputBytes(
        document: PDFDocument,
        pageIndices: [Int],
        dpi: CGFloat,
        bytesPerPixel: Int
    ) async throws -> Int64 {
        var total: Int64 = 0
        for (offset, pageIndex) in pageIndices.enumerated() {
            try Task.checkCancellation()
            guard let page = document.page(at: pageIndex),
                  let pageEstimate = estimatedEncodedSizeUpperBound(
                    displaySize: rotatedDisplaySize(
                        page.bounds(for: .cropBox).size,
                        rotation: page.rotation
                    ),
                    dpi: dpi,
                    bytesPerPixel: bytesPerPixel
                  ) else {
                throw PDFwringerError.cannotCreateOutput
            }
            let (newTotal, overflow) = total.addingReportingOverflow(pageEstimate)
            guard !overflow else {
                throw PDFwringerError.documentTooLarge("Raster output size estimate overflowed")
            }
            total = newTotal

            if (offset + 1).isMultiple(of: 100) {
                await Task.yield()
            }
        }
        return total
    }

    nonisolated static func estimatedEncodedSizeUpperBound(
        displaySize: CGSize,
        dpi: CGFloat,
        bytesPerPixel: Int
    ) -> Int64? {
        guard bytesPerPixel > 0,
              let dimensions = pixelDimensions(displaySize: displaySize, dpi: dpi) else {
            return nil
        }
        let (pixels, pixelOverflow) = Int64(dimensions.width)
            .multipliedReportingOverflow(by: Int64(dimensions.height))
        guard !pixelOverflow else { return nil }
        let (pixelBytes, byteOverflow) = pixels
            .multipliedReportingOverflow(by: Int64(bytesPerPixel))
        guard !byteOverflow else { return nil }
        let (total, totalOverflow) = pixelBytes.addingReportingOverflow(65_536)
        return totalOverflow ? nil : total
    }

    nonisolated static func pixelDimensions(
        displaySize: CGSize,
        dpi: CGFloat
    ) -> PixelDimensions? {
        rasterPlan(displaySize: displaySize, dpi: dpi)?.dimensions
    }

    /// Appends an encoded JPEG page to an open PDF context.
    nonisolated static func append(_ page: JPEGPage, to context: CGContext) throws {
        guard let provider = CGDataProvider(data: page.data as CFData),
              let image = CGImage(
                  jpegDataProviderSource: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              ) else {
            throw PDFwringerError.cannotWriteOutput
        }

        var bounds = CGRect(origin: .zero, size: page.displaySize)
        context.beginPage(mediaBox: &bounds)
        context.draw(image, in: bounds)
        context.endPage()
    }

    nonisolated private static func renderCanvas(
        displaySize: CGSize,
        dpi: CGFloat,
        grayscale: Bool,
        draw: (CGContext, CGRect) -> Void
    ) -> (image: CGImage, displaySize: CGSize)? {
        guard let plan = rasterPlan(displaySize: displaySize, dpi: dpi) else { return nil }

        let colorSpace = grayscale ? CGColorSpaceCreateDeviceGray() : sRGBColorSpace
        let bitmapInfo = grayscale
            ? CGImageAlphaInfo.none.rawValue
            : CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: plan.dimensions.width,
            height: plan.dimensions.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        if grayscale {
            context.setFillColor(gray: 1, alpha: 1)
        } else {
            context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        }
        context.fill(CGRect(
            x: 0,
            y: 0,
            width: plan.dimensions.width,
            height: plan.dimensions.height
        ))
        context.scaleBy(x: plan.effectiveScale, y: plan.effectiveScale)
        draw(context, CGRect(origin: .zero, size: displaySize))

        guard let image = context.makeImage() else { return nil }
        return (image, displaySize)
    }

    nonisolated static func rotatedDisplaySize(
        _ size: CGSize,
        rotation: Int
    ) -> CGSize {
        let normalizedRotation = ((rotation % 360) + 360) % 360
        if normalizedRotation == 90 || normalizedRotation == 270 {
            return CGSize(width: size.height, height: size.width)
        }
        return size
    }

    nonisolated private static func canRender(displaySize: CGSize, dpi: CGFloat) -> Bool {
        guard displaySize.width.isFinite,
              displaySize.height.isFinite,
              displaySize.width > 0,
              displaySize.height > 0,
              dpi.isFinite,
              dpi > 0 else {
            return false
        }

        let scale = dpi / 72
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

    nonisolated private static func rasterPlan(
        displaySize: CGSize,
        dpi: CGFloat
    ) -> (dimensions: PixelDimensions, effectiveScale: CGFloat)? {
        guard canRender(displaySize: displaySize, dpi: dpi) else { return nil }

        let scale = dpi / 72
        var pixelWidth = max(1, Int(displaySize.width * scale))
        var pixelHeight = max(1, Int(displaySize.height * scale))

        // Pages larger than A3 are usually scans whose pixel dimensions were used
        // as points. Cap them to prevent unexpectedly huge bitmap allocations.
        let maxLong = max(1, Int(16.5 * dpi))
        let maxShort = max(1, Int(11.7 * dpi))
        let longSide = max(pixelWidth, pixelHeight)
        let shortSide = min(pixelWidth, pixelHeight)
        var effectiveScale = scale
        if longSide > maxLong || shortSide > maxShort {
            let downscale = min(
                Double(maxLong) / Double(longSide),
                Double(maxShort) / Double(shortSide)
            )
            pixelWidth = max(1, Int(Double(pixelWidth) * downscale))
            pixelHeight = max(1, Int(Double(pixelHeight) * downscale))
            effectiveScale *= downscale
        }

        return (
            PixelDimensions(width: pixelWidth, height: pixelHeight),
            effectiveScale
        )
    }

    nonisolated private static func encode(
        _ image: CGImage,
        as type: UTType,
        properties: CFDictionary?
    ) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            type.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
