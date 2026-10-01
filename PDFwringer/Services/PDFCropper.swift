import Foundation
import PDFKit

/// Converts display-oriented crop controls into the unrotated page coordinate space.
enum PDFCropGeometry {
    static func isValid(_ bounds: CGRect) -> Bool {
        bounds.origin.x.isFinite && bounds.origin.y.isFinite
            && bounds.size.width.isFinite && bounds.size.height.isFinite
            && bounds.size.width > 0 && bounds.size.height > 0
            && bounds.maxX.isFinite && bounds.maxY.isFinite
    }

    static func cropBounds(
        in bounds: CGRect,
        rotation: Int,
        top: CGFloat,
        bottom: CGFloat,
        left: CGFloat,
        right: CGFloat
    ) -> CGRect {
        let top = max(0, top)
        let bottom = max(0, bottom)
        let left = max(0, left)
        let right = max(0, right)

        let pageInsets: (top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat)
        switch normalizedRotation(rotation) {
        case 90:
            pageInsets = (right, left, top, bottom)
        case 180:
            pageInsets = (bottom, top, right, left)
        case 270:
            pageInsets = (left, right, bottom, top)
        default:
            pageInsets = (top, bottom, left, right)
        }

        return CGRect(
            x: bounds.minX + pageInsets.left,
            y: bounds.minY + pageInsets.bottom,
            width: bounds.width - pageInsets.left - pageInsets.right,
            height: bounds.height - pageInsets.top - pageInsets.bottom
        )
    }

    static func resizeBounds(
        in bounds: CGRect,
        rotation: Int,
        displayTargetSize: CGSize
    ) -> CGRect {
        let pageTargetSize = pageSpaceSize(for: displayTargetSize, rotation: rotation)
        return CGRect(
            x: bounds.midX - pageTargetSize.width / 2,
            y: bounds.midY - pageTargetSize.height / 2,
            width: pageTargetSize.width,
            height: pageTargetSize.height
        )
    }

    static func pageSpaceSize(for displaySize: CGSize, rotation: Int) -> CGSize {
        switch normalizedRotation(rotation) {
        case 90, 270:
            CGSize(width: displaySize.height, height: displaySize.width)
        default:
            displaySize
        }
    }

    private static func normalizedRotation(_ rotation: Int) -> Int {
        ((rotation % 360) + 360) % 360
    }
}

@MainActor
struct PDFCropper {

    struct CropResult {
        var pagesModified: Int
        var pagesSkipped: Int
    }

    func crop(document: PDFDocument, indices: [Int], top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat) throws -> CropResult {
        try PDFPermissionPolicy.require(.changeDocument, for: document)
        guard [top, bottom, left, right].allSatisfy(\.isFinite) else {
            throw PDFwringerError.cannotCreateOutput
        }
        Log.crop.info("Starting crop: \(indices.count) pages, insets T=\(top) B=\(bottom) L=\(left) R=\(right)")
        var modified = 0
        var skipped = 0

        for idx in indices where idx >= 0 && idx < document.pageCount {
            guard let page = document.page(at: idx) else {
                skipped += 1
                continue
            }
            let bounds = page.bounds(for: .cropBox)
            let newBounds = PDFCropGeometry.cropBounds(
                in: bounds,
                rotation: page.rotation,
                top: top,
                bottom: bottom,
                left: left,
                right: right
            )
            guard PDFCropGeometry.isValid(bounds), PDFCropGeometry.isValid(newBounds) else {
                skipped += 1
                continue
            }
            page.setBounds(newBounds, for: .cropBox)
            modified += 1
        }

        return CropResult(pagesModified: modified, pagesSkipped: skipped)
    }

    func resize(document: PDFDocument, indices: [Int], targetSize: CGSize) throws -> CropResult {
        try PDFPermissionPolicy.require(.changeDocument, for: document)
        var modified = 0
        var skipped = 0

        for idx in indices where idx >= 0 && idx < document.pageCount {
            guard let page = document.page(at: idx) else {
                skipped += 1
                continue
            }
            let bounds = page.bounds(for: .cropBox)
            let targetBounds = PDFCropGeometry.resizeBounds(
                in: bounds,
                rotation: page.rotation,
                displayTargetSize: targetSize
            )
            guard PDFCropGeometry.isValid(bounds), PDFCropGeometry.isValid(targetBounds) else {
                skipped += 1
                continue
            }
            page.setBounds(targetBounds, for: .mediaBox)
            page.setBounds(targetBounds, for: .cropBox)
            modified += 1
        }

        return CropResult(pagesModified: modified, pagesSkipped: skipped)
    }

    func cropInBatches(document: PDFDocument, indices: [Int], top: CGFloat, bottom: CGFloat,
                       left: CGFloat, right: CGFloat) async throws -> CropResult {
        try await mutateInBatches(document: document, indices: indices) { batch in
            try crop(document: document, indices: batch, top: top, bottom: bottom, left: left, right: right)
        }
    }

    func resizeInBatches(document: PDFDocument, indices: [Int], targetSize: CGSize) async throws -> CropResult {
        try await mutateInBatches(document: document, indices: indices) { batch in
            try resize(document: document, indices: batch, targetSize: targetSize)
        }
    }

    private func mutateInBatches(document: PDFDocument, indices: [Int],
                                 operation: ([Int]) throws -> CropResult) async throws -> CropResult {
        try PDFPermissionPolicy.require(.changeDocument, for: document)
        var originals: [Int: (PDFPage, CGRect, CGRect)] = [:]
        var result = CropResult(pagesModified: 0, pagesSkipped: 0)
        do {
            for (offset, index) in indices.enumerated() {
                try Task.checkCancellation()
                if (0..<document.pageCount).contains(index), originals[index] == nil,
                   let page = document.page(at: index) {
                    originals[index] = (page, page.bounds(for: .mediaBox), page.bounds(for: .cropBox))
                }
                if (offset + 1).isMultiple(of: 25) { await Task.yield() }
            }
            for start in stride(from: 0, to: indices.count, by: 25) {
                try Task.checkCancellation()
                let batch = try operation(Array(indices[start..<min(start + 25, indices.count)]))
                result.pagesModified += batch.pagesModified
                result.pagesSkipped += batch.pagesSkipped
                if indices.count > 25 { await Task.yield() }
            }
            try Task.checkCancellation()
            return result
        } catch {
            for (offset, original) in originals.values.enumerated() {
                original.0.setBounds(original.1, for: .mediaBox)
                original.0.setBounds(original.2, for: .cropBox)
                if (offset + 1).isMultiple(of: 25) { await Task.yield() }
            }
            throw error
        }
    }
}
