import Foundation
import OSLog
import PDFKit
import SwiftUI

/// Domain-specific errors surfaced to users via `LocalizedError`.
enum PDFwringerError: LocalizedError {
    case cannotOpenDocument
    case documentIsLocked
    case cannotCreateOutput
    case cannotWriteOutput
    case invalidPageRange(String)
    case invalidPageOrder
    case noSourceFile
    case emptyFileList
    case accessDenied
    case fileNotReadable(String)
    case insufficientDiskSpace(needed: Int64, available: Int64)
    case sourceEqualsDestination
    case documentTooLarge(String)
    case documentPermissionsDenied
    case sensitiveAnnotationsRequireFlattening

    var errorDescription: String? {
        switch self {
        case .cannotOpenDocument: String(localized: "Cannot open the PDF document. It may be corrupted or have zero pages.")
        case .documentIsLocked: String(localized: "This PDF is password-protected.")
        case .cannotCreateOutput: String(localized: "Cannot create the output file.")
        case .cannotWriteOutput: String(localized: "Failed to write the output file.")
        case .invalidPageRange(let range): String(localized: "Invalid page range: '\(range)'")
        case .invalidPageOrder: String(localized: "The page order is incomplete or invalid.")
        case .noSourceFile: String(localized: "No source file selected.")
        case .emptyFileList: String(localized: "No files to process.")
        case .accessDenied: String(localized: "Cannot access the file. Try selecting it again.")
        case .fileNotReadable(let name): String(localized: "Cannot read '\(name)'. The file may have been moved or deleted.")
        case .insufficientDiskSpace(let needed, let available):
            String(localized: "Not enough disk space. Need \(Formatting.fileSize(needed)), only \(Formatting.fileSize(available)) available.")
        case .sourceEqualsDestination:
            String(localized: "Source and destination cannot be the same file. Choose a different location.")
        case .documentTooLarge(let detail):
            String(localized: "Document is too large to process safely: \(detail)")
        case .documentPermissionsDenied:
            String(localized: "This PDF's permissions do not allow this operation.")
        case .sensitiveAnnotationsRequireFlattening:
            String(localized: "This PDF contains forms, signatures, redactions, or unsupported annotations. Flatten annotations instead of removing them.")
        }
    }
}

/// Shared formatting utilities for the app.
enum Formatting {
    /// Formats a byte count as a human-readable file size string (e.g. "1.2 MB").
    static func fileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Returns available disk space on the volume that contains the URL. Save-panel
    /// destinations commonly do not exist yet, so walk up to the nearest existing
    /// ancestor before asking for volume capacity.
    static func availableDiskSpace(at url: URL) -> Int64? {
        guard url.isFileURL else { return nil }

        let fileManager = FileManager.default
        var existingURL = url.standardizedFileURL
        while !fileManager.fileExists(atPath: existingURL.path(percentEncoded: false)) {
            let parent = existingURL.deletingLastPathComponent()
            guard parent != existingURL else { return nil }
            existingURL = parent
        }

        let values = try? existingURL.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// Triggers a horizontal shake animation sequence on the given offset binding.
    @MainActor static func triggerShake(_ offset: Binding<CGFloat>) {
        Task { @MainActor in
            withAnimation(.default) { offset.wrappedValue = 8 }
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.default) { offset.wrappedValue = -6 }
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.default) { offset.wrappedValue = 4 }
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.default) { offset.wrappedValue = 0 }
        }
    }
}

/// Writes content to a temporary file then atomically replaces the destination.
/// Cleans up the temp file on failure.
enum AtomicFileWriter {
    // Releases before destination-volume staging wrote UUID-named PDFs and images here.
    // Keep this migration cleanup for one release, then remove it and the launch calls.
    private static let legacyTempDirectory = URL.temporaryDirectory
        .appending(component: "PDFwringer")
    private static let legacyTempExtensions: Set<String> = ["pdf", "jpg", "jpeg", "png"]

    static func write(to destination: URL, using block: (URL) throws -> Bool) throws {
        let stagedFile = try StagedFile(destination: destination)
        defer { stagedFile.cleanup() }

        Log.fileIO.debug("AtomicWrite: temp=\(stagedFile.url.lastPathComponent, privacy: .private) → dest")
        let success = try block(stagedFile.url)
        guard success else {
            throw PDFwringerError.cannotWriteOutput
        }
        try stagedFile.commit()
    }

    /// Async counterpart for producers that must yield or cooperatively cancel while
    /// writing. The staging and commit guarantees are identical to the synchronous API.
    @MainActor
    static func write(to destination: URL, using block: (URL) async throws -> Bool) async throws {
        let stagedFile = try StagedFile(destination: destination)
        defer { stagedFile.cleanup() }

        Log.fileIO.debug("AtomicWrite: temp=\(stagedFile.url.lastPathComponent, privacy: .private) → dest")
        let success = try await block(stagedFile.url)
        guard success else {
            throw PDFwringerError.cannotWriteOutput
        }
        try Task.checkCancellation()
        try stagedFile.commit()
    }

    private struct StagedFile {
        let destination: URL
        let destinationExists: Bool
        let replacementDirectory: URL
        let url: URL

        init(destination: URL) throws {
            let fileManager = FileManager.default
            let destinationPath = destination.path(percentEncoded: false)
            let parent = destination.deletingLastPathComponent()
            var parentIsDirectory: ObjCBool = false
            guard fileManager.fileExists(
                atPath: parent.path(percentEncoded: false),
                isDirectory: &parentIsDirectory
            ), parentIsDirectory.boolValue else {
                throw PDFwringerError.cannotWriteOutput
            }

            let destinationExists = fileManager.fileExists(atPath: destinationPath)
            if destinationExists {
                let attributes = try fileManager.attributesOfItem(atPath: destinationPath)
                guard attributes[.type] as? FileAttributeType == .typeRegular else {
                    throw PDFwringerError.cannotWriteOutput
                }
            }

            let replacementDirectory = try fileManager.url(
                for: .itemReplacementDirectory,
                in: .userDomainMask,
                appropriateFor: destinationExists ? destination : parent,
                create: true
            )
            var url = replacementDirectory.appending(component: UUID().uuidString)
            if !destination.pathExtension.isEmpty {
                url.appendPathExtension(destination.pathExtension)
            }

            self.destination = destination
            self.destinationExists = destinationExists
            self.replacementDirectory = replacementDirectory
            self.url = url
        }

        func commit() throws {
            let fileManager = FileManager.default
            if destinationExists {
                _ = try fileManager.replaceItemAt(destination, withItemAt: url)
            } else {
                try fileManager.moveItem(at: url, to: destination)
            }
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: replacementDirectory)
        }
    }

    static func cleanupLegacyTempFiles() {
        let removed = cleanupLegacyTempFiles(
            in: legacyTempDirectory,
            olderThan: Date().addingTimeInterval(-3600)
        )
        if removed > 0 {
            Log.fileIO.info("Cleaned up \(removed) legacy temp file(s)")
        }
    }

    @discardableResult
    static func cleanupLegacyTempFiles(in directory: URL, olderThan cutoff: Date) -> Int {
        let fileManager = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys)
        ) else {
            return 0
        }

        var removed = 0
        for file in contents {
            let fileExtension = file.pathExtension.lowercased()
            let stem = file.deletingPathExtension().lastPathComponent
            guard legacyTempExtensions.contains(fileExtension),
                  UUID(uuidString: stem) != nil,
                  let values = try? file.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  modified < cutoff else {
                continue
            }

            do {
                try fileManager.removeItem(at: file)
                removed += 1
            } catch {
                Log.fileIO.error(
                    "Could not remove legacy temp file: \(error.localizedDescription, privacy: .private)"
                )
            }
        }
        return removed
    }
}

/// Shared loggers for structured diagnostics.
enum Log {
    static let compress = Logger(subsystem: "com.pdfwringer.app", category: "compress")
    static let merge = Logger(subsystem: "com.pdfwringer.app", category: "merge")
    static let split = Logger(subsystem: "com.pdfwringer.app", category: "split")
    static let rotate = Logger(subsystem: "com.pdfwringer.app", category: "rotate")
    static let metadata = Logger(subsystem: "com.pdfwringer.app", category: "metadata")
    static let crop = Logger(subsystem: "com.pdfwringer.app", category: "crop")
    static let colorAdjust = Logger(subsystem: "com.pdfwringer.app", category: "colorAdjust")
    static let app = Logger(subsystem: "com.pdfwringer.app", category: "app")
    static let fileIO = Logger(subsystem: "com.pdfwringer.app", category: "fileIO")
}

extension Color {
    static let coral = Color(red: 0.91, green: 0.39, blue: 0.30)
}

/// Saves a PDFDocument to a user-chosen destination via AtomicFileWriter.
/// Returns (message, isError, outputURL) for use in result message display.
@MainActor
enum DocumentSaver {
    struct Result {
        var message: String
        var isError: Bool
        var outputURL: URL?
    }

    static func save(document: PDFDocument, source: URL, to destination: URL) -> Result {
        guard !FileSystemIdentity.representsSameFile(source, destination) else {
            return Result(
                message: PDFwringerError.sourceEqualsDestination.localizedDescription,
                isError: true,
                outputURL: nil
            )
        }
        guard !document.isLocked else {
            return Result(
                message: PDFwringerError.documentIsLocked.localizedDescription,
                isError: true,
                outputURL: nil
            )
        }
        let expectedPageCount = document.pageCount
        guard expectedPageCount > 0,
              let data = document.dataRepresentation(),
              !data.isEmpty else {
            return Result(message: "Failed to serialize document.", isError: true, outputURL: nil)
        }

        do {
            try AtomicFileWriter.write(to: destination) { tempURL in
                try data.write(to: tempURL)
                guard let output = PDFDocument(url: tempURL) else { return false }
                if output.isLocked {
                    return document.isEncrypted && output.isEncrypted
                }
                guard output.pageCount == expectedPageCount else { return false }
                return (0..<expectedPageCount).allSatisfy { output.page(at: $0) != nil }
            }
            return Result(message: "Saved.", isError: false, outputURL: destination)
        } catch {
            return Result(message: error.localizedDescription, isError: true, outputURL: nil)
        }
    }
}
