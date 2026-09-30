import AppKit
import UniformTypeIdentifiers

/// Wraps `NSSavePanel` and `NSOpenPanel` for PDF file selection in a sandboxed context.
/// All methods run modally and return nil if the user cancels.
@MainActor
struct FileDialogHelper {
    private(set) static var isPresentingFilePanel = false

    /// AppKit modal panels run a nested event loop. Finder Open and other app
    /// callbacks must not replace the workflow while it is choosing a destination.
    static func withFilePanel<Result>(_ present: () -> Result) -> Result? {
        guard !isPresentingFilePanel else { return nil }
        isPresentingFilePanel = true
        defer { isPresentingFilePanel = false }
        return present()
    }

    static func confirmDiscardChanges() -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Discard unsaved changes?")
        alert.informativeText = String(localized: "Your original PDF is unchanged. Edits that have not been saved will be lost.")
        alert.addButton(withTitle: String(localized: "Keep Editing"))
        alert.addButton(withTitle: String(localized: "Discard Changes"))
        alert.alertStyle = .warning
        return alert.runModal() == .alertSecondButtonReturn
    }


    /// Shows a save dialog pre-filled with a suggested filename. Returns the chosen URL or nil on cancel.
    static func showSavePanel(suggestedName: String, title: String? = nil,
                              prompt: String? = nil, message: String? = nil) -> URL? {
        let panel = NSSavePanel()
        if let title { panel.title = title }
        if let prompt { panel.prompt = prompt }
        if let message { panel.message = message }
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldLabel = "Save As:"
        guard withFilePanel({ panel.runModal() }) == .OK else { return nil }
        return panel.url
    }

    /// Shows an open dialog filtered to PDFs. Returns selected URLs or nil on cancel.
    static func showOpenPanel(allowsMultiple: Bool) -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = allowsMultiple
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.pdf]
        guard withFilePanel({ panel.runModal() }) == .OK else { return nil }
        return panel.urls
    }

    /// Shows a directory chooser for output folder selection. Returns chosen URL or nil on cancel.
    static func showDirectoryPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Output Folder"
        guard withFilePanel({ panel.runModal() }) == .OK else { return nil }
        return panel.url
    }
}
