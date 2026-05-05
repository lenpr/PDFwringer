import Foundation

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
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cannotOpenDocument: "Cannot open the PDF document. It may be corrupted."
        case .documentIsLocked: "This PDF is password-protected."
        case .cannotCreateOutput: "Cannot create the output file."
        case .cannotWriteOutput: "Failed to write the output PDF."
        case .invalidPageRange(let range): "Invalid page range: '\(range)'"
        case .noSourceFile: "No source file selected."
        case .emptyFileList: "No files to process."
        case .accessDenied: "Cannot access the file. Try selecting it again."
        case .cancelled: "Operation was cancelled."
        }
    }
}

/// Shared formatting utilities for the app.
enum Formatting {
    /// Formats a byte count as a human-readable file size string (e.g. "1.2 MB").
    static func fileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
