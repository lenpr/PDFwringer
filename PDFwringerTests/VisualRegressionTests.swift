import Testing
import PDFKit
import Foundation
import CoreGraphics

/// Visual regression tests: render a page before and after an operation,
/// compare pixel data to detect silent rasterization or rendering changes.
/// Only runs on a small representative set to keep test time reasonable.

@Suite("Visual Regression")
@MainActor
struct VisualRegressionTests {

    /// Renders a PDF page to raw RGBA pixel data for comparison.
    private func renderPage(from url: URL, pageIndex: Int = 0, dpi: CGFloat = 72) -> (data: [UInt8], width: Int, height: Int)? {
        guard let doc = CGPDFDocument(url as CFURL),
              let page = doc.page(at: pageIndex + 1) else { return nil }

        let cropBox = page.getBoxRect(.cropBox)
        let scale = dpi / 72.0
        let width = max(1, Int(cropBox.width * scale))
        let height = max(1, Int(cropBox.height * scale))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        var pixelData = [UInt8](repeating: 255, count: bytesPerRow * height)

        guard let ctx = CGContext(
            data: &pixelData, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)

        let transform = page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: cropBox.size), rotate: 0, preserveAspectRatio: true)
        ctx.concatenate(transform)
        ctx.drawPDFPage(page)

        return (pixelData, width, height)
    }

    /// Computes fraction of pixels that differ significantly (0.0 = identical, 1.0 = completely different).
    private func pixelDifference(before: [UInt8], after: [UInt8], width: Int, height: Int) -> Double {
        guard before.count == after.count, !before.isEmpty else { return 1.0 }

        let totalPixels = width * height
        var diffCount = 0

        for i in stride(from: 0, to: min(before.count, after.count), by: 4) {
            let dr = abs(Int(before[i]) - Int(after[i]))
            let dg = abs(Int(before[i+1]) - Int(after[i+1]))
            let db = abs(Int(before[i+2]) - Int(after[i+2]))
            if dr + dg + db > 30 {
                diffCount += 1
            }
        }

        return Double(diffCount) / Double(max(1, totalPixels))
    }

    @Test("Lossless compression does not visually alter page 1")
    func losslessVisualIdentity() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 3, filename: "visual_lossless.pdf")
        let output = URL.temporaryDirectory.appending(component: "visual_lossless_out_\(UUID()).pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            try? FileManager.default.removeItem(at: output)
        }

        guard let before = renderPage(from: source) else { return }

        let compressor = PDFCompressor()
        try await compressor.compress(
            source: source, destination: output,
            level: .lossless, quality: .good, grayscale: false, stripMetadata: false,
            progress: { _ in }
        )

        guard let after = renderPage(from: output) else {
            Issue.record("Cannot render output page")
            return
        }

        let diff = pixelDifference(before: before.data, after: after.data, width: before.width, height: before.height)
        #expect(diff < 0.01, "Lossless compression should not visually alter pages (diff: \(String(format: "%.2f%%", diff * 100)))")
    }

    @Test("Metadata write does not visually alter page 1")
    func metadataVisualIdentity() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2, filename: "visual_meta.pdf")
        let output = URL.temporaryDirectory.appending(component: "visual_meta_out_\(UUID()).pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            try? FileManager.default.removeItem(at: output)
        }

        guard let before = renderPage(from: source) else { return }

        let editor = PDFMetadataEditor()
        try await editor.write(
            metadata: .init(title: "Visual", author: "Test", subject: "", keywords: "", creator: ""),
            source: source, destination: output
        )

        guard let after = renderPage(from: output) else {
            Issue.record("Cannot render output page")
            return
        }

        let diff = pixelDifference(before: before.data, after: after.data, width: before.width, height: before.height)
        #expect(diff < 0.01, "Metadata write should not visually alter pages (diff: \(String(format: "%.2f%%", diff * 100)))")
    }

    @Test("Rotate 4×90° visually matches original")
    func rotateFullCircleVisual() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "visual_rotate.pdf")
        defer { TestPDFGenerator.cleanup(source) }

        guard let before = renderPage(from: source) else { return }

        var current = source
        var temps: [URL] = []
        for i in 1...4 {
            let out = URL.temporaryDirectory.appending(component: "visual_rot\(i)_\(UUID()).pdf")
            temps.append(out)
            let rotator = PDFRotator()
            try await rotator.rotate(source: current, destination: out, angle: .ninety, pageIndices: nil, progress: { _ in })
            current = out
        }
        defer { temps.forEach { try? FileManager.default.removeItem(at: $0) } }

        guard let after = renderPage(from: current) else {
            Issue.record("Cannot render 4× rotated page")
            return
        }

        let diff = pixelDifference(before: before.data, after: after.data, width: before.width, height: before.height)
        #expect(diff < 0.01, "4×90° rotation should visually match original (diff: \(String(format: "%.2f%%", diff * 100)))")
    }

    @Test("Color identity adjustment does not visually alter output")
    func colorIdentityVisual() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "visual_color.pdf")
        let output = URL.temporaryDirectory.appending(component: "visual_color_out_\(UUID()).pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            try? FileManager.default.removeItem(at: output)
        }

        guard let before = renderPage(from: source) else { return }

        let adjuster = PDFColorAdjuster()
        try await adjuster.adjust(
            source: source, destination: output,
            settings: .init(brightness: 0, contrast: 1, saturation: 1),
            pages: nil, progress: { _ in }
        )

        guard let after = renderPage(from: output) else {
            Issue.record("Cannot render identity output")
            return
        }

        let diff = pixelDifference(before: before.data, after: after.data, width: before.width, height: before.height)
        #expect(diff < 0.01, "Identity color adjustment should not visually alter pages (diff: \(String(format: "%.2f%%", diff * 100)))")
    }
}
