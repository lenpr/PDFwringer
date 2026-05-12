import Foundation

/// JPEG encoding quality presets used during rasterize compression.
enum JPEGQuality: String, CaseIterable, Identifiable {
    case best
    case good
    case moderate
    case low

    var id: String { rawValue }

    var title: String {
        switch self {
        case .best: String(localized: "Best")
        case .good: String(localized: "Good")
        case .moderate: String(localized: "Moderate")
        case .low: String(localized: "Low")
        }
    }

    var subtitle: String {
        switch self {
        case .best: String(localized: "Minimal artifacts, larger files")
        case .good: String(localized: "Balanced quality and size")
        case .moderate: String(localized: "Visible compression, smaller files")
        case .low: String(localized: "Heavy compression, smallest files")
        }
    }

    var value: CGFloat {
        switch self {
        case .best: 0.85
        case .good: 0.60
        case .moderate: 0.40
        case .low: 0.25
        }
    }
}
