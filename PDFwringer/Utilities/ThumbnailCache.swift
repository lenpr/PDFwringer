import AppKit
import Observation
import PDFKit

/// A bounded cache for one document. Geometry and requested size are part of the
/// key because crop/rotation editors mutate PDFPage objects in place.
@MainActor @Observable
final class ThumbnailCache {
    @ObservationIgnored private let cache = NSCache<NSString, NSImage>()
    @ObservationIgnored private weak var document: PDFDocument?
    @ObservationIgnored private var pending: [String: Request] = [:]
    @ObservationIgnored private var queue: [String] = []
    @ObservationIgnored private var preferredPage: Int?
    @ObservationIgnored private var activeRequest: Request?
    // Keep the active task across cancellation: a non-interruptible PDFKit
    // render must finish before another request allocates a page snapshot.
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var revision = 0
    private(set) var generation = 0

    private struct Request {
        let key: String
        let index: Int
        let page: PDFPage
        let size: CGSize
        let revision: Int
    }

    init() {
        cache.countLimit = 200
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    func thumbnail(for index: Int, document: PDFDocument, size: CGSize, priority: Bool = false) -> NSImage? {
        if self.document !== document {
            cancel()
            self.document = document
        }
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0,
              size.width <= 2048, size.height <= 2048,
              let page = document.page(at: index) else { return nil }
        let bounds = page.bounds(for: .cropBox)
        guard bounds.origin.x.isFinite, bounds.origin.y.isFinite,
              bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0 else { return nil }
        if priority { preferredPage = index }
        let key = Self.key(for: index, page: page, size: size)
        if let image = cache.object(forKey: key as NSString) { return image }
        guard pending[key] == nil,
              !(activeRequest?.key == key && activeRequest?.revision == revision) else { return nil }
        // A geometry change supersedes an older queued render of this cell.
        discardQueued(for: index, document: document, size: size)
        pending[key] = Request(key: key, index: index, page: page, size: size, revision: revision)
        queue.append(key)
        startNextIfNeeded()
        return nil
    }

    /// Leaving a cell removes optional work that has not started. A running
    /// render remains single-flight and may populate the bounded cache.
    func discardQueued(for index: Int, document: PDFDocument, size: CGSize) {
        guard self.document === document else { return }
        let keys = Set(pending.values.filter { $0.index == index && $0.size == size }.map(\.key))
        for key in keys { pending.removeValue(forKey: key) }
        queue.removeAll { keys.contains($0) }
    }

    private static func key(for index: Int, page: PDFPage, size: CGSize) -> String {
        "\(index)|\(ObjectIdentifier(page))|\(page.rotation)|\(page.bounds(for: .cropBox))|\(page.bounds(for: .mediaBox))|\(size)"
    }

    private func isCurrent(_ request: Request) -> Bool {
        guard let page = document?.page(at: request.index), page === request.page else { return false }
        return Self.key(for: request.index, page: page, size: request.size) == request.key
    }

    private func startNextIfNeeded() {
        guard renderTask == nil, !queue.isEmpty else { return }

        renderTask = Task { [weak self] in
            defer { self?.finishRender() }
            // View construction only queues work. Leaving the view can cancel
            // it before PDFKit serializes the authoritative page on MainActor.
            guard !Task.isCancelled, let self, !self.queue.isEmpty else { return }
            let position = self.queue.firstIndex { self.pending[$0]?.index == self.preferredPage } ?? 0
            let key = self.queue.remove(at: position)
            guard let request = self.pending.removeValue(forKey: key), self.revision == request.revision,
                  self.isCurrent(request) else { return }
            self.activeRequest = request
            guard let pageData = request.page.dataRepresentation else { return }
            let size = request.size
            let imageData = try? await PDFPageWorker.run(pageData: pageData) { isolatedPage in
                let image = isolatedPage.thumbnail(of: size, for: .cropBox)
                guard let data = image.tiffRepresentation else {
                    throw PDFwringerError.cannotCreateOutput
                }
                return data
            }
            guard self.revision == request.revision, !Task.isCancelled, self.isCurrent(request),
                  let imageData, let image = NSImage(data: imageData) else { return }
            self.cache.setObject(image, forKey: request.key as NSString, cost: imageData.count)
            self.generation += 1
        }
    }

    private func finishRender() {
        activeRequest = nil
        renderTask = nil
        startNextIfNeeded()
    }

    /// Invalidates late completions as well as cancelling workers. A newly shown
    /// view may reuse this cache without an old task clearing its pending request.
    func cancel() {
        revision += 1
        renderTask?.cancel()
        pending.removeAll()
        queue.removeAll()
        preferredPage = nil
        cache.removeAllObjects()
        document = nil
    }
}
