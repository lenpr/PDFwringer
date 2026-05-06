import Foundation
import PDFKit

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
        default: false
        }
    }
}

/// Orchestrates top-level navigation and file loading. Owned by the App scene, shared with ContentView.
@MainActor @Observable
class AppViewModel {
    var state: AppState = .landing
    var currentPage: Int = 0

    // Password prompt state
    var showPasswordPrompt = false
    var passwordText = ""
    private var pendingLockedURL: URL?

    var windowTitle: String {
        switch state {
        case .landing:
            return "PDFwringer"
        case .singleFile(let url, _), .compressing(let url, _), .splitting(let url, _),
             .rotating(let url, _), .editingMetadata(let url, _):
            return url.lastPathComponent
        case .multiFile(let items), .merging(let items):
            return "\(items.count) files"
        }
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
        guard let doc = PDFDocument(url: url) else { return }
        if doc.isLocked {
            pendingLockedURL = url
            passwordText = ""
            showPasswordPrompt = true
            return
        }
        currentPage = 0
        state = .singleFile(url, doc)
    }

    func unlockDocument() {
        guard let url = pendingLockedURL,
              let doc = PDFDocument(url: url) else {
            pendingLockedURL = nil
            return
        }
        if doc.unlock(withPassword: passwordText) {
            state = .singleFile(url, doc)
        }
        pendingLockedURL = nil
        passwordText = ""
    }

    func cancelPassword() {
        pendingLockedURL = nil
        passwordText = ""
    }

    func loadMultipleFiles(_ urls: [URL]) {
        let items = PDFFileItem.from(urls: urls)
        guard !items.isEmpty else { return }
        state = .multiFile(items)
    }

    func selectCompress() {
        guard case .singleFile(let url, let doc) = state else { return }
        state = .compressing(url, doc)
    }

    func selectSplit() {
        guard case .singleFile(let url, let doc) = state else { return }
        state = .splitting(url, doc)
    }

    func selectMerge() {
        guard case .multiFile(let items) = state else { return }
        state = .merging(items)
    }

    func selectRotate() {
        guard case .singleFile(let url, let doc) = state else { return }
        state = .rotating(url, doc)
    }

    func selectMetadata() {
        guard case .singleFile(let url, let doc) = state else { return }
        state = .editingMetadata(url, doc)
    }

    func goBack() {
        switch state {
        case .compressing(let url, let doc), .splitting(let url, let doc),
             .rotating(let url, let doc), .editingMetadata(let url, let doc):
            state = .singleFile(url, doc)
        case .merging(let items):
            state = .multiFile(items)
        default:
            break
        }
    }

    func startOver() {
        state = .landing
    }
}
