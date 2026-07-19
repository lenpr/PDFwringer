import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

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
            targetPages = Set(pages.map { $0 + 1 })
        } else {
            targetPages = Set(1...pageCount)
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

        let tempURL = AtomicFileWriter.tempDirectory.appending(component: UUID().uuidString + ".pdf")

        var emptyBox = CGRect.zero
        guard let outputCtx = CGContext(tempURL as CFURL, mediaBox: &emptyBox, nil) else {
            throw PDFwringerError.cannotCreateOutput
        }

        var didCloseOutput = false
        defer {
            if !didCloseOutput { outputCtx.closePDF() }
            try? FileManager.default.removeItem(at: tempURL)
        }

        for i in 0..<pageCount {
            try Task.checkCancellation()

            try autoreleasepool {
                guard let page = document.page(at: i),
                      let (rendered, displaySize) = PDFCompressor.renderPage(page, dpi: dpi, grayscale: false)
                else {
                    throw PDFwringerError.cannotWriteOutput
                }

                let finalImage: CGImage
                if targetPages.contains(i + 1) {
                    guard let adjusted = Self.adjustImage(rendered, settings: settings) else {
                        throw PDFwringerError.cannotWriteOutput
                    }
                    finalImage = adjusted
                } else {
                    finalImage = rendered
                }

                guard let jpegData = PDFCompressor.jpegEncode(image: finalImage, quality: quality) else {
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

            progress(Double(i + 1) / Double(pageCount))
            await Task.yield()
        }

        try Task.checkCancellation()
        outputCtx.closePDF()
        didCloseOutput = true

        guard let outputDocument = PDFDocument(url: tempURL),
              outputDocument.pageCount == pageCount else {
            throw PDFwringerError.cannotWriteOutput
        }

        try AtomicFileWriter.write(to: destination) { tempDest in
            try FileManager.default.copyItem(at: tempURL, to: tempDest)
            guard let verificationDocument = PDFDocument(url: tempDest) else { return false }
            return verificationDocument.pageCount == pageCount
        }
        let elapsed = ContinuousClock.now - start
        Log.colorAdjust.info("Color adjust complete: \(pageCount) pages, duration=\(elapsed)")
    }
}
