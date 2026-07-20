import CoreGraphics
import Darwin
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

        let stagingDirectory = try fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: outputDirectory,
            create: true
        )
        defer { try? fileManager.removeItem(at: stagingDirectory) }

        let start = ContinuousClock.now
        var stagedOutputs: [(pageIndex: Int, stagedURL: URL)] = []

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
            stagedOutputs.append((pageIndex, stagedURL))

            progress(Double(i + 1) / Double(indicesToExport.count))
        }

        try Task.checkCancellation()
        var publishedOutputs: [PublishedOutput] = []
        do {
            for stagedOutput in stagedOutputs {
                guard let identity = fileIdentity(at: stagedOutput.stagedURL) else {
                    throw PDFwringerError.cannotWriteOutput
                }
                let outputURL = try publish(
                    stagedURL: stagedOutput.stagedURL,
                    pageIndex: stagedOutput.pageIndex,
                    baseName: baseName,
                    fileExtension: options.format.fileExtension,
                    outputDirectory: outputDirectory,
                    resolvedOutputDirectory: resolvedOutputDir
                )
                publishedOutputs.append(PublishedOutput(url: outputURL, identity: identity))
            }
        } catch {
            rollback(publishedOutputs)
            throw error
        }

        let elapsed = ContinuousClock.now - start
        Log.app.info("Export complete: \(publishedOutputs.count) images, duration=\(elapsed)")

        return publishedOutputs.map(\.url)
    }

    /// Publishes a staged image without replacing any existing filesystem entry.
    /// A collision receives the lowest available numeric suffix, including when
    /// another process creates the candidate between rendering and publication.
    private func publish(
        stagedURL: URL,
        pageIndex: Int,
        baseName: String,
        fileExtension: String,
        outputDirectory: URL,
        resolvedOutputDirectory: URL
    ) throws -> URL {
        let stem = String(format: "%@_page_%03d", baseName, pageIndex + 1)
        var suffix = 0

        while true {
            let filename = suffix == 0
                ? "\(stem).\(fileExtension)"
                : "\(stem)_\(suffix).\(fileExtension)"
            let candidate = outputDirectory.appending(component: filename)
            let resolvedParent = candidate.deletingLastPathComponent()
                .standardizedFileURL
                .resolvingSymlinksInPath()
            guard resolvedParent == resolvedOutputDirectory else {
                throw PDFwringerError.accessDenied
            }

            if try renameExclusively(from: stagedURL, to: candidate) {
                return candidate
            }
            suffix += 1
        }
    }

    /// `FileManager.moveItem` can overwrite in a check-then-move race. Darwin's
    /// exclusive rename makes the no-clobber guarantee a single filesystem step.
    private func renameExclusively(from source: URL, to destination: URL) throws -> Bool {
        let result: Int32 = try source.withUnsafeFileSystemRepresentation { sourcePath in
            guard let sourcePath else { throw PDFwringerError.cannotWriteOutput }
            return try destination.withUnsafeFileSystemRepresentation { destinationPath in
                guard let destinationPath else { throw PDFwringerError.cannotWriteOutput }
                return renameatx_np(
                    AT_FDCWD,
                    sourcePath,
                    AT_FDCWD,
                    destinationPath,
                    UInt32(RENAME_EXCL)
                )
            }
        }

        if result == 0 { return true }
        let errorCode = errno
        if errorCode == EEXIST { return false }
        Log.fileIO.error("Exclusive image export rename failed with errno \(errorCode)")
        throw PDFwringerError.cannotWriteOutput
    }

    private struct FileIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
    }

    private struct PublishedOutput {
        let url: URL
        let identity: FileIdentity
    }

    private func fileIdentity(at url: URL) -> FileIdentity? {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return nil }
            var information = stat()
            guard lstat(path, &information) == 0 else { return nil }
            return FileIdentity(
                device: UInt64(information.st_dev),
                inode: UInt64(information.st_ino)
            )
        }
    }

    private func rollback(_ outputs: [PublishedOutput]) {
        for output in outputs.reversed() {
            guard fileIdentity(at: output.url) == output.identity else {
                Log.fileIO.error(
                    "Skipped rollback of changed export: \(output.url.lastPathComponent, privacy: .private)"
                )
                continue
            }
            do {
                try FileManager.default.removeItem(at: output.url)
            } catch {
                Log.fileIO.error(
                    "Failed to roll back export: \(output.url.lastPathComponent, privacy: .private)"
                )
            }
        }
    }
}
