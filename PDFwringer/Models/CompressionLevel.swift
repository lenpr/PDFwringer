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
        case .lossless: String(localized: "Lossless")
        case .high: String(localized: "High (300 dpi)")
        case .medium: String(localized: "Medium (150 dpi)")
        case .low: String(localized: "Low (72 dpi)")
        }
    }

    var subtitle: String {
        switch self {
        case .lossless: String(localized: "Strips metadata, preserves everything else")
        case .high: String(localized: "Print quality, good for archival")
        case .medium: String(localized: "Good for on-screen reading")
        case .low: String(localized: "Smallest size, good for email")
        }
    }

    var isRasterize: Bool {
        self != .lossless
    }

    /// Target render DPI. Only meaningful for rasterize levels; lossless returns 72 as a no-op sentinel.
    var dpi: CGFloat {
        switch self {
        case .lossless: 72
        case .high: 300
        case .medium: 150
        case .low: 72
        }
    }
}
