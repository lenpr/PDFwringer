import AppKit
import Observation
import PDFKit

/// A bounded cache for one document. Geometry and requested size are part of the
/// key because crop/rotation editors mutate PDFPage objects in place.
@MainActor @Observable
final class ThumbnailCache {
    @ObservationIgnored private let cache = NSCache<NSString, NSImage>()
    @ObservationIgnored private weak var document: PDFDocument?
    @ObservationIgnored private var pending: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var revision = 0
    private(set) var generation = 0

    init() {
        cache.countLimit = 200
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    func thumbnail(for index: Int, document: PDFDocument, size: CGSize) -> NSImage? {
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
        let key = "\(index)|\(ObjectIdentifier(page))|\(page.rotation)|\(bounds)|\(page.bounds(for: .mediaBox))|\(size)"
        if let image = cache.object(forKey: key as NSString) { return image }
        guard pending[key] == nil else { return nil }
        let requestRevision = revision

        pending[key] = Task { [weak self] in
            defer {
                if let self, self.revision == requestRevision {
                    self.pending.removeValue(forKey: key)
                }
            }
            // View construction only queues work. Leaving the view can cancel
            // it before PDFKit serializes the authoritative page on MainActor.
            guard !Task.isCancelled, let pageData = page.dataRepresentation else { return }
            let imageData = try? await PDFPageWorker.run(pageData: pageData) { isolatedPage in
                let image = isolatedPage.thumbnail(of: size, for: .cropBox)
                guard let data = image.tiffRepresentation else {
                    throw PDFwringerError.cannotCreateOutput
                }
                return data
            }
            guard let self, self.revision == requestRevision else { return }
            guard !Task.isCancelled, let imageData, let image = NSImage(data: imageData) else { return }
            self.cache.setObject(image, forKey: key as NSString, cost: imageData.count)
            self.generation += 1
        }
        return nil
    }

    /// Invalidates late completions as well as cancelling workers. A newly shown
    /// view may reuse this cache without an old task clearing its pending request.
    func cancel() {
        revision += 1
        for task in pending.values { task.cancel() }
        pending.removeAll()
        cache.removeAllObjects()
        document = nil
    }
}
