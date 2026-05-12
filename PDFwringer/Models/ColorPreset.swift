import Foundation

/// Predefined color adjustment presets for quick one-tap application.
enum ColorPreset: String, CaseIterable {
    case vivid
    case muted
    case blackAndWhite
    case highContrast

    var title: String {
        switch self {
        case .vivid: String(localized: "Vivid")
        case .muted: String(localized: "Muted")
        case .blackAndWhite: String(localized: "B&W")
        case .highContrast: String(localized: "Hi-Con")
        }
    }

    var settings: PDFColorAdjuster.Settings {
        switch self {
        case .vivid: .init(brightness: 0.05, contrast: 1.2, saturation: 1.5)
        case .muted: .init(brightness: 0, contrast: 0.9, saturation: 0.4)
        case .blackAndWhite: .init(brightness: 0, contrast: 1.1, saturation: 0)
        case .highContrast: .init(brightness: 0, contrast: 1.8, saturation: 1.0)
        }
    }
}
