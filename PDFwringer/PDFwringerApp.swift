import SwiftUI
import PDFKit

@main
struct PDFwringerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appVM = AppViewModel()
    @AppStorage("appearance") private var appearance: AppAppearance = .system

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(appVM: appVM)
                .navigationTitle(appVM.windowTitle)
                .preferredColorScheme(appearance.colorScheme)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 800, height: 520)
        .commands {
            // File menu
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    guard let urls = FileDialogHelper.showOpenPanel(allowsMultiple: true) else { return }
                    appVM.handleDrop(urls)
                }
                .keyboardShortcut("o")

                Menu("Open Recent") {
                    ForEach(appVM.recentDocuments, id: \.self) { url in
                        Button(url.lastPathComponent) {
                            appVM.handleDrop([url])
                        }
                    }
                    if !appVM.recentDocuments.isEmpty {
                        Divider()
                        Button("Clear Menu") {
                            appVM.clearRecentDocuments()
                        }
                    }
                }

                Divider()

                Button("Close") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut("w")
            }

            // View menu
            CommandMenu("View") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }

            // Navigate menu
            CommandMenu("Navigate") {
                Button("Next Page") {
                    appVM.nextPage()
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(!appVM.hasDocument)

                Button("Previous Page") {
                    appVM.previousPage()
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(!appVM.hasDocument)

                Divider()

                Button("First Page") {
                    appVM.goToFirstPage()
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(!appVM.hasDocument)

                Button("Last Page") {
                    appVM.goToLastPage()
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(!appVM.hasDocument)
            }

            // Actions menu
            CommandMenu("Actions") {
                Button("Compress") {
                    appVM.selectCompress()
                }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(!appVM.canSelectSingleFileAction)

                Button("Split / Extract") {
                    appVM.selectSplit()
                }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(!appVM.canSelectSingleFileAction)

                Button("Rotate Pages") {
                    appVM.selectRotate()
                }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(!appVM.canSelectSingleFileAction)

                Button("Edit Metadata") {
                    appVM.selectMetadata()
                }
                .keyboardShortcut("4", modifiers: .command)
                .disabled(!appVM.canSelectSingleFileAction)

                Button("Crop / Resize") {
                    appVM.selectCrop()
                }
                .keyboardShortcut("5", modifiers: .command)
                .disabled(!appVM.canSelectSingleFileAction)

                Button("Adjust Colors") {
                    appVM.selectAdjustColor()
                }
                .keyboardShortcut("6", modifiers: .command)
                .disabled(!appVM.canSelectSingleFileAction)

                Divider()

                Button("Merge") {
                    appVM.selectMerge()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(!appVM.canSelectMerge)

                Divider()

                Button("Go Back") {
                    appVM.goBack()
                }
                .keyboardShortcut("[")
                .disabled(!appVM.canGoBack)

                Button("Start Over") {
                    appVM.startOver()
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(appVM.state == .landing)
            }

            // Keep default Edit menu (Undo/Redo/Cut/Copy/Paste)
            // Keep default Window menu (Minimize/Zoom/Bring All to Front)
        }
    }
}

/// Handles files opened via Finder (double-click, Open With, drag to Dock icon).
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var onOpenURLs: (([URL]) -> Void)?
    var hasUnsavedChanges: (() -> Bool)?

    func application(_ application: NSApplication, open urls: [URL]) {
        onOpenURLs?(urls)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let dirty = hasUnsavedChanges?() == true ||
            sender.windows.contains(where: { $0.isDocumentEdited })
        guard dirty else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "You have unsaved changes."
        alert.informativeText = "If you quit now, your changes will be lost."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            return .terminateNow
        }
        return .terminateCancel
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
