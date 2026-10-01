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
        didSet { cancelPendingIntake(); cancelToolPreparation() }
    }
    var currentPage: Int = 0
    var currentFileSize: Int64 = 0
    var navigationDirection: Edge = .trailing
    private(set) var isPreparingTool = false
    private(set) var isLoadingFile = false
    @ObservationIgnored private var previewSourceBytes: Data?
    @ObservationIgnored private weak var previewSourceDocument: PDFDocument?
    @ObservationIgnored private var toolPreparationTask: Task<Void, Never>?
    @ObservationIgnored private var toolPreparationID: UUID?

    // Error alert state
    var showErrorAlert = false
    var errorMessage = ""

    // Includes pending metadata, color, page-order, and working-document edits.
    var hasUnsavedChanges = false
    @ObservationIgnored var operationIsRunning: @MainActor () -> Bool = { false }
    @ObservationIgnored private var isConfirmingDiscard = false
    @ObservationIgnored private let confirmDiscard: @MainActor () -> Bool

    /// Navigation and termination share the same gate. Running operations must finish
    /// or be cancelled through their view before releasing document/file access.
    func canLeaveWorkflow() -> Bool {
        // The active file panel owns the workflow until it returns. Do not open
        // a discard/error alert underneath it or release its source-file access.
        guard !FileDialogHelper.isPresentingFilePanel, !isConfirmingDiscard else { return false }
        if operationIsRunning() {
            errorMessage = String(localized: "An operation is still running. Wait for it to finish, or cancel it before leaving this document.")
            showErrorAlert = true
            return false
        }
        guard hasUnsavedChanges else { return true }
        // NSAlert runs a nested event loop just like a file panel. Preserve the
        // workflow while its discard decision is outstanding.
        isConfirmingDiscard = true
        defer { isConfirmingDiscard = false }
        return confirmDiscard()
    }

    // Password prompt state
    var showPasswordPrompt = false
    var passwordText = ""
    var wrongPasswordAttempt = false
    private var pendingLockedURL: URL?
    private var pendingLockedDocument: PDFDocument?
    private var pendingLockedFileSize: Int64 = 0
    private var fileIntakeTask: Task<Void, Never>?
    private var fileIntakeID: UUID?
    private var activeSecurityScopedURL: URL?
    private var pendingSecurityScopedURL: URL?
    private var mergeReturnState: AppState?
    @ObservationIgnored private let beginSecurityScopedAccess: @MainActor (URL) -> Bool
    @ObservationIgnored private let endSecurityScopedAccess: @MainActor (URL) -> Void

    init(
        beginSecurityScopedAccess: @escaping @MainActor (URL) -> Bool = BookmarkManager.startAccessing,
        endSecurityScopedAccess: @escaping @MainActor (URL) -> Void = BookmarkManager.stopAccessing,
        confirmDiscard: @escaping @MainActor () -> Bool = FileDialogHelper.confirmDiscardChanges
    ) {
        self.confirmDiscard = confirmDiscard
        self.beginSecurityScopedAccess = beginSecurityScopedAccess
        self.endSecurityScopedAccess = endSecurityScopedAccess
    }

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
            return items.isEmpty ? "PDFwringer — Merge PDFs"
                : "PDFwringer — \(items.count) \(items.count == 1 ? "file" : "files")"
        }
    }

    var isLanding: Bool {
        if case .landing = state { return true }
        return false
    }

    var canSelectSingleFileAction: Bool {
        guard !isPreparingTool, !isLoadingFile else { return false }
        if case .singleFile = state { return true }
        return false
    }

    var mergeReturnsToDocument: Bool { mergeReturnState != nil }

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

    private var canNavigatePages: Bool { !isPreparingTool && !isLoadingFile && !operationIsRunning() }

    func nextPage() { if canNavigatePages, currentPage < currentPageCount - 1 { currentPage += 1 } }
    func previousPage() { if canNavigatePages, currentPage > 0 { currentPage -= 1 } }
    func goToFirstPage() { if canNavigatePages { currentPage = 0 } }
    func goToLastPage() { if canNavigatePages { currentPage = max(0, currentPageCount - 1) } }

    var recentDocuments: [URL] = []
    @ObservationIgnored private var recentRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var recentRefreshID: UUID?

    func refreshRecentDocuments() {
        recentRefreshID = UUID()
        recentRefreshTask?.cancel()
        startRecentRefreshIfNeeded()
    }

    private func startRecentRefreshIfNeeded() {
        guard recentRefreshTask == nil, let id = recentRefreshID else { return }
        recentRefreshTask = Task { @MainActor [weak self] in
            defer {
                if let self {
                    self.recentRefreshTask = nil
                    if self.recentRefreshID != id { self.startRecentRefreshIfNeeded() }
                }
            }
            let urls = await BookmarkManager.resolveBookmarksAsync()
            guard !Task.isCancelled, let self, self.recentRefreshID == id, let urls else { return }
            self.recentDocuments = urls
        }
    }

    func clearRecentDocuments() {
        recentRefreshTask?.cancel()
        recentRefreshID = nil
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
        loadSingleFile(url, requiresSecurityScopedAccess: false)
    }

    func openRecentDocument(_ url: URL) {
        loadSingleFile(url, requiresSecurityScopedAccess: true)
    }

    private func loadSingleFile(_ url: URL, requiresSecurityScopedAccess: Bool) {
        guard canLeaveWorkflow() else { return }
        cancelPendingIntake()
        if requiresSecurityScopedAccess {
            guard beginSecurityScopedAccess(url) else {
                errorMessage = PDFwringerError.accessDenied.localizedDescription
                showErrorAlert = true
                return
            }
            pendingSecurityScopedURL = url
        }

        let id = UUID()
        fileIntakeID = id
        isLoadingFile = true
        // The task holds a recent-file grant until its read finishes, even when
        // navigation cancels a noninterruptible filesystem read.
        let scopedURL = pendingSecurityScopedURL
        pendingSecurityScopedURL = nil
        let endAccess = endSecurityScopedAccess
        fileIntakeTask = Task { @MainActor [weak self] in
            var ownsScope = scopedURL != nil
            defer {
                if ownsScope, let scopedURL { endAccess(scopedURL) }
                if let self, self.fileIntakeID == id {
                    self.fileIntakeTask = nil
                    self.fileIntakeID = nil
                    self.isLoadingFile = false
                }
            }
            do {
                let worker = Task.detached(priority: .userInitiated) {
                    try Task.checkCancellation()
                    let size = try FileManager.default.attributesOfItem(
                        atPath: url.path(percentEncoded: false))[.size] as? Int64 ?? 0
                    // Large sources retain URL-backed PDFKit loading rather
                    // than retaining an additional unbounded byte buffer.
                    let data = size > 0 && size <= PDFRasterizer.maximumInMemoryPDFBytes
                        ? try PDFRasterizer.readSourceBytes(at: url) : nil
                    try Task.checkCancellation()
                    return (data, data.map { Int64($0.count) } ?? size)
                }
                let (data, size) = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                guard let self, self.fileIntakeID == id else { return }
                let loadedDocument: PDFDocument?
                if let data { loadedDocument = PDFDocument(data: data) }
                else { loadedDocument = PDFDocument(url: url) }
                guard let doc = loadedDocument else {
                    throw PDFwringerError.cannotOpenDocument
                }
                self.pendingSecurityScopedURL = scopedURL
                ownsScope = false
                self.finishSingleFileLoad(url, document: doc, data: data, size: size)
            } catch {
                guard let self, self.fileIntakeID == id, !(error is CancellationError) else { return }
                self.failFileIntake(error, requestID: id)
                if case PDFwringerError.cannotOpenDocument = error {
                    self.errorMessage = "Cannot open '\(url.lastPathComponent)'. The file may be corrupted or not a valid PDF."
                }
            }
        }
    }

    func waitForFileIntake() async { await fileIntakeTask?.value }

    func cancelFileIntake() { cancelPendingIntake() }

    func previewSourceData(for document: PDFDocument) -> Data? {
        guard document === previewSourceDocument, !document.isEncrypted else { return nil }
        return previewSourceBytes
    }

    private func finishSingleFileLoad(_ url: URL, document doc: PDFDocument, data: Data?, size: Int64) {
        previewSourceBytes = doc.isEncrypted ? nil : data
        previewSourceDocument = doc
        if doc.isLocked {
            pendingLockedURL = url
            pendingLockedDocument = doc
            pendingLockedFileSize = size
            passwordText = ""
            wrongPasswordAttempt = false
            showPasswordPrompt = true
            return
        }
        commitPendingSecurityScope()
        currentPage = 0
        currentFileSize = size
        recordRecentDocuments([url])
        refreshRecentDocuments()
        hasUnsavedChanges = false
        operationIsRunning = { false }
        mergeReturnState = nil
        state = .singleFile(url, doc)
    }

    func unlockDocument() {
        defer {
            passwordText = ""
        }
        guard let url = pendingLockedURL,
              let doc = pendingLockedDocument else {
            cancelPendingIntake()
            return
        }
        if doc.unlock(withPassword: passwordText) {
            commitPendingSecurityScope()
            currentPage = 0
            currentFileSize = pendingLockedFileSize
            recordRecentDocuments([url])
            refreshRecentDocuments()
            hasUnsavedChanges = false
            operationIsRunning = { false }
            pendingLockedURL = nil
            pendingLockedDocument = nil
            pendingLockedFileSize = 0
            wrongPasswordAttempt = false
            showPasswordPrompt = false
            mergeReturnState = nil
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
        guard !FileDialogHelper.isPresentingFilePanel, !isConfirmingDiscard else { return Task {} }
        guard !operationIsRunning() else {
            _ = canLeaveWorkflow()
            return Task {}
        }
        cancelPendingIntake()
        let requestID = UUID()
        fileIntakeID = requestID

        let task = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let items = try await PDFFileItem.load(urls: urls)
                try Task.checkCancellation()
                await self?.completeFileIntake(items, requestID: requestID)
            } catch is CancellationError {
                // A newer intake or navigation transition superseded this batch.
            } catch {
                await self?.failFileIntake(error, requestID: requestID)
            }
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
        prepareWorkingTool(crop: false)
    }

    func selectMetadata() {
        guard case .singleFile(let url, let doc) = state else { return }
        navigationDirection = .trailing
        state = .editingMetadata(url, doc)
    }

    func selectCrop() {
        prepareWorkingTool(crop: true)
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

    func selectMerge() {
        guard canSelectSingleFileAction, canLeaveWorkflow() else { return }
        switch state {
        case .singleFile(let url, let document):
            // Merge reads its inputs again from disk; an in-memory unlock cannot
            // be passed to the background merger as a password authorization.
            if document.isEncrypted, PDFFileItem.from(url: url) == nil {
                errorMessage = String(localized: "To merge this password-protected PDF, first save a copy with Remove password protection in Edit Metadata, then open that copy.")
                showErrorAlert = true
                return
            }
            mergeReturnState = state
            state = .merging([PDFFileItem(url: url, pageCount: document.pageCount)])
        default:
            return
        }
        navigationDirection = .trailing
        hasUnsavedChanges = false
        operationIsRunning = { false }
    }

    func updateMergeFiles(_ items: [PDFFileItem]) {
        guard case .merging = state else { return }
        // Removing the final item leaves an empty merge list ready for Add Files.
        state = .merging(items)
    }

    func goBack() {
        guard canGoBack, canLeaveWorkflow() else { return }
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
            destination = mergeReturnState ?? .landing
            mergeReturnState = nil
        default:
            return
        }
        navigationDirection = .leading
        state = destination
        operationIsRunning = { false }
        hasUnsavedChanges = false
        if case .landing = destination { stopActiveSecurityScope() }
    }

    func confirmStartOver() {
        startOver()
    }

    func startOver() {
        guard canLeaveWorkflow() else { return }
        resetWorkflow()
    }

    func closeWorkflow() -> Bool {
        guard canLeaveWorkflow() else { return false }
        resetWorkflow()
        return true
    }

    private func resetWorkflow() {
        previewSourceBytes = nil
        previewSourceDocument = nil
        stopActiveSecurityScope()
        state = .landing
        operationIsRunning = { false }
        currentPage = 0
        currentFileSize = 0
        navigationDirection = .trailing
        hasUnsavedChanges = false
        mergeReturnState = nil
    }

    private func failFileIntake(_ error: Error, requestID: UUID) {
        guard fileIntakeID == requestID else { return }
        cancelPendingIntake()
        errorMessage = PDFwringerError.userMessage(for: error)
        showErrorAlert = true
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
            guard canLeaveWorkflow() else { return }
            operationIsRunning = { false }
            commitPendingSecurityScope()
            recordRecentDocuments(items.map(\.url))
            previewSourceBytes = nil
            previewSourceDocument = nil
            refreshRecentDocuments()
            hasUnsavedChanges = false
            mergeReturnState = nil
            state = .merging(items)
        }
    }

    private func recordRecentDocuments(_ urls: [URL]) {
        for url in urls {
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            recentDocuments.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
            recentDocuments.insert(url, at: 0)
            recentDocuments = Array(recentDocuments.prefix(10))
        }
        BookmarkManager.saveBookmarks(for: urls)
    }

    private func cancelPendingIntake() {
        fileIntakeTask?.cancel()
        fileIntakeTask = nil
        fileIntakeID = nil
        isLoadingFile = false
        if let pendingSecurityScopedURL {
            endSecurityScopedAccess(pendingSecurityScopedURL)
            self.pendingSecurityScopedURL = nil
        }
        pendingLockedURL = nil
        pendingLockedDocument = nil
        pendingLockedFileSize = 0
        showPasswordPrompt = false
        passwordText = ""
        wrongPasswordAttempt = false
    }

    private func commitPendingSecurityScope() {
        stopActiveSecurityScope()
        activeSecurityScopedURL = pendingSecurityScopedURL
        pendingSecurityScopedURL = nil
    }

    private func stopActiveSecurityScope() {
        guard let activeSecurityScopedURL else { return }
        endSecurityScopedAccess(activeSecurityScopedURL)
        self.activeSecurityScopedURL = nil
    }

    func cancelToolPreparation() {
        toolPreparationTask?.cancel()
        toolPreparationTask = nil
        toolPreparationID = nil
        isPreparingTool = false
    }

    private func prepareWorkingTool(crop: Bool) {
        guard !isPreparingTool, case .singleFile(let url, let document) = state else { return }
        // Normal documents retain immediate navigation. Large documents finish
        // the same isolation checks before any editing view receives the copy.
        if document.pageCount <= 100 {
            do {
                let copy = try workingCopyHeader(of: document)
                try requireIsolatedPages(document, copy: copy, indices: 0..<document.pageCount)
                navigationDirection = .trailing
                state = crop ? .cropping(url, source: document, working: copy)
                    : .rotating(url, source: document, working: copy)
            } catch { reportToolPreparationFailure(error) }
            return
        }
        let id = UUID()
        toolPreparationID = id
        isPreparingTool = true
        toolPreparationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.toolPreparationID == id { self.cancelToolPreparation() } }
            do {
                try Task.checkCancellation()
                let copy = try self.workingCopyHeader(of: document)
                for start in stride(from: 0, to: document.pageCount, by: 25) {
                    try Task.checkCancellation()
                    try self.requireIsolatedPages(document, copy: copy,
                                                  indices: start..<min(start + 25, document.pageCount))
                    await Task.yield()
                }
                try Task.checkCancellation()
                guard self.toolPreparationID == id,
                      case .singleFile(let currentURL, let currentDocument) = self.state,
                      currentURL == url, currentDocument === document else { return }
                self.navigationDirection = .trailing
                self.state = crop ? .cropping(url, source: document, working: copy)
                    : .rotating(url, source: document, working: copy)
            } catch is CancellationError {
                // Closing/replacing the file discards this private copy.
            } catch {
                if self.toolPreparationID == id { self.reportToolPreparationFailure(error) }
            }
        }
    }

    private func reportToolPreparationFailure(_ error: Error) {
        errorMessage = PDFwringerError.userMessage(for: error)
        showErrorAlert = true
    }

    private func workingCopyHeader(of document: PDFDocument) throws -> PDFDocument {
        guard let copy = document.copy() as? PDFDocument,
              copy !== document,
              copy.pageCount == document.pageCount,
              copy.isLocked == document.isLocked,
              copy.isEncrypted == document.isEncrypted,
              copy.accessPermissions == document.accessPermissions else {
            throw PDFwringerError.cannotOpenDocument
        }
        return copy
    }

    private func requireIsolatedPages(_ document: PDFDocument, copy: PDFDocument, indices: Range<Int>) throws {
        for pageIndex in indices {
            guard let sourcePage = document.page(at: pageIndex),
                  let workingPage = copy.page(at: pageIndex),
                  sourcePage !== workingPage else {
                throw PDFwringerError.cannotOpenDocument
            }
        }
    }

}
