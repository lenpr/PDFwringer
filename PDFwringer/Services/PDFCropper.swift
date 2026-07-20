import Foundation
import PDFKit

/// Converts display-oriented crop controls into the unrotated page coordinate space.
enum PDFCropGeometry {
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
            guard newBounds.size.width > 0 && newBounds.size.height > 0 else {
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
            let targetBounds = PDFCropGeometry.resizeBounds(
                in: page.bounds(for: .cropBox),
                rotation: page.rotation,
                displayTargetSize: targetSize
            )
            guard targetBounds.width > 0, targetBounds.height > 0,
                  targetBounds.width.isFinite, targetBounds.height.isFinite else {
                skipped += 1
                continue
            }
            page.setBounds(targetBounds, for: .mediaBox)
            page.setBounds(targetBounds, for: .cropBox)
            modified += 1
        }

        return CropResult(pagesModified: modified, pagesSkipped: skipped)
    }
}
