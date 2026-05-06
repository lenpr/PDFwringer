import Foundation
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
