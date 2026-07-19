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
        guard let document = PDFDocument(url: source) else {
            throw PDFwringerError.cannotOpenDocument
        }
        if document.isLocked { throw PDFwringerError.documentIsLocked }

        return try await exportPages(
            document: document,
            source: source,
            outputDirectory: outputDirectory,
            options: options,
            pageIndices: pageIndices,
            progress: progress
        )
    }

    /// Exports pages from an already-open document, including one the caller unlocked.
    func exportPages(
        document: PDFDocument,
        source: URL,
        outputDirectory: URL,
        options: Options,
        pageIndices: [Int]?,
        progress: (Double) -> Void
    ) async throws -> [URL] {
        if document.isLocked { throw PDFwringerError.documentIsLocked }

        let pageCount = document.pageCount
        guard pageCount > 0 else { throw PDFwringerError.cannotOpenDocument }
        guard options.dpi.isFinite, options.dpi > 0, options.dpi <= 2_400 else {
            throw PDFwringerError.cannotCreateOutput
        }
        if options.format == .jpeg {
            guard options.quality.isFinite, (0...1).contains(options.quality) else {
                throw PDFwringerError.cannotCreateOutput
            }
        }

        let requestedCount = pageIndices?.count ?? pageCount
        guard requestedCount > 0 else {
            throw PDFwringerError.invalidPageRange("empty")
        }
        guard requestedCount <= Self.maxOutputFiles else {
            throw PDFwringerError.documentTooLarge("Export would create \(requestedCount) files, exceeding the \(Self.maxOutputFiles) file limit")
        }

        let indicesToExport = pageIndices ?? Array(0..<pageCount)
        guard indicesToExport.allSatisfy({ $0 >= 0 && $0 < pageCount }) else {
            throw PDFwringerError.invalidPageRange("page outside document")
        }
        guard Set(indicesToExport).count == indicesToExport.count else {
            throw PDFwringerError.invalidPageRange("duplicate pages")
        }

        // Guard: disk space estimate (rough: pages × average image size at target DPI)
        let dpi = Double(options.dpi)
        let estimatedBytesPerPage = Int64((dpi * dpi * 0.3).rounded(.up))
        let estimatedTotal = estimatedBytesPerPage * Int64(indicesToExport.count)
        if let available = Formatting.availableDiskSpace(at: outputDirectory) {
            if estimatedTotal > available {
                throw PDFwringerError.insufficientDiskSpace(needed: estimatedTotal, available: available)
            }
        }

        // Resolve the output directory to detect symlink traversal
        let resolvedOutputDir = outputDirectory.standardizedFileURL.resolvingSymlinksInPath()

        let fileManager = FileManager.default
        var outputDirectoryIsDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: outputDirectory.path(percentEncoded: false),
            isDirectory: &outputDirectoryIsDirectory
        ), outputDirectoryIsDirectory.boolValue else {
            throw PDFwringerError.cannotWriteOutput
        }

        let baseName = source.deletingPathExtension().lastPathComponent
        let plannedOutputs = try indicesToExport.map { pageIndex -> (pageIndex: Int, outputURL: URL) in
            let filename = String(
                format: "%@_page_%03d.%@",
                baseName,
                pageIndex + 1,
                options.format.fileExtension
            )
            let outputURL = outputDirectory.appending(component: filename)
            let resolvedParent = outputURL.deletingLastPathComponent()
                .standardizedFileURL
                .resolvingSymlinksInPath()
            guard resolvedParent == resolvedOutputDir else {
                throw PDFwringerError.accessDenied
            }
            guard !fileManager.fileExists(atPath: outputURL.path(percentEncoded: false)) else {
                throw PDFwringerError.cannotWriteOutput
            }
            return (pageIndex, outputURL)
        }

        let stagingDirectory = try fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: outputDirectory,
            create: true
        )
        defer { try? fileManager.removeItem(at: stagingDirectory) }

        let start = ContinuousClock.now
        var stagedOutputs: [(stagedURL: URL, outputURL: URL)] = []

        for (i, plannedOutput) in plannedOutputs.enumerated() {
            try Task.checkCancellation()

            guard let page = document.page(at: plannedOutput.pageIndex),
                  let (rendered, _) = PDFCompressor.renderPage(
                    page,
                    dpi: options.dpi,
                    grayscale: false
                  ) else {
                throw PDFwringerError.cannotWriteOutput
            }

            let data: Data?
            switch options.format {
            case .jpeg:
                data = PDFCompressor.jpegEncode(image: rendered, quality: options.quality)
            case .png:
                data = pngEncode(image: rendered)
            }

            guard let imageData = data else { throw PDFwringerError.cannotWriteOutput }

            let stagedURL = stagingDirectory.appending(component: plannedOutput.outputURL.lastPathComponent)
            try imageData.write(to: stagedURL)
            stagedOutputs.append((stagedURL, plannedOutput.outputURL))

            progress(Double(i + 1) / Double(plannedOutputs.count))
            await Task.yield()
        }

        try Task.checkCancellation()
        var createdOutputs: [URL] = []
        do {
            for stagedOutput in stagedOutputs {
                guard !fileManager.fileExists(
                    atPath: stagedOutput.outputURL.path(percentEncoded: false)
                ) else {
                    throw PDFwringerError.cannotWriteOutput
                }
                try fileManager.moveItem(at: stagedOutput.stagedURL, to: stagedOutput.outputURL)
                createdOutputs.append(stagedOutput.outputURL)
            }
        } catch {
            for createdOutput in createdOutputs {
                try? fileManager.removeItem(at: createdOutput)
            }
            throw error
        }

        let elapsed = ContinuousClock.now - start
        Log.app.info("Export complete: \(createdOutputs.count) images, duration=\(elapsed)")

        return createdOutputs
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
