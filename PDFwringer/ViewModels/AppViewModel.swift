import AppKit
import Foundation
import OSLog
import PDFKit
import SwiftUI

/// Top-level navigation state machine. Each case represents a distinct screen in the app.
/// Transitions: landing → singleFile/multiFile → action screen → (back).
enum AppState: Equatable {
    case landing
    case singleFile(URL, PDFDocument)
    case multiFile([PDFFileItem])
    case compressing(URL, PDFDocument)
    case splitting(URL, PDFDocument)
    case merging([PDFFileItem])
    case rotating(URL, PDFDocument)
    case editingMetadata(URL, PDFDocument)
    case cropping(URL, PDFDocument)
    case adjustingColor(URL, PDFDocument)
    case addingPageNumbers(URL, PDFDocument)
    case exportingImages(URL, PDFDocument)
    case reorderingPages(URL, PDFDocument)

    // PDFDocument doesn't conform to Equatable; compare by URL/item identity only.
    static func == (lhs: AppState, rhs: AppState) -> Bool {
        switch (lhs, rhs) {
        case (.landing, .landing): true
        case (.singleFile(let a, _), .singleFile(let b, _)): a == b
        case (.multiFile(let a), .multiFile(let b)): a.map(\.id) == b.map(\.id)
        case (.compressing(let a, _), .compressing(let b, _)): a == b
        case (.splitting(let a, _), .splitting(let b, _)): a == b
        case (.merging(let a), .merging(let b)): a.map(\.id) == b.map(\.id)
        case (.rotating(let a, _), .rotating(let b, _)): a == b
        case (.editingMetadata(let a, _), .editingMetadata(let b, _)): a == b
        case (.cropping(let a, _), .cropping(let b, _)): a == b
        case (.adjustingColor(let a, _), .adjustingColor(let b, _)): a == b
        case (.addingPageNumbers(let a, _), .addingPageNumbers(let b, _)): a == b
        case (.exportingImages(let a, _), .exportingImages(let b, _)): a == b
        case (.reorderingPages(let a, _), .reorderingPages(let b, _)): a == b
        default: false
        }
    }
}

/// Orchestrates top-level navigation and file loading. Owned by the App scene, shared with ContentView.
@MainActor @Observable
class AppViewModel {
    var state: AppState = .landing
    var currentPage: Int = 0
    var currentFileSize: Int64 = 0
    var navigationDirection: Edge = .trailing

    // Error alert state
    var showErrorAlert = false
    var errorMessage = ""

    // Start-over confirmation state
    var showStartOverConfirm = false

    // Dirty state: set when user makes unsaved mutations (rotations, metadata edits)
    var hasUnsavedChanges = false

    // Password prompt state
    var showPasswordPrompt = false
    var passwordText = ""
    var wrongPasswordAttempt = false
    private var pendingLockedURL: URL?

    var windowTitle: String {
        switch state {
        case .landing:
            return "PDFwringer"
        case .singleFile(let url, _), .compressing(let url, _), .splitting(let url, _),
             .rotating(let url, _), .editingMetadata(let url, _), .cropping(let url, _),
             .adjustingColor(let url, _), .addingPageNumbers(let url, _),
             .exportingImages(let url, _), .reorderingPages(let url, _):
            return url.lastPathComponent
        case .multiFile(let items), .merging(let items):
            return "\(items.count) files"
        }
    }

    var canSelectSingleFileAction: Bool {
        if case .singleFile = state { return true }
        return false
    }

    var canSelectMerge: Bool {
        if case .multiFile = state { return true }
        return false
    }

    var canGoBack: Bool {
        switch state {
        case .compressing, .splitting, .rotating, .editingMetadata, .merging, .cropping, .adjustingColor:
            return true
        default:
            return false
        }
    }

    var currentPageCount: Int {
        switch state {
        case .singleFile(_, let doc), .compressing(_, let doc), .splitting(_, let doc),
             .rotating(_, let doc), .editingMetadata(_, let doc), .cropping(_, let doc),
             .adjustingColor(_, let doc):
            return doc.pageCount
        default:
            return 0
        }
    }

    var hasDocument: Bool { currentPageCount > 0 }

    func nextPage() { if currentPage < currentPageCount - 1 { currentPage += 1 } }
    func previousPage() { if currentPage > 0 { currentPage -= 1 } }
    func goToFirstPage() { currentPage = 0 }
    func goToLastPage() { currentPage = max(0, currentPageCount - 1) }

    var recentDocuments: [URL] {
        BookmarkManager.resolveBookmarks()
    }

    func clearRecentDocuments() {
        NSDocumentController.shared.clearRecentDocuments(nil)
        BookmarkManager.clearAll()
    }

    func handleDrop(_ urls: [URL]) {
        let pdfURLs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        let imageURLs = PDFImageConverter.imageFiles(from: urls)

        // If only images were dropped, offer to convert them
        if pdfURLs.isEmpty && !imageURLs.isEmpty {
            convertImagesToPDF(imageURLs)
            return
        }

        guard !pdfURLs.isEmpty else { return }

        if pdfURLs.count == 1 {
            loadSingleFile(pdfURLs[0])
        } else {
            loadMultipleFiles(pdfURLs)
        }
    }

    func loadSingleFile(_ url: URL) {
        guard let doc = PDFDocument(url: url) else {
            Log.app.warning("Cannot open file: \(url.lastPathComponent, privacy: .private)")
            errorMessage = "Cannot open '\(url.lastPathComponent)'. The file may be corrupted or not a valid PDF."
            showErrorAlert = true
            return
        }
        if doc.isLocked {
            pendingLockedURL = url
            passwordText = ""
            showPasswordPrompt = true
            return
        }
        currentPage = 0
        currentFileSize = (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? Int64) ?? 0
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        BookmarkManager.saveBookmark(for: url)
        state = .singleFile(url, doc)
    }

    func unlockDocument() {
        defer {
            passwordText = ""
        }
        guard let url = pendingLockedURL,
              let doc = PDFDocument(url: url) else {
            pendingLockedURL = nil
            return
        }
        if doc.unlock(withPassword: passwordText) {
            currentPage = 0
            currentFileSize = (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? Int64) ?? 0
            state = .singleFile(url, doc)
            pendingLockedURL = nil
            wrongPasswordAttempt = false
            showPasswordPrompt = false
        } else {
            passwordText = ""
            wrongPasswordAttempt = true
            showPasswordPrompt = true
        }
    }

    func cancelPassword() {
        pendingLockedURL = nil
        passwordText = ""
        wrongPasswordAttempt = false
    }

    func loadMultipleFiles(_ urls: [URL]) {
        let items = PDFFileItem.from(urls: urls)
        guard !items.isEmpty else { return }
        for item in items {
            NSDocumentController.shared.noteNewRecentDocumentURL(item.url)
            BookmarkManager.saveBookmark(for: item.url)
        }
        state = .multiFile(items)
    }

    func selectCompress() {
        guard case .singleFile(let url, let doc) = state else { return }
        navigationDirection = .trailing
        state = .compressing(url, doc)
    }

    func selectSplit() {
        guard case .singleFile(let url, let doc) = state else { return }
        navigationDirection = .trailing
        state = .splitting(url, doc)
    }

    func selectMerge() {
        guard case .multiFile(let items) = state else { return }
        navigationDirection = .trailing
        state = .merging(items)
    }

    func selectRotate() {
        guard case .singleFile(let url, let doc) = state else { return }
        navigationDirection = .trailing
        state = .rotating(url, doc)
    }

    func selectMetadata() {
        guard case .singleFile(let url, let doc) = state else { return }
        navigationDirection = .trailing
        state = .editingMetadata(url, doc)
    }

    func selectCrop() {
        guard case .singleFile(let url, let doc) = state else { return }
        navigationDirection = .trailing
        state = .cropping(url, doc)
    }

    func selectAdjustColor() {
        guard case .singleFile(let url, let doc) = state else { return }
        navigationDirection = .trailing
        state = .adjustingColor(url, doc)
    }

    func selectPageNumbers() {
        guard case .singleFile(let url, let doc) = state else { return }
        navigationDirection = .trailing
        state = .addingPageNumbers(url, doc)
    }

    func selectExportImages() {
        guard case .singleFile(let url, let doc) = state else { return }
        navigationDirection = .trailing
        state = .exportingImages(url, doc)
    }

    func selectReorderPages() {
        guard case .singleFile(let url, let doc) = state else { return }
        navigationDirection = .trailing
        state = .reorderingPages(url, doc)
    }

    func goBack() {
        navigationDirection = .leading
        switch state {
        case .compressing(let url, let doc), .splitting(let url, let doc),
             .rotating(let url, let doc), .editingMetadata(let url, let doc),
             .cropping(let url, let doc), .adjustingColor(let url, let doc),
             .addingPageNumbers(let url, let doc), .exportingImages(let url, let doc),
             .reorderingPages(let url, let doc):
            state = .singleFile(url, doc)
        case .merging(let items):
            state = .multiFile(items)
        default:
            break
        }
        hasUnsavedChanges = false
    }

    func confirmStartOver() {
        showStartOverConfirm = true
    }

    func startOver() {
        state = .landing
        hasUnsavedChanges = false
    }

    // MARK: - Image to PDF

    func convertImagesToPDF(_ imageURLs: [URL]) {
        guard let destination = FileDialogHelper.showSavePanel(suggestedName: "converted.pdf") else { return }

        Task {
            do {
                let converter = PDFImageConverter()
                try await converter.convert(images: imageURLs, destination: destination, progress: { _ in })
                loadSingleFile(destination)
            } catch {
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }
}
