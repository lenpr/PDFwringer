import SwiftUI
import PDFKit

@main
struct PDFwringerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appVM = AppViewModel()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(appVM: appVM)
                .navigationTitle(appVM.windowTitle)
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

    func application(_ application: NSApplication, open urls: [URL]) {
        onOpenURLs?(urls)
    }
}
