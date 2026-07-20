import AppKit
import Foundation
import OSLog
import PDFKit
import SwiftUI

/// Top-level navigation state machine. Each case represents a distinct screen in the app.
/// Transitions: landing → singleFile → action screen → (back), or landing → merging → (back).
enum AppState {
    case landing
    case singleFile(URL, PDFDocument)
    case compressing(URL, PDFDocument)
    case splitting(URL, PDFDocument)
    case merging([PDFFileItem])
    case rotating(URL, source: PDFDocument, working: PDFDocument)
    case editingMetadata(URL, PDFDocument)
    case cropping(URL, source: PDFDocument, working: PDFDocument)
    case adjustingColor(URL, PDFDocument)
    case exportingImages(URL, PDFDocument)
    case reorderingPages(URL, PDFDocument)
}

/// Orchestrates top-level navigation and file loading. Owned by the App scene, shared with ContentView.
@MainActor @Observable
class AppViewModel {
    var state: AppState = .landing {
        didSet { cancelPendingIntake() }
    }
    var currentPage: Int = 0
    var currentFileSize: Int64 = 0
    var navigationDirection: Edge = .trailing

    // Error alert state
    var showErrorAlert = false
    var errorMessage = ""

    // Start-over confirmation state
    var showStartOverConfirm = false

    // Dirty state: set only for unsaved mutations to an isolated working document.
    var hasUnsavedChanges = false

    // Password prompt state
    var showPasswordPrompt = false
    var passwordText = ""
    var wrongPasswordAttempt = false
    private var pendingLockedURL: URL?
    private var fileIntakeTask: Task<Void, Never>?
    private var fileIntakeID: UUID?

    var windowTitle: String {
        switch state {
        case .landing:
            return "PDFwringer"
        case .singleFile(let url, _), .compressing(let url, _), .splitting(let url, _),
             .editingMetadata(let url, _), .adjustingColor(let url, _),
             .exportingImages(let url, _), .reorderingPages(let url, _):
            return "PDFwringer — \(url.lastPathComponent)"
        case .rotating(let url, _, _), .cropping(let url, _, _):
            return "PDFwringer — \(url.lastPathComponent)"
        case .merging(let items):
            return "PDFwringer — \(items.count) files"
        }
    }

    var isLanding: Bool {
        if case .landing = state { return true }
        return false
    }

    var canSelectSingleFileAction: Bool {
        if case .singleFile = state { return true }
        return false
    }

    var canGoBack: Bool {
        switch state {
        case .compressing, .splitting, .rotating, .editingMetadata, .merging, .cropping,
             .adjustingColor, .exportingImages, .reorderingPages:
            return true
        default:
            return false
        }
    }

    var currentPageCount: Int {
        switch state {
        case .singleFile(_, let doc), .compressing(_, let doc), .splitting(_, let doc),
             .editingMetadata(_, let doc), .adjustingColor(_, let doc),
             .exportingImages(_, let doc):
            return doc.pageCount
        case .rotating(_, _, let working), .cropping(_, _, let working):
            return working.pageCount
        default:
            return 0
        }
    }

    var hasDocument: Bool { currentPageCount > 0 }

    func nextPage() { if currentPage < currentPageCount - 1 { currentPage += 1 } }
    func previousPage() { if currentPage > 0 { currentPage -= 1 } }
    func goToFirstPage() { currentPage = 0 }
    func goToLastPage() { currentPage = max(0, currentPageCount - 1) }

    var recentDocuments: [URL] = []

    func refreshRecentDocuments() {
        recentDocuments = BookmarkManager.resolveBookmarks()
    }

    func clearRecentDocuments() {
        NSDocumentController.shared.clearRecentDocuments(nil)
        BookmarkManager.clearAll()
        recentDocuments = []
    }

    func handleDrop(_ urls: [URL]) {
        let pdfURLs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        guard !pdfURLs.isEmpty else { return }

        if pdfURLs.count == 1 {
            loadSingleFile(pdfURLs[0])
        } else {
            loadMultipleFiles(pdfURLs)
        }
    }

    func loadSingleFile(_ url: URL) {
        cancelPendingIntake()
        guard let doc = PDFDocument(url: url) else {
            Log.app.warning("Cannot open file: \(url.lastPathComponent, privacy: .private)")
            errorMessage = "Cannot open '\(url.lastPathComponent)'. The file may be corrupted or not a valid PDF."
            showErrorAlert = true
            return
        }
        if doc.isLocked {
            pendingLockedURL = url
            passwordText = ""
            wrongPasswordAttempt = false
            showPasswordPrompt = true
            return
        }
        currentPage = 0
        currentFileSize = (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? Int64) ?? 0
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        BookmarkManager.saveBookmark(for: url)
        refreshRecentDocuments()
        hasUnsavedChanges = false
        state = .singleFile(url, doc)
    }

    func unlockDocument() {
        defer {
            passwordText = ""
        }
        guard let url = pendingLockedURL,
              let doc = PDFDocument(url: url) else {
            cancelPendingIntake()
            return
        }
        if doc.unlock(withPassword: passwordText) {
            currentPage = 0
            currentFileSize = (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? Int64) ?? 0
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            BookmarkManager.saveBookmark(for: url)
            refreshRecentDocuments()
            hasUnsavedChanges = false
            pendingLockedURL = nil
            wrongPasswordAttempt = false
            showPasswordPrompt = false
            state = .singleFile(url, doc)
        } else {
            passwordText = ""
            wrongPasswordAttempt = true
            showPasswordPrompt = true
        }
    }

    func cancelPassword() {
        cancelPendingIntake()
    }

    @discardableResult
    func loadMultipleFiles(_ urls: [URL]) -> Task<Void, Never> {
        cancelPendingIntake()
        let requestID = UUID()
        fileIntakeID = requestID

        let task = Task.detached(priority: .userInitiated) { [weak self] in
            var items: [PDFFileItem] = []
            items.reserveCapacity(urls.count)
            for url in urls {
                guard !Task.isCancelled else { return }
                if let item = PDFFileItem.from(url: url) {
                    items.append(item)
                }
            }
            guard !Task.isCancelled else { return }
            await self?.completeFileIntake(items, requestID: requestID)
        }
        fileIntakeTask = task
        return task
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

    func selectRotate() {
        guard case .singleFile(let url, let doc) = state else { return }
        guard let workingDocument = makeWorkingCopy(of: doc) else { return }
        navigationDirection = .trailing
        state = .rotating(url, source: doc, working: workingDocument)
    }

    func selectMetadata() {
        guard case .singleFile(let url, let doc) = state else { return }
        navigationDirection = .trailing
        state = .editingMetadata(url, doc)
    }

    func selectCrop() {
        guard case .singleFile(let url, let doc) = state else { return }
        guard let workingDocument = makeWorkingCopy(of: doc) else { return }
        navigationDirection = .trailing
        state = .cropping(url, source: doc, working: workingDocument)
    }

    func selectAdjustColor() {
        guard case .singleFile(let url, let doc) = state else { return }
        navigationDirection = .trailing
        state = .adjustingColor(url, doc)
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
        let destination: AppState
        switch state {
        case .rotating(let url, let sourceDocument, _),
             .cropping(let url, let sourceDocument, _):
            destination = .singleFile(url, sourceDocument)
        case .compressing(let url, let doc), .splitting(let url, let doc),
             .editingMetadata(let url, let doc), .adjustingColor(let url, let doc),
             .exportingImages(let url, let doc),
             .reorderingPages(let url, let doc):
            destination = .singleFile(url, doc)
        case .merging:
            destination = .landing
        default:
            return
        }
        navigationDirection = .leading
        state = destination
        hasUnsavedChanges = false
    }

    func confirmStartOver() {
        showStartOverConfirm = true
    }

    func startOver() {
        state = .landing
        currentPage = 0
        currentFileSize = 0
        navigationDirection = .trailing
        showStartOverConfirm = false
        hasUnsavedChanges = false
    }

    private func completeFileIntake(_ items: [PDFFileItem], requestID: UUID) {
        guard fileIntakeID == requestID else { return }
        fileIntakeTask = nil
        fileIntakeID = nil

        switch items.count {
        case 0:
            errorMessage = PDFwringerError.cannotOpenDocument.localizedDescription
            showErrorAlert = true
        case 1:
            loadSingleFile(items[0].url)
        default:
            for item in items {
                NSDocumentController.shared.noteNewRecentDocumentURL(item.url)
                BookmarkManager.saveBookmark(for: item.url)
            }
            refreshRecentDocuments()
            hasUnsavedChanges = false
            state = .merging(items)
        }
    }

    private func cancelPendingIntake() {
        fileIntakeTask?.cancel()
        fileIntakeTask = nil
        fileIntakeID = nil
        pendingLockedURL = nil
        showPasswordPrompt = false
        passwordText = ""
        wrongPasswordAttempt = false
    }

    private func makeWorkingCopy(of document: PDFDocument) -> PDFDocument? {
        guard let copy = document.copy() as? PDFDocument,
              copy !== document,
              copy.pageCount == document.pageCount,
              copy.isLocked == document.isLocked,
              copy.isEncrypted == document.isEncrypted,
              copy.accessPermissions == document.accessPermissions else {
            errorMessage = PDFwringerError.cannotOpenDocument.localizedDescription
            showErrorAlert = true
            return nil
        }
        for pageIndex in 0..<document.pageCount {
            guard let sourcePage = document.page(at: pageIndex),
                  let workingPage = copy.page(at: pageIndex),
                  sourcePage !== workingPage else {
                errorMessage = PDFwringerError.cannotOpenDocument.localizedDescription
                showErrorAlert = true
                return nil
            }
        }
        return copy
    }

}
