import AppKit
import OSLog

let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

/// Handles files opened via Finder (double-click, Open With, drag to Dock icon).
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var onOpenURLs: (([URL]) -> Void)? {
        didSet { deliverPendingOpenURLs() }
    }
    private weak var viewModel: AppViewModel?

    func configure(with viewModel: AppViewModel) {
        self.viewModel = viewModel
        onOpenURLs = { [weak viewModel] urls in viewModel?.handleDrop(urls) }
    }
    private var pendingOpenURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("PDFwringer launched, version=\(appVersion)")
        AtomicFileWriter.cleanupLegacyTempFiles()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let onOpenURLs else {
            pendingOpenURLs.append(contentsOf: urls)
            return
        }
        onOpenURLs(urls)
    }

    private func deliverPendingOpenURLs() {
        guard let onOpenURLs, !pendingOpenURLs.isEmpty else { return }
        let urls = pendingOpenURLs
        pendingOpenURLs.removeAll()
        onOpenURLs(urls)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        viewModel?.canLeaveWorkflow() == false ? .terminateCancel : .terminateNow
    }

    /// Let macOS collect crashes; avoid allocating, formatting, or writing files
    /// from an uncaught-exception handler in an already failing process.
    static func openDiagnostics() {
        guard let consoleURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Console"),
              NSWorkspace.shared.open(consoleURL) else {
            let alert = NSAlert()
            alert.messageText = String(localized: "Could not open Console")
            alert.informativeText = String(localized: "Open Console from Applications > Utilities to inspect PDFwringer's diagnostic and crash reports.")
            alert.runModal()
            return
        }
    }
}
