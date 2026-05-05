import AppKit
import UniformTypeIdentifiers

/// Wraps `NSSavePanel` and `NSOpenPanel` for PDF file selection in a sandboxed context.
/// All methods run modally and return nil if the user cancels.
@MainActor
struct FileDialogHelper {

    /// Shows a save dialog pre-filled with a suggested filename. Returns the chosen URL or nil on cancel.
    static func showSavePanel(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldLabel = "Save As:"
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// Shows an open dialog filtered to PDFs. Returns selected URLs or nil on cancel.
    static func showOpenPanel(allowsMultiple: Bool) -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = allowsMultiple
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK else { return nil }
        return panel.urls
    }

    /// Shows a directory chooser for output folder selection. Returns chosen URL or nil on cancel.
    static func showDirectoryPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Output Folder"
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
