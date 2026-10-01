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
    case destinationChanged
    case passwordRequiresFlattening
    case outputPasswordRequired
    case protectionPreservationFailed
    case existingPasswordRequired
    case unsupportedEncryption
    case invalidEncryptionPassword
    case annotationRemovalFailed
    case metadataVerificationFailed
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

    /// Keep domain-specific explanations; make common filesystem failures actionable.
    static func userMessage(for error: Error) -> String {
        guard let cocoa = error as? CocoaError else { return error.localizedDescription }
        switch cocoa.code {
        case .fileWriteNoPermission:
            return String(localized: "Cannot save in this location. Choose a folder you can write to, or select the destination again.")
        case .fileReadNoPermission:
            return String(localized: "Cannot read this file. Select it again to grant access, or check its permissions in Finder.")
        case .fileWriteOutOfSpace:
            return String(localized: "There is not enough free space to save the output. Free space on the destination disk or choose another disk, then try again.")
        case .fileWriteVolumeReadOnly:
            return String(localized: "The destination disk is read-only. Choose a writable disk or folder.")
        case .fileWriteFileExists:
            return String(localized: "A file already exists at this destination. Choose another name, or select the existing file again to confirm replacement.")
        case .fileNoSuchFile, .fileReadNoSuchFile:
            return String(localized: "A required file or folder is no longer available. Reconnect the disk if needed, then select the file and destination again.")
        default:
            return error.localizedDescription
        }
    }

    var errorDescription: String? {
        switch self {
        case .cannotOpenDocument: String(localized: "Cannot open the PDF document. It may be corrupted or have zero pages.")
        case .documentIsLocked: String(localized: "This PDF is password-protected.")
        case .cannotCreateOutput: String(localized: "Cannot create the output file.")
        case .cannotWriteOutput: String(localized: "Failed to write the output file.")
        case .destinationChanged:
            String(localized: "The destination changed while this file was being prepared. Save again with a different name, or reselect the file you want to replace.")
        case .passwordRequiresFlattening:
            String(localized: "New password protection requires explicitly flattening this PDF. Flattening turns pages into images and removes searchable text. Existing protection can be retained without flattening.")
        case .outputPasswordRequired:
            String(localized: "Enter a password for the flattened copy, or explicitly choose Remove protection.")
        case .protectionPreservationFailed:
            String(localized: "PDFKit could not retain this document's password protection and permissions. No output was replaced. To create an unprotected copy, explicitly choose Remove protection in Edit Metadata.")
        case .existingPasswordRequired:
            String(localized: "Enter the document's current password to verify the saved copy. Its existing protection will be retained.")
        case .unsupportedEncryption:
            String(localized: "The output did not use the required AES-128 encryption. No output was replaced.")
        case .invalidEncryptionPassword:
            String(localized: "Use 1–32 printable ASCII characters for a new PDF password. Longer or non-ASCII passwords are not supported by the PDF writer.")
        case .annotationRemovalFailed:
            String(localized: "PDFKit could not remove all annotations from this PDF. No output was replaced. You can explicitly flatten annotations to preserve their visible appearance instead.")
        case .metadataVerificationFailed:
            String(localized: "The requested metadata could not be verified in the saved PDF. No output was replaced. Try a different PDF or explicitly flatten the document.")
        case .invalidPageRange(let range): String(localized: "Invalid page range: '\(range)'")
        case .invalidPageOrder: String(localized: "The page order is incomplete or invalid.")
        case .noSourceFile: String(localized: "No source file selected.")
        case .emptyFileList: String(localized: "No files to process.")
        case .accessDenied: String(localized: "Cannot access the file. Try selecting it again.")
        case .fileNotReadable(let name): String(localized: "Cannot read '\(name)'. It may be damaged, password-protected, moved, or unavailable. Open it individually to check.")
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

    /// Formats untrusted PDF page geometry without trapping on values that
    /// cannot be represented as integers.
    static func pageTooltip(pageNumber: Int, cropBox: CGRect) -> String {
        let width = cropBox.width
        let height = cropBox.height
        guard width.isFinite,
              height.isFinite,
              width >= 0,
              height >= 0,
              width < CGFloat(Int.max),
              height < CGFloat(Int.max) else {
            return "Page \(pageNumber)"
        }
        return "Page \(pageNumber) — \(Int(width)) × \(Int(height)) pt"
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

    /// A destination-volume write that may be retained for review before commit.
    /// The destination identity is captured at creation, not at the later save.
    /// This immutable handle can cross actors. Await its writer before cleanup;
    /// filesystem publication/cleanup must remain sequenced by the owner.
    final class StagedFile: Sendable {
        let destination: URL
        let destinationExists: Bool
        let destinationIdentity: FileSystemIdentity.Identity?
        let replacementDirectory: URL
        let url: URL

        deinit { cleanup() }

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

            let destinationIdentity = FileSystemIdentity.entryIdentity(at: destination)
            guard !destinationExists || destinationIdentity != nil else {
                throw PDFwringerError.destinationChanged
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
            self.destinationIdentity = destinationIdentity
            self.replacementDirectory = replacementDirectory
            self.url = url
        }

        func commit() throws {
            try Task.checkCancellation()
            let fileManager = FileManager.default
            if destinationExists {
                // A save can yield while preparing its output. Do not replace a
                // different file installed by another save during that interval.
                guard let destinationIdentity,
                      FileSystemIdentity.entryIdentity(at: destination) == destinationIdentity else {
                    throw PDFwringerError.destinationChanged
                }
                _ = try fileManager.replaceItemAt(destination, withItemAt: url)
            } else {
                guard try ExclusiveFilePublisher.renameExclusively(from: url, to: destination) else {
                    throw PDFwringerError.destinationChanged
                }
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
    // Text-bearing controls need a darker accent on light backgrounds.
    static let coral = Color(nsColor: NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? NSColor(red: 0.91, green: 0.39, blue: 0.30, alpha: 1)
                    : NSColor(red: 0.70, green: 0.20, blue: 0.14, alpha: 1)
    })
    // Native prominent buttons and segmented selections use white labels.
    static let coralFill = Color(red: 0.78, green: 0.25, blue: 0.19)
    static let coralText = Color(nsColor: NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? NSColor(red: 0.98, green: 0.57, blue: 0.46, alpha: 1)
                    : NSColor(red: 0.70, green: 0.20, blue: 0.14, alpha: 1)
    })
}

/// Saves a PDFDocument to a user-chosen destination via AtomicFileWriter.
/// Returns (message, isError, outputURL) for use in result message display.
@MainActor
enum DocumentSaver {
    struct Result: Sendable {
        var message: String
        var isError: Bool
        var outputURL: URL?
    }

    static func save(document: PDFDocument, source: URL, to destination: URL) async -> Result {
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
        let sourceWasEncrypted = document.isEncrypted
        let sourcePermissions = UInt(document.accessPermissions.rawValue)
        do {
            try Task.checkCancellation()
            let staged = try AtomicFileWriter.StagedFile(destination: destination)
            defer { staged.cleanup() }
            await Task.yield()
            try Task.checkCancellation()
            guard expectedPageCount > 0,
                  let data = document.dataRepresentation(), !data.isEmpty else {
                throw PDFwringerError.cannotWriteOutput
            }
            let worker = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                try data.write(to: staged.url)
                try Task.checkCancellation()
                guard let output = PDFDocument(url: staged.url) else {
                    throw PDFwringerError.cannotWriteOutput
                }
                try PDFEncryptionPolicy.requirePreservedProtection(
                    sourceIsEncrypted: sourceWasEncrypted,
                    sourcePermissions: sourcePermissions, in: output
                )
                if output.isLocked {
                    guard sourceWasEncrypted && output.isEncrypted else {
                        throw PDFwringerError.cannotWriteOutput
                    }
                } else {
                    guard output.pageCount == expectedPageCount else {
                        throw PDFwringerError.cannotWriteOutput
                    }
                    for index in 0..<expectedPageCount {
                        try Task.checkCancellation()
                        guard output.page(at: index) != nil else {
                            throw PDFwringerError.cannotWriteOutput
                        }
                    }
                }
                try FileSystemIdentity.requireDistinct(source, destination)
                try staged.commit()
            }
            try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: { worker.cancel() }
            return Result(message: "Saved.", isError: false, outputURL: destination)
        } catch is CancellationError {
            return Result(message: "Cancelled.", isError: false, outputURL: nil)
        } catch {
            return Result(message: PDFwringerError.userMessage(for: error), isError: true, outputURL: nil)
        }
    }
}
