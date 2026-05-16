import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Exports PDF pages as image files (JPEG or PNG).
@MainActor
struct PDFImageExporter {

    /// Maximum number of image files that can be exported in one operation.
    private static let maxOutputFiles = 5_000

    enum ImageFormat: String, CaseIterable, Identifiable {
        case jpeg
        case png

        var id: String { rawValue }

        var title: String {
            switch self {
            case .jpeg: "JPEG"
            case .png: "PNG"
            }
        }

        var utType: UTType {
            switch self {
            case .jpeg: .jpeg
            case .png: .png
            }
        }

        var fileExtension: String {
            switch self {
            case .jpeg: "jpg"
            case .png: "png"
            }
        }
    }

    struct Options {
        var format: ImageFormat = .jpeg
        var dpi: CGFloat = 150
        var quality: CGFloat = 0.85 // JPEG only
    }

    /// Exports selected pages as images into the given output directory.
    /// Returns the URLs of all exported image files.
    ///
    /// Security: uses atomic writes via temp files, checks for symlinks,
    /// validates path containment, enforces output count and disk space limits.
    func exportPages(
        source: URL,
        outputDirectory: URL,
        options: Options,
        pageIndices: [Int]?,
        progress: (Double) -> Void
    ) async throws -> [URL] {
        guard FileManager.default.isReadableFile(atPath: source.path(percentEncoded: false)) else {
            throw PDFwringerError.fileNotReadable(source.lastPathComponent)
        }

        guard let doc = PDFCompressor.openPDF(at: source) else {
            throw PDFwringerError.cannotOpenDocument
        }

        let pageCount = doc.numberOfPages
        guard pageCount > 0 else { throw PDFwringerError.cannotOpenDocument }

        let indicesToExport: [Int]
        if let indices = pageIndices {
            indicesToExport = indices.filter { $0 >= 0 && $0 < pageCount }
        } else {
            indicesToExport = Array(0..<pageCount)
        }

        guard !indicesToExport.isEmpty else {
            throw PDFwringerError.invalidPageRange("empty")
        }

        // Guard: output file count limit
        guard indicesToExport.count <= Self.maxOutputFiles else {
            throw PDFwringerError.documentTooLarge("Export would create \(indicesToExport.count) files, exceeding the \(Self.maxOutputFiles) file limit")
        }

        // Guard: disk space estimate (rough: pages × average image size at target DPI)
        let estimatedBytesPerPage: Int64 = Int64(options.dpi * options.dpi * 3 / 10) // rough JPEG estimate
        let estimatedTotal = estimatedBytesPerPage * Int64(indicesToExport.count)
        if let available = Formatting.availableDiskSpace(at: outputDirectory) {
            if estimatedTotal > available {
                throw PDFwringerError.insufficientDiskSpace(needed: estimatedTotal, available: available)
            }
        }

        // Resolve the output directory to detect symlink traversal
        let resolvedOutputDir = outputDirectory.standardizedFileURL.resolvingSymlinksInPath()

        let start = ContinuousClock.now
        let baseName = source.deletingPathExtension().lastPathComponent

        var outputURLs: [URL] = []

        for (i, pageIdx) in indicesToExport.enumerated() {
            try Task.checkCancellation()

            guard let page = doc.page(at: pageIdx + 1) else { continue } // CGPDFDocument is 1-based

            guard let (rendered, _) = PDFCompressor.renderPage(page, dpi: options.dpi, grayscale: false) else { continue }

            let filename = String(format: "%@_page_%03d.%@", baseName, pageIdx + 1, options.format.fileExtension)
            let outputURL = outputDirectory.appending(component: filename)

            // Security: verify resolved path stays inside the output directory
            let resolvedOutput = outputURL.standardizedFileURL.resolvingSymlinksInPath()
            guard resolvedOutput.path(percentEncoded: false).hasPrefix(resolvedOutputDir.path(percentEncoded: false)) else {
                continue // skip paths that escape the output directory
            }

            // Security: reject if target exists and is a symlink or non-regular file
            let outputPath = outputURL.path(percentEncoded: false)
            if FileManager.default.fileExists(atPath: outputPath) {
                let attrs = try? FileManager.default.attributesOfItem(atPath: outputPath)
                let fileType = attrs?[.type] as? FileAttributeType
                if fileType == .typeSymbolicLink || (fileType != nil && fileType != .typeRegular) {
                    continue // skip symlinks and non-regular files
                }
            }

            let data: Data?
            switch options.format {
            case .jpeg:
                data = PDFCompressor.jpegEncode(image: rendered, quality: options.quality)
            case .png:
                data = pngEncode(image: rendered)
            }

            guard let imageData = data else { continue }

            // Security: atomic write via temp file then move/replace
            let tempURL = AtomicFileWriter.tempDirectory.appending(component: UUID().uuidString + "." + options.format.fileExtension)
            try imageData.write(to: tempURL)
            do {
                if FileManager.default.fileExists(atPath: outputPath) {
                    _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: tempURL)
                } else {
                    try FileManager.default.moveItem(at: tempURL, to: outputURL)
                }
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                throw error
            }

            outputURLs.append(outputURL)

            progress(Double(i + 1) / Double(indicesToExport.count))
            await Task.yield()
        }

        let elapsed = ContinuousClock.now - start
        Log.app.info("Export complete: \(outputURLs.count) images, duration=\(elapsed)")

        return outputURLs
    }

    private func pngEncode(image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
