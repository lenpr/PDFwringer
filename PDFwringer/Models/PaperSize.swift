import Foundation
import PDFKit

enum PaperSize: String, CaseIterable, Identifiable {
    case a4 = "A4"
    case letter = "Letter"
    case a5 = "A5"
    case legal = "Legal"

    var id: String { rawValue }

    var size: CGSize {
        switch self {
        case .a4: CGSize(width: 595.28, height: 841.89)
        case .letter: CGSize(width: 612, height: 792)
        case .a5: CGSize(width: 419.53, height: 595.28)
        case .legal: CGSize(width: 612, height: 1008)
        }
    }
}
