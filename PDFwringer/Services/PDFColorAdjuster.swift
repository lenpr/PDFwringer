import AppKit
import CoreGraphics
import CoreImage
import Foundation
import PDFKit

@MainActor
struct PDFColorAdjuster {

    struct Settings: Equatable, Hashable, Sendable {
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

        try FileSystemIdentity.requireDistinct(source, destination)
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
            guard let data = document.dataRepresentation(), !data.isEmpty else {
                throw PDFwringerError.cannotWriteOutput
            }
            progress(1.0)
            try Task.checkCancellation()
            try AtomicFileWriter.write(to: destination) { tempURL in
                try data.write(to: tempURL)
                guard let verificationDocument = PDFDocument(url: tempURL) else { return false }
                if document.isEncrypted {
                    guard verificationDocument.isEncrypted else { return false }
                    if verificationDocument.isLocked { return true }
                    return verificationDocument.pageCount == pageCount
                        && verificationDocument.accessPermissions == document.accessPermissions
                }
                return !verificationDocument.isLocked
                    && verificationDocument.pageCount == pageCount
            }
            Log.colorAdjust.info("Identity settings — serialized authoritative document unchanged")
            return
        }

        try PDFPermissionPolicy.require(.copyContent, .changeDocument, for: document)
        let outputDocument = PDFDocument()
        outputDocument.documentAttributes = document.documentAttributes

        for i in 0..<pageCount {
            try Task.checkCancellation()

            guard let page = document.page(at: i) else {
                throw PDFwringerError.cannotWriteOutput
            }

            let outputPage: PDFPage
            if targetPages.contains(i) {
                guard let pageData = page.dataRepresentation else {
                    throw PDFwringerError.cannotWriteOutput
                }
                let encodedPage = try await PDFPageWorker.run(pageData: pageData) { isolatedPage in
                    guard let (rendered, displaySize) = PDFRasterizer.render(
                        isolatedPage,
                        dpi: dpi,
                        grayscale: false
                    ), let adjusted = Self.adjustImage(rendered, settings: settings),
                       let jpegData = PDFRasterizer.jpegData(for: adjusted, quality: quality)
                    else {
                        throw PDFwringerError.cannotWriteOutput
                    }
                    return PDFRasterizer.JPEGPage(data: jpegData, displaySize: displaySize)
                }

                outputPage = try autoreleasepool {
                    guard let image = NSImage(data: encodedPage.data) else {
                        throw PDFwringerError.cannotWriteOutput
                    }
                    image.size = encodedPage.displaySize
                    guard let rasterizedPage = PDFPage(image: image) else {
                        throw PDFwringerError.cannotWriteOutput
                    }

                    let outputBounds = CGRect(origin: .zero, size: encodedPage.displaySize)
                    rasterizedPage.setBounds(outputBounds, for: .mediaBox)
                    rasterizedPage.setBounds(outputBounds, for: .cropBox)
                    return rasterizedPage
                }
            } else {
                guard let copiedPage = page.copy() as? PDFPage else {
                    throw PDFwringerError.cannotWriteOutput
                }
                outputPage = copiedPage
            }
            outputDocument.insert(outputPage, at: outputDocument.pageCount)

            progress(Double(i + 1) / Double(pageCount))
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
