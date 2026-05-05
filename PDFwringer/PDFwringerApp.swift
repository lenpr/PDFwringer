import SwiftUI

@main
struct PDFwringerApp: App {

    init() {
        // Required when launching as a bare executable (make run) so the app gets its own
        // menu bar, Dock icon, and keyboard focus instead of inheriting Terminal's.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 800, height: 520)
    }
}
