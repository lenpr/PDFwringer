import Foundation
import PDFKit

enum AppState: Equatable {
    case landing
    case singleFile(URL, PDFDocument)
    case multiFile([PDFFileItem])
    case compressing(URL, PDFDocument)
    case splitting(URL, PDFDocument)
    case merging([PDFFileItem])

    static func == (lhs: AppState, rhs: AppState) -> Bool {
        switch (lhs, rhs) {
        case (.landing, .landing): true
        case (.singleFile(let a, _), .singleFile(let b, _)): a == b
        case (.multiFile(let a), .multiFile(let b)): a.map(\.id) == b.map(\.id)
        case (.compressing(let a, _), .compressing(let b, _)): a == b
        case (.splitting(let a, _), .splitting(let b, _)): a == b
        case (.merging(let a), .merging(let b)): a.map(\.id) == b.map(\.id)
        default: false
        }
    }
}

@MainActor @Observable
class AppViewModel {
    var state: AppState = .landing

    var windowTitle: String {
        switch state {
        case .landing:
            return "PDFwringer"
        case .singleFile(let url, _), .compressing(let url, _), .splitting(let url, _):
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
        state = .singleFile(url, doc)
    }

    func loadMultipleFiles(_ urls: [URL]) {
        var items: [PDFFileItem] = []
        for url in urls {
            guard url.pathExtension.lowercased() == "pdf" else { continue }
            let pageCount = PDFDocument(url: url)?.pageCount ?? 0
            let bookmarkData = (try? url.bookmarkData(options: .withSecurityScope)) ?? Data()
            items.append(PDFFileItem(url: url, bookmarkData: bookmarkData, pageCount: pageCount))
        }
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

    func goBack() {
        switch state {
        case .compressing(let url, let doc), .splitting(let url, let doc):
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
