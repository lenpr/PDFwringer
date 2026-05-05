import SwiftUI
import PDFKit

@main
struct PDFwringerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appVM = AppViewModel()

    init() {
        // Required when launching as a bare executable (make run) so the app gets its own
        // menu bar, Dock icon, and keyboard focus instead of inheriting Terminal's.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(appVM: appVM)
                .navigationTitle(appVM.windowTitle)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 800, height: 520)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    guard let urls = FileDialogHelper.showOpenPanel(allowsMultiple: true) else { return }
                    appVM.handleDrop(urls)
                }
                .keyboardShortcut("o")
            }
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
