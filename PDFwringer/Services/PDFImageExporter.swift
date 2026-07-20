import CoreGraphics
import Foundation
import PDFKit

/// Exports PDF pages as image files (JPEG or PNG).
@MainActor
struct PDFImageExporter {

    /// Maximum number of image files that can be exported in one operation.
    private static let maxOutputFiles = 5_000

    enum ImageFormat: String, CaseIterable, Identifiable, Sendable {
        case jpeg
        case png

        var id: String { rawValue }

        var title: String {
            switch self {
            case .jpeg: "JPEG"
            case .png: "PNG"
            }
        }

        var fileExtension: String {
            switch self {
            case .jpeg: "jpg"
            case .png: "png"
            }
        }
    }

    struct Options: Sendable {
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
        try PDFPermissionPolicy.require(.copyContent, for: document)
        guard options.dpi.isFinite, options.dpi > 0, options.dpi <= 2_400 else {
            throw PDFwringerError.cannotCreateOutput
        }
        if options.format == .jpeg {
            guard options.quality.isFinite, (0...1).contains(options.quality) else {
                throw PDFwringerError.cannotCreateOutput
            }
        }

        let indicesToExport: [Int]
        if let pageIndices {
            guard !pageIndices.isEmpty else {
                throw PDFwringerError.invalidPageRange("empty")
            }

            var seen = Set<Int>()
            var uniqueIndices: [Int] = []
            uniqueIndices.reserveCapacity(min(pageIndices.count, Self.maxOutputFiles))
            for pageIndex in pageIndices {
                guard pageIndex >= 0, pageIndex < pageCount else {
                    throw PDFwringerError.invalidPageRange("page outside document")
                }
                guard seen.insert(pageIndex).inserted else { continue }
                uniqueIndices.append(pageIndex)
                guard uniqueIndices.count <= Self.maxOutputFiles else {
                    throw PDFwringerError.documentTooLarge(
                        "Export would create more than \(Self.maxOutputFiles) files"
                    )
                }
            }
            indicesToExport = uniqueIndices
        } else {
            guard pageCount <= Self.maxOutputFiles else {
                throw PDFwringerError.documentTooLarge(
                    "Export would create \(pageCount) files, exceeding the \(Self.maxOutputFiles) file limit"
                )
            }
            indicesToExport = Array(0..<pageCount)
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

        let fileManager = FileManager.default
        var outputDirectoryIsDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: outputDirectory.path(percentEncoded: false),
            isDirectory: &outputDirectoryIsDirectory
        ), outputDirectoryIsDirectory.boolValue else {
            throw PDFwringerError.cannotWriteOutput
        }

        let baseName = source.deletingPathExtension().lastPathComponent

        let stagingDirectory = try fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: outputDirectory,
            create: true
        )
        defer { try? fileManager.removeItem(at: stagingDirectory) }

        let start = ContinuousClock.now
        var stagedOutputs: [ExclusiveFilePublisher.StagedFile] = []

        for (i, pageIndex) in indicesToExport.enumerated() {
            try Task.checkCancellation()

            guard let page = document.page(at: pageIndex),
                  let pageData = page.dataRepresentation else {
                throw PDFwringerError.cannotWriteOutput
            }

            let imageData = try await PDFPageWorker.run(pageData: pageData) { isolatedPage in
                guard let (rendered, _) = PDFRasterizer.render(
                    isolatedPage,
                    dpi: options.dpi,
                    grayscale: false
                ) else {
                    throw PDFwringerError.cannotWriteOutput
                }

                let data: Data?
                switch options.format {
                case .jpeg:
                    data = PDFRasterizer.jpegData(for: rendered, quality: options.quality)
                case .png:
                    data = PDFRasterizer.pngData(for: rendered)
                }
                guard let data else { throw PDFwringerError.cannotWriteOutput }
                return data
            }

            let stagedURL = stagingDirectory.appending(
                component: "\(UUID().uuidString).\(options.format.fileExtension)"
            )
            try imageData.write(to: stagedURL)
            stagedOutputs.append(ExclusiveFilePublisher.StagedFile(
                url: stagedURL,
                baseStem: baseName,
                generatedSuffix: String(format: "_page_%03d", pageIndex + 1),
                pathExtension: options.format.fileExtension
            ))

            progress(Double(i + 1) / Double(indicesToExport.count))
        }

        try Task.checkCancellation()
        let publishedOutputs = try ExclusiveFilePublisher.publish(
            stagedOutputs,
            to: outputDirectory
        )

        let elapsed = ContinuousClock.now - start
        Log.app.info("Export complete: \(publishedOutputs.count) images, duration=\(elapsed)")

        return publishedOutputs
    }
}
