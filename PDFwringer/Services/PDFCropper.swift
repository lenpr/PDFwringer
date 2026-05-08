import Foundation
import PDFKit

@MainActor
struct PDFCropper {

    struct CropResult {
        var pagesModified: Int
        var pagesSkipped: Int
    }

    func crop(document: PDFDocument, indices: [Int], top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat) -> CropResult {
        Log.crop.info("Starting crop: \(indices.count) pages, insets T=\(top) B=\(bottom) L=\(left) R=\(right)")
        var modified = 0
        var skipped = 0

        for idx in indices where idx >= 0 && idx < document.pageCount {
            guard let page = document.page(at: idx) else {
                skipped += 1
                continue
            }
            let bounds = page.bounds(for: .cropBox)
            let newBounds = CGRect(
                x: bounds.origin.x + max(0, left),
                y: bounds.origin.y + max(0, bottom),
                width: bounds.width - max(0, left) - max(0, right),
                height: bounds.height - max(0, top) - max(0, bottom)
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

    func resize(document: PDFDocument, indices: [Int], targetSize: CGSize) -> CropResult {
        var modified = 0
        var skipped = 0

        for idx in indices where idx >= 0 && idx < document.pageCount {
            guard let page = document.page(at: idx) else {
                skipped += 1
                continue
            }
            page.setBounds(CGRect(origin: .zero, size: targetSize), for: .mediaBox)
            page.setBounds(CGRect(origin: .zero, size: targetSize), for: .cropBox)
            modified += 1
        }

        return CropResult(pagesModified: modified, pagesSkipped: skipped)
    }
}
