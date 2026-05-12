import SwiftUI
import PDFKit
import OSLog

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
                Button(String(localized: "Open...")) {
                    guard let urls = FileDialogHelper.showOpenPanel(allowsMultiple: true) else { return }
                    appVM.handleDrop(urls)
                }
                .keyboardShortcut("o")

                Menu(String(localized: "Open Recent")) {
                    ForEach(appVM.recentDocuments, id: \.self) { url in
                        Button(url.lastPathComponent) {
                            let _ = BookmarkManager.accessURL(from: url)
                            appVM.handleDrop([url])
                        }
                    }
                    if !appVM.recentDocuments.isEmpty {
                        Divider()
                        Button(String(localized: "Clear Menu")) {
                            appVM.clearRecentDocuments()
                        }
                    }
                }

                Divider()

                Button(String(localized: "Close")) {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut("w")
            }

            // View menu — inject into the system-provided View menu
            CommandGroup(after: .toolbar) {
                Picker(String(localized: "Appearance"), selection: $appearance) {
                    ForEach(AppAppearance.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Divider()

                Button(String(localized: "Next Page")) {
                    appVM.nextPage()
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(!appVM.hasDocument)

                Button(String(localized: "Previous Page")) {
                    appVM.previousPage()
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(!appVM.hasDocument)

                Divider()

                Button(String(localized: "First Page")) {
                    appVM.goToFirstPage()
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(!appVM.hasDocument)

                Button(String(localized: "Last Page")) {
                    appVM.goToLastPage()
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(!appVM.hasDocument)
            }

            // Actions menu
            CommandMenu(String(localized: "Actions")) {
                Button(String(localized: "Compress")) {
                    appVM.selectCompress()
                }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(!appVM.canSelectSingleFileAction)

                Button(String(localized: "Split / Extract")) {
                    appVM.selectSplit()
                }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(!appVM.canSelectSingleFileAction)

                Button(String(localized: "Rotate Pages")) {
                    appVM.selectRotate()
                }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(!appVM.canSelectSingleFileAction)

                Button(String(localized: "Edit Metadata")) {
                    appVM.selectMetadata()
                }
                .keyboardShortcut("4", modifiers: .command)
                .disabled(!appVM.canSelectSingleFileAction)

                Button(String(localized: "Crop / Resize")) {
                    appVM.selectCrop()
                }
                .keyboardShortcut("5", modifiers: .command)
                .disabled(!appVM.canSelectSingleFileAction)

                Button(String(localized: "Adjust Colors")) {
                    appVM.selectAdjustColor()
                }
                .keyboardShortcut("6", modifiers: .command)
                .disabled(!appVM.canSelectSingleFileAction)

                Divider()

                Button(String(localized: "Merge")) {
                    appVM.selectMerge()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(!appVM.canSelectMerge)

                Divider()

                Button(String(localized: "Go Back")) {
                    appVM.goBack()
                }
                .keyboardShortcut("[")
                .disabled(!appVM.canGoBack)

                Button(String(localized: "Start Over")) {
                    appVM.startOver()
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(appVM.state == .landing)
            }

            // Help menu
            CommandGroup(replacing: .help) {
                Button(String(localized: "PDFwringer on GitHub")) {
                    NSWorkspace.shared.open(URL(string: "https://github.com/lenpr/PDFwringer")!)
                }
                Button(String(localized: "License (MIT)")) {
                    NSWorkspace.shared.open(URL(string: "https://github.com/lenpr/PDFwringer/blob/main/LICENSE")!)
                }
                Button(String(localized: "Privacy Policy")) {
                    NSWorkspace.shared.open(URL(string: "https://github.com/lenpr/PDFwringer/blob/main/PRIVACY.md")!)
                }
                Divider()
                Button(String(localized: "Show Logs")) {
                    AppDelegate.openLogDirectory()
                }
            }
        }
    }
}

/// Handles files opened via Finder (double-click, Open With, drag to Dock icon).
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var onOpenURLs: (([URL]) -> Void)?
    var hasUnsavedChanges: (() -> Bool)?

    private static let logDirectory: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs/PDFwringer")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("PDFwringer launched, version=\(appVersion)")
        AtomicFileWriter.cleanupStaleFiles()
        installCrashHandler()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        onOpenURLs?(urls)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let dirty = hasUnsavedChanges?() == true ||
            sender.windows.contains(where: { $0.isDocumentEdited })
        guard dirty else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = String(localized: "You have unsaved changes.")
        alert.informativeText = String(localized: "If you quit now, your changes will be lost.")
        alert.addButton(withTitle: String(localized: "Quit"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            return .terminateNow
        }
        return .terminateCancel
    }

    static func openLogDirectory() {
        NSWorkspace.shared.open(logDirectory)
    }

    private func installCrashHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let logFile = AppDelegate.logDirectory.appending(component: "crash.log")
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

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
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
