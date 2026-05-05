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
        case .best: "Best"
        case .good: "Good"
        case .moderate: "Moderate"
        case .low: "Low"
        }
    }

    var subtitle: String {
        switch self {
        case .best: "Minimal artifacts, larger files"
        case .good: "Balanced quality and size"
        case .moderate: "Visible compression, smaller files"
        case .low: "Heavy compression, smallest files"
        }
    }

    var value: CGFloat {
        switch self {
        case .best: 0.90
        case .good: 0.75
        case .moderate: 0.55
        case .low: 0.35
        }
    }
}
