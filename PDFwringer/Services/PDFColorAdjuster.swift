import AppKit
import CoreGraphics
import CoreImage
import Foundation
import PDFKit

@MainActor
struct PDFColorAdjuster {

    struct Settings: Equatable, Hashable {
        var brightness: Float = 0
        var contrast: Float = 1
        var saturation: Float = 1

        var isIdentity: Bool {
            brightness == 0 && contrast == 1 && saturation == 1
        }
    }

    private nonisolated static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    nonisolated static func adjustImage(_ image: CGImage, settings: Settings) -> CGImage? {
        guard !settings.isIdentity else { return image }

        let ciImage = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIColorControls") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(settings.brightness, forKey: kCIInputBrightnessKey)
        filter.setValue(settings.contrast, forKey: kCIInputContrastKey)
        filter.setValue(settings.saturation, forKey: kCIInputSaturationKey)

        guard let output = filter.outputImage else { return nil }

        guard let cgResult = ciContext.createCGImage(output, from: output.extent) else { return nil }
        return cgResult
    }

    func adjust(
        source: URL,
        destination: URL,
        settings: Settings,
        pages: [Int]?,
        dpi: CGFloat = 150,
        quality: CGFloat = 0.85,
        progress: (Double) -> Void
    ) async throws {
        guard FileManager.default.isReadableFile(atPath: source.path(percentEncoded: false)) else {
            throw PDFwringerError.fileNotReadable(source.lastPathComponent)
        }
        guard let document = PDFDocument(url: source) else {
            throw PDFwringerError.cannotOpenDocument
        }
        if document.isLocked { throw PDFwringerError.documentIsLocked }

        try await adjust(
            document: document,
            source: source,
            destination: destination,
            settings: settings,
            pages: pages,
            dpi: dpi,
            quality: quality,
            progress: progress
        )
    }

    /// Applies color settings to an already-open document, including one the caller unlocked.
    func adjust(
        document: PDFDocument,
        source: URL,
        destination: URL,
        settings: Settings,
        pages: [Int]?,
        dpi: CGFloat = 150,
        quality: CGFloat = 0.85,
        progress: (Double) -> Void
    ) async throws {
        let start = ContinuousClock.now
        Log.colorAdjust.info("Starting color adjust: brightness=\(settings.brightness), contrast=\(settings.contrast), saturation=\(settings.saturation)")

        guard source.standardizedFileURL != destination.standardizedFileURL else {
            throw PDFwringerError.sourceEqualsDestination
        }
        if document.isLocked { throw PDFwringerError.documentIsLocked }

        let pageCount = document.pageCount
        guard pageCount > 0 else { throw PDFwringerError.cannotOpenDocument }

        let targetPages: Set<Int>
        if let pages {
            guard !pages.isEmpty, pages.allSatisfy({ (0..<pageCount).contains($0) }) else {
                let range = pages.map { String($0 + 1) }.joined(separator: ", ")
                throw PDFwringerError.invalidPageRange(range)
            }
            targetPages = Set(pages)
        } else {
            targetPages = Set(0..<pageCount)
        }

        try Task.checkCancellation()
        guard !settings.isIdentity else {
            try AtomicFileWriter.write(to: destination) { tempURL in
                try FileManager.default.copyItem(at: source, to: tempURL)
                guard let verificationDocument = PDFDocument(url: tempURL) else { return false }
                if document.isEncrypted {
                    return verificationDocument.isEncrypted
                }
                return !verificationDocument.isLocked
                    && verificationDocument.pageCount == pageCount
            }
            progress(1.0)
            Log.colorAdjust.info("Identity settings — copied source unchanged")
            return
        }

        let outputDocument = PDFDocument()
        outputDocument.documentAttributes = document.documentAttributes

        for i in 0..<pageCount {
            try Task.checkCancellation()

            let outputPage = try autoreleasepool { () throws -> PDFPage in
                guard let page = document.page(at: i) else {
                    throw PDFwringerError.cannotWriteOutput
                }

                guard targetPages.contains(i) else {
                    guard let copiedPage = page.copy() as? PDFPage else {
                        throw PDFwringerError.cannotWriteOutput
                    }
                    return copiedPage
                }

                guard let (rendered, displaySize) = PDFCompressor.renderPage(
                    page,
                    dpi: dpi,
                    grayscale: false
                ), let adjusted = Self.adjustImage(rendered, settings: settings),
                   let jpegData = PDFCompressor.jpegEncode(image: adjusted, quality: quality),
                   let image = NSImage(data: jpegData)
                else {
                    throw PDFwringerError.cannotWriteOutput
                }

                image.size = displaySize
                guard let rasterizedPage = PDFPage(image: image) else {
                    throw PDFwringerError.cannotWriteOutput
                }

                let outputBounds = CGRect(origin: .zero, size: displaySize)
                rasterizedPage.setBounds(outputBounds, for: .mediaBox)
                rasterizedPage.setBounds(outputBounds, for: .cropBox)
                return rasterizedPage
            }
            outputDocument.insert(outputPage, at: outputDocument.pageCount)

            progress(Double(i + 1) / Double(pageCount))
            await Task.yield()
        }

        try Task.checkCancellation()

        try AtomicFileWriter.write(to: destination) { tempDest in
            guard outputDocument.write(to: tempDest),
                  let verificationDocument = PDFDocument(url: tempDest),
                  !verificationDocument.isLocked,
                  verificationDocument.pageCount == pageCount else {
                return false
            }
            return (0..<pageCount).allSatisfy { verificationDocument.page(at: $0) != nil }
        }
        let elapsed = ContinuousClock.now - start
        Log.colorAdjust.info("Color adjust complete: \(pageCount) pages, duration=\(elapsed)")
    }
}
