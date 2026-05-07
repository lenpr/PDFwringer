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
    @State private var syncingFromThumbnails = false
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
                    syncingFromThumbnails = true
                    pageRangeText = selectedPages.sorted().map { "\($0 + 1)" }.joined(separator: ", ")
                    syncingFromThumbnails = false
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
                HStack {
                    Button(action: onBack) {
                        Label("Back", systemImage: "chevron.left")
                            .font(.caption.weight(.medium))
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)

                    Spacer()

                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    Text("Rotate Pages")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(document.pageCount) pages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }

                Divider()

                // Page selection
                Toggle(isOn: $rotateAll) {
                    Text("Rotate all pages")
                        .font(.callout)
                }
                .toggleStyle(.checkbox)

                if !rotateAll {
                    HStack {
                        TextField("e.g. 1, 3-5, 8-", text: $pageRangeText)
                            .textFieldStyle(.roundedBorder)
                            .offset(x: shakeOffset)
                            .onChange(of: pageRangeText) {
                                guard !syncingFromThumbnails else { return }
                                if let indices = try? PageRangeParser.parse(pageRangeText, pageCount: document.pageCount) {
                                    selectedPages = Set(indices)
                                }
                            }
                    }
                    Text("Tap thumbnails or type page numbers, ranges, or comma-separated values")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 12) {
                    Button("90° CW") { rotateInPlace(angle: .ninety) }
                        .keyboardShortcut("r")
                    Button("180°") { rotateInPlace(angle: .oneEighty) }
                    Button("90° CCW") { rotateInPlace(angle: .twoSeventy) }
                        .keyboardShortcut("r", modifiers: [.command, .shift])

                    Spacer()

                    Button("Save") { Task { await saveRotated() } }
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

        guard let data = document.dataRepresentation() else {
            resultMessage = "Failed to serialize document."
            isError = true
            return
        }

        do {
            try AtomicFileWriter.write(to: destination) { tempURL in
                try data.write(to: tempURL)
                return true
            }
            resultMessage = "Saved."
            isError = false
            lastOutputURL = destination
        } catch {
            resultMessage = error.localizedDescription
            isError = true
        }
    }
}
