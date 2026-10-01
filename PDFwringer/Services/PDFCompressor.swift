import CoreGraphics
import Foundation
import PDFKit

/// Handles PDF compression via two strategies: lossless optimization (re-serialize with metadata stripped)
/// or lossy rasterization (render pages as JPEG at a target DPI).
@MainActor
struct PDFCompressor {

    private static let removableAnnotationSubtypes: Set<String> = [
        PDFAnnotationSubtype.text.rawValue,
        PDFAnnotationSubtype.link.rawValue,
        PDFAnnotationSubtype.freeText.rawValue,
        PDFAnnotationSubtype.line.rawValue,
        PDFAnnotationSubtype.square.rawValue,
        PDFAnnotationSubtype.circle.rawValue,
        PDFAnnotationSubtype.highlight.rawValue,
        PDFAnnotationSubtype.underline.rawValue,
        PDFAnnotationSubtype.strikeOut.rawValue,
        PDFAnnotationSubtype.ink.rawValue,
        PDFAnnotationSubtype.stamp.rawValue,
        PDFAnnotationSubtype.popup.rawValue
    ]

    struct Result {
        var outputSize: Int64
    }

    @MainActor
    final class PreparedCompression {
        private let stagedFile: AtomicFileWriter.StagedFile
        private let source: URL
        private let expectedPageCount: Int
        private let sourceIsEncrypted: Bool
        private let sourcePermissions: UInt
        let level: CompressionLevel
        let outputSize: Int64
        let previewDocument: PDFDocument?
        var destination: URL { stagedFile.destination }
        var url: URL { stagedFile.url }

        fileprivate init(stagedFile: AtomicFileWriter.StagedFile, source: URL,
                         document: PDFDocument, level: CompressionLevel, outputSize: Int64) throws {
            guard let output = PDFDocument(url: stagedFile.url) else {
                throw PDFwringerError.cannotWriteOutput
            }
            self.stagedFile = stagedFile
            self.source = source
            expectedPageCount = document.pageCount
            sourceIsEncrypted = document.isEncrypted
            sourcePermissions = UInt(document.accessPermissions.rawValue)
            self.level = level
            self.outputSize = outputSize
            previewDocument = output.isLocked ? nil : output
        }

        func commit() async throws {
            let staged = stagedFile
            let source = source
            let count = expectedPageCount
            let encrypted = sourceIsEncrypted
            let permissions = sourcePermissions
            let size = outputSize
            let rasterized = level.isRasterize
            let worker = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                try FileSystemIdentity.requireDistinct(source, staged.destination)
                guard let actualSize = try FileManager.default.attributesOfItem(
                    atPath: staged.url.path(percentEncoded: false))[.size] as? Int64,
                      actualSize == size, let output = PDFDocument(url: staged.url) else {
                    throw PDFwringerError.cannotWriteOutput
                }
                if !rasterized {
                    try PDFEncryptionPolicy.requirePreservedProtection(
                        sourceIsEncrypted: encrypted, sourcePermissions: permissions, in: output)
                }
                if !output.isLocked {
                    try PDFCompressor.validateOutput(output, expectedPageCount: count,
                                                     requireNoAnnotations: rasterized)
                }
                try FileSystemIdentity.requireDistinct(source, staged.destination)
                try staged.commit()
            }
            try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: { worker.cancel() }
        }
    }

    enum TargetResult {
        case alreadyUnderLimit(Int64)
        case prepared(PreparedCompression)
        case unattainable(smallestSize: Int64)
    }

    /// Renders into a retained staging file without publishing to the chosen path.
    func prepare(document: PDFDocument, source: URL, destination: URL,
                 level: CompressionLevel, quality: JPEGQuality, grayscale: Bool,
                 removeAnnotations: Bool = false, progress: (Double) -> Void) async throws -> PreparedCompression {
        try FileSystemIdentity.requireDistinct(source, destination)
        let staged = try AtomicFileWriter.StagedFile(destination: destination)
        let result = try await compress(document: document, source: source, destination: staged.url,
                                        level: level, quality: quality, grayscale: grayscale,
                                        removeAnnotations: removeAnnotations,
                                        progress: { progress(min(0.99, $0)) })
        try Task.checkCancellation()
        let prepared = try PreparedCompression(stagedFile: staged, source: source, document: document,
                                               level: level, outputSize: result.outputSize)
        progress(1)
        return prepared
    }

    /// Lossless plus at most three existing raster presets. Errors fail closed;
    /// only a successfully validated, oversized result advances to another preset.
    func prepareToFit(document: PDFDocument, source: URL, destination: URL,
                      limitBytes: Int64, allowRasterization: Bool, grayscale: Bool,
                      progress: (Double) -> Void) async throws -> TargetResult {
        try Task.checkCancellation()
        try FileSystemIdentity.requireDistinct(source, destination)
        guard limitBytes > 0 else { throw PDFwringerError.cannotCreateOutput }
        guard !document.isLocked, document.pageCount > 0 else {
            throw PDFwringerError.cannotOpenDocument
        }
        let sourceSize = try FileManager.default.attributesOfItem(atPath: source.path(percentEncoded: false))[.size] as? Int64 ?? 0
        guard sourceSize > 0 else { throw PDFwringerError.cannotOpenDocument }
        if sourceSize < limitBytes { return .alreadyUnderLimit(sourceSize) }

        let staged = try AtomicFileWriter.StagedFile(destination: destination)
        let levels: [CompressionLevel] = allowRasterization ? [.lossless, .high, .medium, .low] : [.lossless]
        var smallestSize = Int64.max
        for (index, level) in levels.enumerated() {
            try Task.checkCancellation()
            let result = try await compress(document: document, source: source, destination: staged.url,
                                            level: level, quality: .good, grayscale: grayscale,
                                            progress: { progress(min(0.99, (Double(index) + $0) / Double(levels.count))) })
            try Task.checkCancellation()
            smallestSize = min(smallestSize, result.outputSize)
            if result.outputSize < limitBytes {
                let prepared = try PreparedCompression(stagedFile: staged, source: source, document: document,
                                                        level: level, outputSize: result.outputSize)
                progress(1)
                return .prepared(prepared)
            }
            try FileManager.default.removeItem(at: staged.url)
        }
        progress(1)
        return .unattainable(smallestSize: smallestSize)
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
                source: source,
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

    /// Estimates requested settings (or all settings for noninteractive callers)
    /// from one source open and at most one
    /// first-page render per DPI/color combination. The first-page byte count is
    /// extrapolated across the document, so estimates assume roughly uniform content.
    nonisolated func estimateFirstPageSizes(
        source: URL, quality selectedQuality: JPEGQuality? = nil, grayscale selectedGrayscale: Bool? = nil
    ) throws -> [String: Int64] {
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

        let qualities = selectedQuality.map { [$0] } ?? JPEGQuality.allCases
        let colorModes = selectedGrayscale.map { [$0] } ?? [false, true]
        var estimates: [String: Int64] = [:]
        let losslessEstimate = Int64(Double(sourceSize) * 0.95)
        for quality in qualities {
            for grayscale in colorModes {
                estimates[Self.estimateKey(
                    level: .lossless,
                    quality: quality,
                    grayscale: grayscale
                )] = losslessEstimate
            }
        }

        let pageCount = Int64(document.numberOfPages)
        for level in CompressionLevel.allCases where level.isRasterize {
            for grayscale in colorModes {
                try Task.checkCancellation()
                guard let (rendered, _) = PDFRasterizer.render(
                    firstPage,
                    dpi: level.dpi,
                    grayscale: grayscale
                ) else { continue }

                for quality in qualities {
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
        source: URL,
        destination: URL,
        removeAnnotations: Bool,
        progress: (Double) -> Void
    ) async throws {
        try Task.checkCancellation()
        let staged = try AtomicFileWriter.StagedFile(destination: destination)
        defer { staged.cleanup() }
        guard let doc = document.copy() as? PDFDocument else {
            throw PDFwringerError.cannotOpenDocument
        }

        guard doc.pageCount > 0 else {
            throw PDFwringerError.cannotOpenDocument
        }

        doc.documentAttributes?.removeAll()

        if removeAnnotations {
            guard Self.annotationRemovalIsSafe(in: doc) else {
                throw PDFwringerError.sensitiveAnnotationsRequireFlattening
            }
            for i in 0..<doc.pageCount {
                try Task.checkCancellation()
                guard let page = doc.page(at: i) else {
                    throw PDFwringerError.cannotOpenDocument
                }
                for annotation in page.annotations {
                    page.removeAnnotation(annotation)
                }
                guard page.annotations.isEmpty else {
                    throw PDFwringerError.annotationRemovalFailed
                }
            }
        }

        guard let data = doc.dataRepresentation() else {
            throw PDFwringerError.cannotWriteOutput
        }
        guard !data.isEmpty else { throw PDFwringerError.cannotWriteOutput }
        let expectedPageCount = document.pageCount
        let sourceWasEncrypted = document.isEncrypted
        let sourcePermissions = UInt(document.accessPermissions.rawValue)
        if let available = Formatting.availableDiskSpace(at: destination), Int64(data.count) > available {
            throw PDFwringerError.insufficientDiskSpace(needed: Int64(data.count), available: available)
        }

        // The authoritative copy and serialization stay on MainActor. Every
        // verification document below belongs exclusively to this worker.
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard let serializedOutput = PDFDocument(data: data) else {
                throw PDFwringerError.cannotWriteOutput
            }
            try PDFEncryptionPolicy.requirePreservedProtection(
                sourceIsEncrypted: sourceWasEncrypted, sourcePermissions: sourcePermissions,
                in: serializedOutput
            )
            if serializedOutput.isLocked {
                guard serializedOutput.isEncrypted else { throw PDFwringerError.cannotWriteOutput }
            } else {
                try Self.validateOutput(serializedOutput, expectedPageCount: expectedPageCount,
                                        requireNoAnnotations: removeAnnotations)
            }
            try Task.checkCancellation()
            try data.write(to: staged.url)
            try Task.checkCancellation()
            guard let output = PDFDocument(url: staged.url) else {
                throw PDFwringerError.cannotWriteOutput
            }
            try PDFEncryptionPolicy.requirePreservedProtection(
                sourceIsEncrypted: sourceWasEncrypted, sourcePermissions: sourcePermissions,
                in: output
            )
            if output.isLocked {
                guard output.isEncrypted else { throw PDFwringerError.cannotWriteOutput }
            } else {
                try Self.validateOutput(output, expectedPageCount: expectedPageCount,
                                        requireNoAnnotations: removeAnnotations)
            }
            try FileSystemIdentity.requireDistinct(source, destination)
            try staged.commit()
        }
        try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: { worker.cancel() }

        progress(1.0)
    }

    /// Lossless removal is intentionally limited to known comment/markup/link
    /// types. Widgets can carry form or signature values, redaction overlays can
    /// conceal sensitive content, and unknown subtypes may contain attachments.
    static func annotationRemovalIsSafe(in document: PDFDocument) -> Bool {
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { return false }
            for annotation in page.annotations {
                guard annotation.markupType != .redact,
                      let subtype = annotation.value(forAnnotationKey: .subtype)
                        as? PDFAnnotationSubtype,
                      Self.removableAnnotationSubtypes.contains(subtype.rawValue) else {
                    return false
                }
            }
        }
        return true
    }

    // MARK: - Rasterize path (maximum compression, flattens content)

    private func compressRasterize(
        document: PDFDocument,
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

        let estimatedNeeded = try await PDFRasterizer.estimatedEncodedOutputBytes(
            document: document,
            pageIndices: Array(0..<pageCount),
            dpi: dpi,
            bytesPerPixel: 4
        )
        if let available = Formatting.availableDiskSpace(at: destination) {
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

                    progress(min(0.99, Double(i + 1) / Double(pageCount)))
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
        progress(1)
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

    private nonisolated static func validateOutput(
        _ output: PDFDocument,
        expectedPageCount: Int,
        requireNoAnnotations: Bool
    ) throws {
        guard output.pageCount == expectedPageCount else {
            throw PDFwringerError.cannotWriteOutput
        }
        for index in 0..<expectedPageCount {
            try Task.checkCancellation()
            guard let page = output.page(at: index) else {
                throw PDFwringerError.cannotWriteOutput
            }
            if requireNoAnnotations, !page.annotations.isEmpty {
                throw PDFwringerError.annotationRemovalFailed
            }
        }
    }
}
