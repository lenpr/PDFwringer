import Foundation

/// Available compression strategies, from lossless metadata stripping to aggressive rasterization.
enum CompressionLevel: String, CaseIterable, Identifiable {
    case lossless
    case high
    case medium
    case low

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lossless: "Lossless"
        case .high: "High (300 dpi)"
        case .medium: "Medium (150 dpi)"
        case .low: "Low (72 dpi)"
        }
    }

    var subtitle: String {
        switch self {
        case .lossless: "Strips metadata, preserves everything else"
        case .high: "Print quality, good for archival"
        case .medium: "Good for on-screen reading"
        case .low: "Smallest size, good for email"
        }
    }

    var isRasterize: Bool {
        self != .lossless
    }

    var dpi: CGFloat {
        switch self {
        case .lossless: 72
        case .high: 300
        case .medium: 150
        case .low: 72
        }
    }
}
