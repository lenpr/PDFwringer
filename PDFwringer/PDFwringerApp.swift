import SwiftUI

@main
struct PDFwringerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 720, height: 480)
    }
}
