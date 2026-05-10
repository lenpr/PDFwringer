import SwiftUI
import PDFKit

struct RotateOptionsView: View {
    let url: URL
    let document: PDFDocument
    let onBack: () -> Void
    let onFilesDropped: ([URL]) -> Void
    var onMutate: (() -> Void)?
    @Binding var currentPage: Int

    @State private var pageRangeText: String = ""
    @State private var rotateAll = true
    @State private var selectedPages: Set<Int> = []
    @State private var resultMessage: String?
    @State private var isError = false
    @State private var isDropTargeted = false
    @State private var lastOutputURL: URL?
    @State private var shakeOffset: CGFloat = 0
    @State private var documentGeneration = 0

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                PDFPreviewPanel(document: document, currentPage: $currentPage, generation: documentGeneration)

                PageThumbnailStripView(
                    document: document,
                    currentPage: $currentPage,
                    selectedPages: rotateAll ? nil : $selectedPages
                )
                .id(documentGeneration)
                .padding(.horizontal, 20)
                .onChange(of: selectedPages) {
                    pageRangeText = selectedPages.sorted().map { "\($0 + 1)" }.joined(separator: ", ")
                }
            }
            .frame(minWidth: 260, idealWidth: 320)
            .overlay {
                DropReceiverView(isTargeted: $isDropTargeted) { urls in
                    onFilesDropped(urls)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                OptionsHeaderView(url: url, onBack: onBack)

                HStack {
                    Text(String(localized: "Rotate Pages"))
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(document.pageCount) pages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }

                Divider()

                PageSelectionView(
                    pageCount: document.pageCount,
                    applyAll: $rotateAll,
                    pageRangeText: $pageRangeText,
                    selectedPages: $selectedPages,
                    shakeOffset: $shakeOffset,
                    label: String(localized: "Rotate all pages")
                )

                HStack(spacing: 12) {
                    Button(String(localized: "90° CW")) { rotateInPlace(angle: .ninety) }
                        .keyboardShortcut("r")
                    Button(String(localized: "180°")) { rotateInPlace(angle: .oneEighty) }
                    Button(String(localized: "90° CCW")) { rotateInPlace(angle: .twoSeventy) }
                        .keyboardShortcut("r", modifiers: [.command, .shift])

                    Spacer()

                    Button(String(localized: "Save")) { Task { await saveRotated() } }
                        .keyboardShortcut("s")
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }

                if let msg = resultMessage {
                    ResultMessageView(
                        message: msg,
                        isError: isError,
                        outputURL: lastOutputURL,
                        onRetry: isError ? { Task { await saveRotated() } } : nil
                    )
                }

                Spacer()
            }
            .padding(24)
            .frame(minWidth: 300, idealWidth: 340)
            .tint(.coral)
        }
    }

    private func rotateInPlace(angle: PDFRotator.Angle) {
        let indices: [Int]
        if rotateAll {
            indices = Array(0..<document.pageCount)
        } else if let parsed = try? PageRangeParser.parse(pageRangeText, pageCount: document.pageCount), !parsed.isEmpty {
            indices = parsed
        } else if !selectedPages.isEmpty {
            indices = Array(selectedPages.sorted())
        } else {
            Formatting.triggerShake($shakeOffset)
            return
        }

        for idx in indices where idx >= 0 && idx < document.pageCount {
            if let page = document.page(at: idx) {
                page.rotation = (page.rotation + angle.rawValue) % 360
            }
        }
        documentGeneration += 1
        resultMessage = nil
        onMutate?()
    }

    private func saveRotated() async {
        let suggestedName = url.deletingPathExtension().lastPathComponent + "_rotated.pdf"
        guard let destination = FileDialogHelper.showSavePanel(suggestedName: suggestedName) else { return }

        resultMessage = nil
        isError = false

        let result = DocumentSaver.save(document: document, to: destination)
        resultMessage = result.message
        isError = result.isError
        lastOutputURL = result.outputURL
    }
}
