import Foundation
import OSLog
import SwiftUI

/// Domain-specific errors surfaced to users via `LocalizedError`.
enum PDFwringerError: LocalizedError {
    case cannotOpenDocument
    case documentIsLocked
    case cannotCreateOutput
    case cannotWriteOutput
    case invalidPageRange(String)
    case noSourceFile
    case emptyFileList
    case accessDenied
    case fileNotReadable(String)
    case insufficientDiskSpace(needed: Int64, available: Int64)
    case sourceEqualsDestination

    var errorDescription: String? {
        switch self {
        case .cannotOpenDocument: String(localized: "Cannot open the PDF document. It may be corrupted or have zero pages.")
        case .documentIsLocked: String(localized: "This PDF is password-protected.")
        case .cannotCreateOutput: String(localized: "Cannot create the output file.")
        case .cannotWriteOutput: String(localized: "Failed to write the output PDF.")
        case .invalidPageRange(let range): String(localized: "Invalid page range: '\(range)'")
        case .noSourceFile: String(localized: "No source file selected.")
        case .emptyFileList: String(localized: "No files to process.")
        case .accessDenied: String(localized: "Cannot access the file. Try selecting it again.")
        case .fileNotReadable(let name): String(localized: "Cannot read '\(name)'. The file may have been moved or deleted.")
        case .insufficientDiskSpace(let needed, let available):
            String(localized: "Not enough disk space. Need \(Formatting.fileSize(needed)), only \(Formatting.fileSize(available)) available.")
        case .sourceEqualsDestination:
            String(localized: "Source and destination cannot be the same file. Choose a different location.")
        }
    }
}

/// Shared formatting utilities for the app.
enum Formatting {
    private static let fileSizeFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    /// Formats a byte count as a human-readable file size string (e.g. "1.2 MB").
    static func fileSize(_ bytes: Int64) -> String {
        fileSizeFormatter.string(fromByteCount: bytes)
    }

    /// Returns available disk space at the given URL's volume, or nil if unavailable.
    static func availableDiskSpace(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
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
    static let tempDirectory: URL = {
        let dir = URL.temporaryDirectory.appending(component: "PDFwringer")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func write(to destination: URL, using block: (URL) throws -> Bool) throws {
        let tempURL = tempDirectory.appending(component: UUID().uuidString + ".pdf")
        Log.fileIO.debug("AtomicWrite: temp=\(tempURL.lastPathComponent) → \(destination.lastPathComponent)")
        let success = try block(tempURL)
        guard success else {
            try? FileManager.default.removeItem(at: tempURL)
            throw PDFwringerError.cannotWriteOutput
        }
        do {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }

    static func cleanupStaleFiles() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: [.creationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-3600)
        var removed = 0
        for file in contents {
            guard let attrs = try? file.resourceValues(forKeys: [.creationDateKey]),
                  let created = attrs.creationDate,
                  created < cutoff else { continue }
            try? fm.removeItem(at: file)
            removed += 1
        }
        if removed > 0 {
            Log.fileIO.info("Cleaned up \(removed) stale temp file(s)")
        }
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
