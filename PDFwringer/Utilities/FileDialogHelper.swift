import AppKit
import UniformTypeIdentifiers

@MainActor
struct FileDialogHelper {

    static func showSavePanel(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
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
