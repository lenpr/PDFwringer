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

    private static let crashLogDirectory: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs/PDFwringer")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("PDFwringer launched, version=\(appVersion)")
        AtomicFileWriter.cleanupLegacyTempFiles()
        installCrashHandler()
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

    static func openCrashLogDirectory() {
        NSWorkspace.shared.open(crashLogDirectory)
    }

    private func installCrashHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let logFile = AppDelegate.crashLogDirectory.appending(component: "crash.log")
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let info = """
            --- Crash at \(timestamp) ---
            \(exception.name.rawValue): \(exception.reason ?? "unknown")
            Stack trace:
            \(exception.callStackSymbols.joined(separator: "\n"))

            """
            if let data = info.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logFile.path(percentEncoded: false)) {
                    if let handle = try? FileHandle(forWritingTo: logFile) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        handle.closeFile()
                    }
                } else {
                    try? data.write(to: logFile)
                }
            }
        }
    }
}
