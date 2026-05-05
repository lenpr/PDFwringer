import AppKit
import UniformTypeIdentifiers

/// Wraps `NSSavePanel` and `NSOpenPanel` for PDF file selection in a sandboxed context.
@MainActor
struct FileDialogHelper {

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

    static func showOpenPanel(allowsMultiple: Bool) -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = allowsMultiple
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK else { return nil }
        return panel.urls
    }

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
