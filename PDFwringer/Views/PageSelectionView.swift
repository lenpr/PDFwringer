import SwiftUI
import PDFKit

struct PageSelectionView: View {
    let pageCount: Int
    @Binding var applyAll: Bool
    @Binding var pageRangeText: String
    @Binding var selectedPages: Set<Int>
    @Binding var shakeOffset: CGFloat

    @State private var syncingFromThumbnails = false

    var label: String = String(localized: "Apply to all pages")

    var body: some View {
        Toggle(isOn: $applyAll) {
            Text(label)
                .font(.callout)
        }
        .toggleStyle(.checkbox)
        .accessibilityLabel(label)

        if !applyAll {
            HStack {
                TextField(String(localized: "e.g. 1, 3-5, 8-"), text: $pageRangeText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(String(localized: "Page range"))
                    .accessibilityHint(String(localized: "Enter page numbers or ranges separated by commas"))
                    .offset(x: shakeOffset)
                    .onChange(of: pageRangeText) {
                        guard !syncingFromThumbnails else { return }
                        if let indices = try? PageRangeParser.parse(pageRangeText, pageCount: pageCount) {
                            selectedPages = Set(indices)
                        }
                    }
            }
            Text(String(localized: "Tap thumbnails or type page numbers"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    func syncFromThumbnails() {
        syncingFromThumbnails = true
        pageRangeText = selectedPages.sorted().map { "\($0 + 1)" }.joined(separator: ", ")
        syncingFromThumbnails = false
    }

    func resolveIndices() -> [Int]? {
        if applyAll {
            return Array(0..<pageCount)
        }
        if let parsed = try? PageRangeParser.parse(pageRangeText, pageCount: pageCount), !parsed.isEmpty {
            return parsed
        }
        if !selectedPages.isEmpty {
            return Array(selectedPages.sorted())
        }
        return nil
    }
}
