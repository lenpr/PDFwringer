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

    var errorDescription: String? {
        switch self {
        case .cannotOpenDocument: "Cannot open the PDF document. It may be corrupted or have zero pages."
        case .documentIsLocked: "This PDF is password-protected."
        case .cannotCreateOutput: "Cannot create the output file."
        case .cannotWriteOutput: "Failed to write the output PDF."
        case .invalidPageRange(let range): "Invalid page range: '\(range)'"
        case .noSourceFile: "No source file selected."
        case .emptyFileList: "No files to process."
        case .accessDenied: "Cannot access the file. Try selecting it again."
        case .fileNotReadable(let name): "Cannot read '\(name)'. The file may have been moved or deleted."
        case .insufficientDiskSpace(let needed, let available):
            "Not enough disk space. Need \(Formatting.fileSize(needed)), only \(Formatting.fileSize(available)) available."
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
    static func write(to destination: URL, using block: (URL) throws -> Bool) throws {
        let tempURL = URL.temporaryDirectory.appending(component: UUID().uuidString + ".pdf")
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
}

/// Shared loggers for structured diagnostics.
enum Log {
    static let compress = Logger(subsystem: "com.pdfwringer.app", category: "compress")
    static let merge = Logger(subsystem: "com.pdfwringer.app", category: "merge")
    static let split = Logger(subsystem: "com.pdfwringer.app", category: "split")
    static let rotate = Logger(subsystem: "com.pdfwringer.app", category: "rotate")
    static let metadata = Logger(subsystem: "com.pdfwringer.app", category: "metadata")
}
