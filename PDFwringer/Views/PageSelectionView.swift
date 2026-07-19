import SwiftUI

struct PageSelectionView: View {
    let pageCount: Int
    @Binding var selection: PageSelection
    @Binding var shakeOffset: CGFloat

    @State private var pageRangeText = ""
    @State private var selectionProducedByText: Set<Int>?

    var label: String = String(localized: "Apply to all pages")

    var body: some View {
        Group {
            Toggle(isOn: $selection.appliesToAll) {
                Text(label)
                    .font(.callout)
            }
            .toggleStyle(.checkbox)
            .accessibilityLabel(label)

            if !selection.appliesToAll {
                HStack {
                    TextField(String(localized: "e.g. 1, 3-5, 8-"), text: $pageRangeText)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(String(localized: "Page range"))
                        .accessibilityHint(String(localized: "Enter page numbers or ranges separated by commas"))
                        .offset(x: shakeOffset)
                        .onChange(of: pageRangeText) {
                            var updatedSelection = selection
                            updatedSelection.update(from: pageRangeText, pageCount: pageCount)
                            selectionProducedByText = updatedSelection.selectedPages
                            selection.selectedPages = updatedSelection.selectedPages
                        }
                }
                Text(String(localized: "Tap thumbnails or type page numbers"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .onAppear {
            pageRangeText = PageSelection.formatted(selection.selectedPages)
        }
        .onChange(of: selection.selectedPages) {
            if selectionProducedByText == selection.selectedPages {
                selectionProducedByText = nil
                return
            }
            pageRangeText = PageSelection.formatted(selection.selectedPages)
        }
    }
}
