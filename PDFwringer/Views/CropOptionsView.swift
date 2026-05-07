import SwiftUI
import PDFKit

enum PaperSize: String, CaseIterable, Identifiable {
    case a4 = "A4"
    case letter = "Letter"
    case a5 = "A5"
    case legal = "Legal"

    var id: String { rawValue }

    var size: CGSize {
        switch self {
        case .a4: CGSize(width: 595.28, height: 841.89)
        case .letter: CGSize(width: 612, height: 792)
        case .a5: CGSize(width: 419.53, height: 595.28)
        case .legal: CGSize(width: 612, height: 1008)
        }
    }
}

struct CropOptionsView: View {
    let url: URL
    let document: PDFDocument
    let onBack: () -> Void
    let onFilesDropped: ([URL]) -> Void
    var onMutate: (() -> Void)?
    @Binding var currentPage: Int

    @State private var cropTop: Double = 0
    @State private var cropBottom: Double = 0
    @State private var cropLeft: Double = 0
    @State private var cropRight: Double = 0

    @State private var selectedPaperSize: PaperSize = .a4
    @State private var landscape = false

    @State private var cropAll = true
    @State private var pageRangeText = ""
    @State private var selectedPages: Set<Int> = []
    @State private var syncingFromThumbnails = false

    @State private var resultMessage: String?
    @State private var isError = false
    @State private var lastOutputURL: URL?
    @State private var isDropTargeted = false
    @State private var documentGeneration = 0
    @State private var shakeOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                PDFPreviewPanel(document: document, currentPage: $currentPage, generation: documentGeneration)

                PageThumbnailStripView(
                    document: document,
                    currentPage: $currentPage,
                    selectedPages: cropAll ? nil : $selectedPages
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
                    Text("Crop / Resize")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(document.pageCount) pages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }

                Divider()

                // Page selection
                Toggle(isOn: $cropAll) {
                    Text("Apply to all pages")
                        .font(.callout)
                }
                .toggleStyle(.checkbox)

                if !cropAll {
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
                    Text("Tap thumbnails or type page numbers")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Divider()

                // Crop margins section
                VStack(alignment: .leading, spacing: 6) {
                    Text("Crop margins (points)")
                        .font(.callout.weight(.medium))

                    HStack(spacing: 12) {
                        VStack(spacing: 2) {
                            Text("Top").font(.caption2).foregroundStyle(.secondary)
                            TextField("0", value: $cropTop, format: .number)
                                .frame(width: 50)
                                .textFieldStyle(.roundedBorder)
                        }
                        VStack(spacing: 2) {
                            Text("Bottom").font(.caption2).foregroundStyle(.secondary)
                            TextField("0", value: $cropBottom, format: .number)
                                .frame(width: 50)
                                .textFieldStyle(.roundedBorder)
                        }
                        VStack(spacing: 2) {
                            Text("Left").font(.caption2).foregroundStyle(.secondary)
                            TextField("0", value: $cropLeft, format: .number)
                                .frame(width: 50)
                                .textFieldStyle(.roundedBorder)
                        }
                        VStack(spacing: 2) {
                            Text("Right").font(.caption2).foregroundStyle(.secondary)
                            TextField("0", value: $cropRight, format: .number)
                                .frame(width: 50)
                                .textFieldStyle(.roundedBorder)
                        }
                        Spacer()
                        Button("Crop") { applyCrop() }
                            .buttonStyle(.borderedProminent)
                            .disabled(cropTop == 0 && cropBottom == 0 && cropLeft == 0 && cropRight == 0)
                    }
                }

                Divider()

                // Resize section
                VStack(alignment: .leading, spacing: 6) {
                    Text("Resize to paper size")
                        .font(.callout.weight(.medium))

                    HStack(spacing: 12) {
                        Picker("", selection: $selectedPaperSize) {
                            ForEach(PaperSize.allCases) { size in
                                Text(size.rawValue).tag(size)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 80)

                        Toggle("Landscape", isOn: $landscape)
                            .toggleStyle(.checkbox)
                            .font(.caption)

                        Spacer()

                        Button("Resize") { applyResize() }
                            .buttonStyle(.borderedProminent)
                    }
                }

                // Save button
                HStack {
                    Spacer()
                    Button("Save") { Task { await saveCropped() } }
                        .keyboardShortcut("s")
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }

                if let msg = resultMessage {
                    ResultMessageView(
                        message: msg,
                        isError: isError,
                        outputURL: lastOutputURL,
                        onRetry: nil
                    )
                }

                Spacer()
            }
            .padding(24)
            .frame(minWidth: 300, idealWidth: 340)
        }
    }

    private var targetIndices: [Int]? {
        if cropAll {
            return Array(0..<document.pageCount)
        }
        if let parsed = try? PageRangeParser.parse(pageRangeText, pageCount: document.pageCount), !parsed.isEmpty {
            return parsed
        }
        if !selectedPages.isEmpty {
            return Array(selectedPages.sorted())
        }
        return nil
    }

    private func applyCrop() {
        guard let indices = targetIndices else {
            Formatting.triggerShake($shakeOffset)
            return
        }

        for idx in indices where idx >= 0 && idx < document.pageCount {
            guard let page = document.page(at: idx) else { continue }
            let bounds = page.bounds(for: .cropBox)
            let newBounds = CGRect(
                x: bounds.origin.x + cropLeft,
                y: bounds.origin.y + cropBottom,
                width: bounds.width - cropLeft - cropRight,
                height: bounds.height - cropTop - cropBottom
            )
            guard newBounds.width > 0 && newBounds.height > 0 else { continue }
            page.setBounds(newBounds, for: .cropBox)
        }
        documentGeneration += 1
        resultMessage = nil
        onMutate?()
    }

    private func applyResize() {
        guard let indices = targetIndices else {
            Formatting.triggerShake($shakeOffset)
            return
        }

        let targetSize: CGSize
        let paperSize = selectedPaperSize.size
        if landscape {
            targetSize = CGSize(width: paperSize.height, height: paperSize.width)
        } else {
            targetSize = paperSize
        }

        for idx in indices where idx >= 0 && idx < document.pageCount {
            guard let page = document.page(at: idx) else { continue }
            page.setBounds(CGRect(origin: .zero, size: targetSize), for: .mediaBox)
            page.setBounds(CGRect(origin: .zero, size: targetSize), for: .cropBox)
        }
        documentGeneration += 1
        resultMessage = nil
        onMutate?()
    }

    private func saveCropped() async {
        let suggestedName = url.deletingPathExtension().lastPathComponent + "_cropped.pdf"
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
