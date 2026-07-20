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
        try FileSystemIdentity.requireDistinct(source, destination)

        guard FileManager.default.isReadableFile(atPath: source.path(percentEncoded: false)) else {
            throw PDFwringerError.fileNotReadable(source.lastPathComponent)
        }

        guard let doc = PDFDocument(url: source) else {
            throw PDFwringerError.cannotOpenDocument
        }

        let start = ContinuousClock.now
        let rotatedPageCount = try rotate(
            document: doc,
            angle: angle,
            pageIndices: pageIndices,
            progress: progress
        )
        let expectedRotations = try rotations(in: doc)

        try Task.checkCancellation()
        try AtomicFileWriter.write(to: destination) { tempURL in
            guard doc.write(to: tempURL),
                  let output = PDFDocument(url: tempURL),
                  output.pageCount == doc.pageCount else {
                return false
            }
            if output.isLocked {
                return doc.isEncrypted && output.isEncrypted
            }
            return (try? rotations(in: output)) == expectedRotations
        }

        let elapsed = ContinuousClock.now - start
        Log.rotate.info("Rotation complete: \(rotatedPageCount) pages rotated \(angle.title), duration=\(elapsed)")
    }

    /// Applies rotation to an already-open document. Used by the interactive
    /// editor so the UI and file service share permission and failure behavior.
    @discardableResult
    func rotate(
        document: PDFDocument,
        angle: Angle,
        pageIndices: [Int]?,
        progress: (Double) -> Void
    ) throws -> Int {
        if document.isLocked { throw PDFwringerError.documentIsLocked }

        let pageCount = document.pageCount
        guard pageCount > 0 else { throw PDFwringerError.cannotOpenDocument }
        guard document.allowsDocumentAssembly else {
            throw PDFwringerError.documentAssemblyNotAllowed
        }

        let indicesToRotate: [Int]
        if let indices = pageIndices {
            indicesToRotate = indices.filter { $0 >= 0 && $0 < pageCount }
        } else {
            indicesToRotate = Array(0..<pageCount)
        }

        let pages = try indicesToRotate.map { pageIndex in
            guard let page = document.page(at: pageIndex) else {
                throw PDFwringerError.cannotOpenDocument
            }
            return page
        }
        var originalRotations: [Int: Int] = [:]
        for (pageIndex, page) in zip(indicesToRotate, pages) where originalRotations[pageIndex] == nil {
            originalRotations[pageIndex] = page.rotation
        }

        do {
            for (i, page) in pages.enumerated() {
                try Task.checkCancellation()
                let expectedRotation = normalizedRotation(page.rotation + angle.rawValue)
                page.rotation = expectedRotation
                guard normalizedRotation(page.rotation) == expectedRotation else {
                    throw PDFwringerError.documentAssemblyNotAllowed
                }
                progress(Double(i + 1) / Double(indicesToRotate.count))
            }
        } catch {
            for (pageIndex, rotation) in originalRotations {
                document.page(at: pageIndex)?.rotation = rotation
            }
            throw error
        }

        return indicesToRotate.count
    }

    private func rotations(in document: PDFDocument) throws -> [Int] {
        try (0..<document.pageCount).map { pageIndex in
            guard let page = document.page(at: pageIndex) else {
                throw PDFwringerError.cannotOpenDocument
            }
            return normalizedRotation(page.rotation)
        }
    }

    private func normalizedRotation(_ rotation: Int) -> Int {
        ((rotation % 360) + 360) % 360
    }
}
