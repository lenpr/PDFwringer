import SwiftUI
import PDFKit
import OSLog

@main
struct PDFwringerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appVM = AppViewModel()
    @AppStorage("appearance") private var appearance: AppAppearance = .system

    var body: some Scene {
        WindowGroup {
            ContentView(appVM: appVM, appDelegate: appDelegate)
                .navigationTitle(appVM.windowTitle)
                .preferredColorScheme(appearance.colorScheme)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 800, height: 520)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(String(localized: "About PDFwringer")) {
                    // Let AppKit read the marketing version from the bundle;
                    // suppress its optional parenthesized internal build number.
                    NSApp.orderFrontStandardAboutPanel(options: [.version: ""])
                }
            }
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
                            appVM.openRecentDocument(url)
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
                    NSApp.keyWindow?.performClose(nil)
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
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(!appVM.hasDocument)

                Button(String(localized: "Previous Page")) {
                    appVM.previousPage()
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(!appVM.hasDocument)

                Divider()

                Button(String(localized: "First Page")) {
                    appVM.goToFirstPage()
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option, .shift])
                .disabled(!appVM.hasDocument)

                Button(String(localized: "Last Page")) {
                    appVM.goToLastPage()
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option, .shift])
                .disabled(!appVM.hasDocument)
            }

            // Actions menu
            CommandMenu(String(localized: "Actions")) {
                Button(String(localized: "Compress")) {
                    appVM.selectCompress()
                }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(!appVM.canSelectSingleFileAction)

                Button(String(localized: "Merge PDFs")) { appVM.selectMerge() }
                    .disabled(!appVM.canSelectSingleFileAction)

                Button(String(localized: "Split / Extract")) {
                    appVM.selectSplit()
                }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(!appVM.canSelectSingleFileAction)

                Button(String(localized: "Reorder Pages")) { appVM.selectReorderPages() }
                    .disabled(!appVM.canSelectSingleFileAction)

                Button(String(localized: "Rotate Pages")) {
                    appVM.selectRotate()
                }
                .keyboardShortcut("3", modifiers: .command)
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

                Button(String(localized: "Export as Images")) { appVM.selectExportImages() }
                    .disabled(!appVM.canSelectSingleFileAction)

                Button(String(localized: "Edit Metadata")) {
                    appVM.selectMetadata()
                }
                .keyboardShortcut("4", modifiers: .command)
                .disabled(!appVM.canSelectSingleFileAction)

                Divider()

                Button(String(localized: "Go Back")) {
                    appVM.goBack()
                }
                .keyboardShortcut("[")
                .disabled(!appVM.canGoBack)

                Button(appVM.hasDocument ? String(localized: "Close File") : String(localized: "Close Files")) {
                    appVM.confirmStartOver()
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(appVM.isLanding)
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
                Button(String(localized: "Open Console")) {
                    AppDelegate.openDiagnostics()
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
