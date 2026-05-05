import Foundation
import PDFKit

/// Rotates pages in a PDF document by a specified angle.
@MainActor
struct PDFRotator {

    /// Rotation angle in degrees (clockwise).
    enum Angle: Int, CaseIterable, Identifiable {
        case ninety = 90
        case oneEighty = 180
        case twoSeventy = 270

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .ninety: "90° CW"
            case .oneEighty: "180°"
            case .twoSeventy: "90° CCW"
            }
        }
    }

    /// Rotates pages at the given 0-based indices by the specified angle.
    /// If `pageIndices` is nil, rotates all pages.
    func rotate(
        source: URL,
        destination: URL,
        angle: Angle,
        pageIndices: [Int]?,
        progress: (Double) -> Void
    ) async throws {
        guard FileManager.default.isReadableFile(atPath: source.path(percentEncoded: false)) else {
            throw PDFwringerError.fileNotReadable(source.lastPathComponent)
        }

        guard let doc = PDFDocument(url: source) else {
            throw PDFwringerError.cannotOpenDocument
        }
        if doc.isLocked { throw PDFwringerError.documentIsLocked }

        let pageCount = doc.pageCount
        guard pageCount > 0 else { throw PDFwringerError.cannotOpenDocument }

        let indicesToRotate: [Int]
        if let indices = pageIndices {
            indicesToRotate = indices.filter { $0 >= 0 && $0 < pageCount }
        } else {
            indicesToRotate = Array(0..<pageCount)
        }

        for (i, pageIdx) in indicesToRotate.enumerated() {
            try Task.checkCancellation()
            guard let page = doc.page(at: pageIdx) else { continue }
            page.rotation = (page.rotation + angle.rawValue) % 360
            progress(Double(i + 1) / Double(indicesToRotate.count))
        }

        let tempURL = URL.temporaryDirectory.appending(component: UUID().uuidString + ".pdf")
        guard doc.write(to: tempURL) else {
            throw PDFwringerError.cannotWriteOutput
        }

        do {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }
}
