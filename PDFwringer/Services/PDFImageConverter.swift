import AppKit
import CoreGraphics
import Foundation
import PDFKit

/// Converts image files (JPEG, PNG, TIFF, HEIC) into a PDF document.
@MainActor
struct PDFImageConverter {

    /// Converts a set of image URLs into a single PDF at the destination.
    /// Each image becomes one page, sized to the image's natural dimensions at 72 DPI.
    func convert(
        images: [URL],
        destination: URL,
        progress: (Double) -> Void
    ) async throws {
        guard !images.isEmpty else { throw PDFwringerError.emptyFileList }

        let start = ContinuousClock.now
        Log.app.info("Converting \(images.count) images to PDF")

        let tempURL = AtomicFileWriter.tempDirectory.appending(component: UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var firstPageBox = CGRect.zero
        guard let ctx = CGContext(tempURL as CFURL, mediaBox: &firstPageBox, nil) else {
            throw PDFwringerError.cannotCreateOutput
        }
        var contextIsClosed = false
        defer {
            if !contextIsClosed {
                ctx.closePDF()
            }
        }

        var pagesWritten = 0

        for (i, imageURL) in images.enumerated() {
            try Task.checkCancellation()

            try autoreleasepool {
                guard let image = loadImage(from: imageURL) else {
                    throw PDFwringerError.fileNotReadable(imageURL.lastPathComponent)
                }

                let width = CGFloat(image.width)
                let height = CGFloat(image.height)

                // Scale to reasonable page size: cap at 72 DPI equivalent of the pixel dimensions
                // (i.e., 1 pixel = 1 point). Cap at A3 to prevent absurd page sizes from phone photos.
                let maxDim: CGFloat = 1190 // ~A3 long side in points
                let scale: CGFloat
                if max(width, height) > maxDim {
                    scale = maxDim / max(width, height)
                } else {
                    scale = 1.0
                }

                let pageWidth = width * scale
                let pageHeight = height * scale

                var pageBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
                ctx.beginPage(mediaBox: &pageBox)
                ctx.draw(image, in: pageBox)
                ctx.endPage()
                pagesWritten += 1
            }

            progress(Double(i + 1) / Double(images.count))
            await Task.yield()
        }

        try Task.checkCancellation()
        ctx.closePDF()
        contextIsClosed = true

        guard pagesWritten == images.count else {
            throw PDFwringerError.cannotWriteOutput
        }
        guard let outputDocument = PDFDocument(url: tempURL),
              outputDocument.pageCount == images.count else {
            throw PDFwringerError.cannotWriteOutput
        }

        try AtomicFileWriter.write(to: destination) { destTemp in
            try FileManager.default.copyItem(at: tempURL, to: destTemp)
            guard let verificationDocument = PDFDocument(url: destTemp) else { return false }
            return verificationDocument.pageCount == images.count
        }

        let elapsed = ContinuousClock.now - start
        Log.app.info("Image to PDF complete: \(pagesWritten) pages, duration=\(elapsed)")
    }

    /// Checks whether a URL is a supported image format.
    static func isImageFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "tiff", "tif", "heic", "heif", "bmp", "gif", "webp"].contains(ext)
    }

    /// Filters a list of URLs to only supported image files.
    static func imageFiles(from urls: [URL]) -> [URL] {
        urls.filter { isImageFile($0) }
    }

    private func loadImage(from url: URL) -> CGImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
