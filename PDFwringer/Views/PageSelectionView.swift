import SwiftUI
import Accessibility

struct PageSelectionView: View {
    let pageCount: Int
    @Binding var selection: PageSelection
    @Binding var shakeOffset: CGFloat

    @State private var pageRangeText = ""
    @State private var selectionProducedByText: Set<Int>?
    @State private var validationMessage: String?

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
                            validationMessage = updatedSelection.update(from: pageRangeText, pageCount: pageCount)
                            selectionProducedByText = updatedSelection.selectedPages
                            selection.selectedPages = updatedSelection.selectedPages
                        }
                }
                if let message = validationMessage ?? (selection.selectedPages.isEmpty ? String(localized: "Choose at least one page.") : nil) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                Text(String(localized: "Click a thumbnail to view it. Use its checkmark or type page numbers to select pages."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: validationMessage) { _, message in
            if let message, !selection.appliesToAll { AccessibilityNotification.Announcement(message).post() }
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
            validationMessage = selection.selectedPages.isEmpty ? String(localized: "Choose at least one page.") : nil
        }
    }
}
