import CoreGraphics
import Foundation
import PDFKit

/// Handles PDF compression via two strategies: lossless optimization (re-serialize with metadata stripped)
/// or lossy rasterization (render pages as JPEG at a target DPI).
@MainActor
struct PDFCompressor {

    struct Result {
        var outputSize: Int64
    }

    /// Compresses a PDF from `source` to `destination` using the selected strategy.
    @discardableResult
    func compress(
        source: URL,
        destination: URL,
        level: CompressionLevel,
        quality: JPEGQuality,
        grayscale: Bool,
        removeAnnotations: Bool = false,
        progress: (Double) -> Void
    ) async throws -> Result {
        guard FileManager.default.isReadableFile(atPath: source.path(percentEncoded: false)) else {
            throw PDFwringerError.fileNotReadable(source.lastPathComponent)
        }
        guard let document = PDFDocument(url: source) else {
            throw PDFwringerError.cannotOpenDocument
        }
        if document.isLocked { throw PDFwringerError.documentIsLocked }

        return try await compress(
            document: document,
            source: source,
            destination: destination,
            level: level,
            quality: quality,
            grayscale: grayscale,
            removeAnnotations: removeAnnotations,
            progress: progress
        )
    }

    /// Compresses the supplied, already-open document. The URL is used only for
    /// source identity, naming, and size estimates; document content comes from `document`.
    @discardableResult
    func compress(
        document: PDFDocument,
        source: URL,
        destination: URL,
        level: CompressionLevel,
        quality: JPEGQuality,
        grayscale: Bool,
        removeAnnotations: Bool = false,
        progress: (Double) -> Void
    ) async throws -> Result {
        let start = ContinuousClock.now
        Log.compress.info("Starting compression: level=\(level.title), quality=\(quality.title), grayscale=\(grayscale)")

        try FileSystemIdentity.requireDistinct(source, destination)
        if document.isLocked { throw PDFwringerError.documentIsLocked }
        guard document.pageCount > 0 else { throw PDFwringerError.cannotOpenDocument }

        if level.isRasterize {
            try PDFPermissionPolicy.require(.copyContent, .changeDocument, for: document)
            try await compressRasterize(
                document: document,
                source: source,
                destination: destination,
                dpi: level.dpi,
                quality: quality.value,
                grayscale: grayscale,
                progress: progress
            )
        } else {
            try PDFPermissionPolicy.require(.changeDocument, for: document)
            try await compressOptimize(
                document: document,
                destination: destination,
                removeAnnotations: removeAnnotations,
                progress: progress
            )
        }
        let outputSize = (try? FileManager.default.attributesOfItem(atPath: destination.path(percentEncoded: false))[.size] as? Int64) ?? 0
        guard outputSize > 0 else { throw PDFwringerError.cannotWriteOutput }
        let elapsed = ContinuousClock.now - start
        Log.compress.info("Compression complete: output=\(Formatting.fileSize(outputSize)), duration=\(elapsed)")
        return Result(outputSize: outputSize)
    }

    /// Estimates every compression setting from one source open and at most one
    /// first-page render per DPI/color combination. The first-page byte count is
    /// extrapolated across the document, so estimates assume roughly uniform content.
    nonisolated func estimateFirstPageSizes(source: URL) throws -> [String: Int64] {
        try Task.checkCancellation()
        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: source.path(percentEncoded: false)
        ), let sourceSize = attributes[.size] as? Int64 else {
            throw PDFwringerError.fileNotReadable(source.lastPathComponent)
        }
        guard let document = PDFRasterizer.openDocument(at: source),
              document.numberOfPages > 0,
              let firstPage = document.page(at: 1) else {
            throw PDFwringerError.cannotOpenDocument
        }

        var estimates: [String: Int64] = [:]
        let losslessEstimate = Int64(Double(sourceSize) * 0.95)
        for quality in JPEGQuality.allCases {
            for grayscale in [false, true] {
                estimates[Self.estimateKey(
                    level: .lossless,
                    quality: quality,
                    grayscale: grayscale
                )] = losslessEstimate
            }
        }

        let pageCount = Int64(document.numberOfPages)
        for level in CompressionLevel.allCases where level.isRasterize {
            for grayscale in [false, true] {
                try Task.checkCancellation()
                guard let (rendered, _) = PDFRasterizer.render(
                    firstPage,
                    dpi: level.dpi,
                    grayscale: grayscale
                ) else { continue }

                for quality in JPEGQuality.allCases {
                    try Task.checkCancellation()
                    guard let jpegData = PDFRasterizer.jpegData(
                        for: rendered,
                        quality: quality.value
                    ),
                          let estimate = Self.extrapolatedSize(
                            firstPageSize: Int64(jpegData.count),
                            pageCount: pageCount
                          ) else { continue }
                    estimates[Self.estimateKey(
                        level: level,
                        quality: quality,
                        grayscale: grayscale
                    )] = estimate
                }
            }
        }
        return estimates
    }

    nonisolated static func estimateKey(
        level: CompressionLevel,
        quality: JPEGQuality,
        grayscale: Bool
    ) -> String {
        "\(level.rawValue)-\(quality.rawValue)-\(grayscale)"
    }

    nonisolated private static func extrapolatedSize(
        firstPageSize: Int64,
        pageCount: Int64
    ) -> Int64? {
        let (perPage, perPageOverflow) = firstPageSize.addingReportingOverflow(200)
        guard !perPageOverflow else { return nil }
        let (pages, pagesOverflow) = perPage.multipliedReportingOverflow(by: pageCount)
        guard !pagesOverflow else { return nil }
        let (total, totalOverflow) = pages.addingReportingOverflow(1_000)
        return totalOverflow ? nil : total
    }

    // MARK: - Optimize path (preserves text; strips annotations only when removeAnnotations is true)

    private func compressOptimize(
        document: PDFDocument,
        destination: URL,
        removeAnnotations: Bool,
        progress: (Double) -> Void
    ) async throws {
        try Task.checkCancellation()
        guard let doc = document.copy() as? PDFDocument else {
            throw PDFwringerError.cannotOpenDocument
        }

        guard doc.pageCount > 0 else {
            throw PDFwringerError.cannotOpenDocument
        }

        doc.documentAttributes?.removeAll()

        if removeAnnotations {
            for i in 0..<doc.pageCount {
                try Task.checkCancellation()
                guard let page = doc.page(at: i) else {
                    throw PDFwringerError.cannotOpenDocument
                }
                for annotation in page.annotations {
                    page.removeAnnotation(annotation)
                }
                guard page.annotations.isEmpty else {
                    throw PDFwringerError.cannotWriteOutput
                }
            }
        }

        guard let data = doc.dataRepresentation() else {
            throw PDFwringerError.cannotWriteOutput
        }
        guard !data.isEmpty, let serializedOutput = PDFDocument(data: data) else {
            throw PDFwringerError.cannotWriteOutput
        }
        if serializedOutput.isLocked {
            guard serializedOutput.isEncrypted else {
                throw PDFwringerError.cannotWriteOutput
            }
        } else {
            try Self.validateOutput(
                serializedOutput,
                expectedPageCount: document.pageCount,
                requireNoAnnotations: removeAnnotations
            )
        }

        if let available = Formatting.availableDiskSpace(at: destination) {
            let needed = Int64(data.count)
            if needed > available {
                throw PDFwringerError.insufficientDiskSpace(needed: needed, available: available)
            }
        }

        try Task.checkCancellation()
        try AtomicFileWriter.write(to: destination) { tempURL in
            try data.write(to: tempURL)
            guard let output = PDFDocument(url: tempURL) else { return false }
            if output.isLocked { return output.isEncrypted }
            do {
                try Self.validateOutput(
                    output,
                    expectedPageCount: document.pageCount,
                    requireNoAnnotations: removeAnnotations
                )
                return true
            } catch {
                return false
            }
        }

        progress(1.0)
    }

    // MARK: - Rasterize path (maximum compression, flattens content)

    private func compressRasterize(
        document: PDFDocument,
        source: URL,
        destination: URL,
        dpi: CGFloat,
        quality: CGFloat,
        grayscale: Bool,
        progress: (Double) -> Void
    ) async throws {
        let pageCount = document.pageCount
        guard pageCount > 0 else { throw PDFwringerError.cannotOpenDocument }
        guard pageCount <= 10_000 else {
            throw PDFwringerError.documentTooLarge("\(pageCount) pages exceeds the 10,000 page limit for rasterization")
        }

        // Estimate output size for disk space check (rough: source size * 0.5 as lower bound)
        if let available = Formatting.availableDiskSpace(at: destination) {
            let sourceSize = (try? FileManager.default.attributesOfItem(atPath: source.path(percentEncoded: false))[.size] as? Int64) ?? 0
            let estimatedNeeded = max(sourceSize / 2, Int64(pageCount) * 50_000)
            if estimatedNeeded > available {
                throw PDFwringerError.insufficientDiskSpace(needed: estimatedNeeded, available: available)
            }
        }

        try await AtomicFileWriter.write(to: destination) { stagedURL in
            var emptyBox = CGRect.zero
            guard let outputCtx = CGContext(stagedURL as CFURL, mediaBox: &emptyBox, nil) else {
                throw PDFwringerError.cannotCreateOutput
            }

            var outputIsClosed = false
            do {
                for i in 0..<pageCount {
                    try Task.checkCancellation()

                    let pageData = try autoreleasepool { () throws -> Data in
                        guard let page = document.page(at: i) else {
                            throw PDFwringerError.cannotOpenDocument
                        }
                        guard let data = page.dataRepresentation else {
                            throw PDFwringerError.cannotOpenDocument
                        }
                        return data
                    }

                    let encodedPage = try await PDFPageWorker.run(pageData: pageData) { page in
                        guard let (rendered, displaySize) = PDFRasterizer.render(
                            page,
                            dpi: dpi,
                            grayscale: grayscale
                        ) else {
                            throw PDFwringerError.cannotCreateOutput
                        }
                        guard let jpegData = PDFRasterizer.jpegData(
                            for: rendered,
                            quality: quality
                        ) else {
                            throw PDFwringerError.cannotWriteOutput
                        }
                        return PDFRasterizer.JPEGPage(data: jpegData, displaySize: displaySize)
                    }

                    try autoreleasepool {
                        try PDFRasterizer.append(encodedPage, to: outputCtx)
                    }

                    progress(Double(i + 1) / Double(pageCount))
                }

                try Task.checkCancellation()
                outputCtx.closePDF()
                outputIsClosed = true

                try Self.validateOutput(at: stagedURL, expectedPageCount: pageCount)
                return true
            } catch {
                if !outputIsClosed {
                    outputCtx.closePDF()
                }
                throw error
            }
        }
    }

    // MARK: - Helpers

    private static func validateOutput(
        data: Data,
        expectedPageCount: Int,
        requireNoAnnotations: Bool = false
    ) throws {
        guard let output = PDFDocument(data: data) else {
            throw PDFwringerError.cannotWriteOutput
        }
        try validateOutput(
            output,
            expectedPageCount: expectedPageCount,
            requireNoAnnotations: requireNoAnnotations
        )
    }

    private static func validateOutput(
        at url: URL,
        expectedPageCount: Int,
        requireNoAnnotations: Bool = false
    ) throws {
        guard let output = PDFDocument(url: url) else {
            throw PDFwringerError.cannotWriteOutput
        }
        try validateOutput(
            output,
            expectedPageCount: expectedPageCount,
            requireNoAnnotations: requireNoAnnotations
        )
    }

    private static func validateOutput(
        _ output: PDFDocument,
        expectedPageCount: Int,
        requireNoAnnotations: Bool
    ) throws {
        guard output.pageCount == expectedPageCount else {
            throw PDFwringerError.cannotWriteOutput
        }
        for index in 0..<expectedPageCount {
            guard let page = output.page(at: index) else {
                throw PDFwringerError.cannotWriteOutput
            }
            if requireNoAnnotations, !page.annotations.isEmpty {
                throw PDFwringerError.cannotWriteOutput
            }
        }
    }
}
