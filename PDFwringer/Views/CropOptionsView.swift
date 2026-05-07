import SwiftUI
import PDFKit

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

    @State private var applyAll = true
    @State private var pageRangeText = ""
    @State private var selectedPages: Set<Int> = []
    @State private var shakeOffset: CGFloat = 0

    @State private var resultMessage: String?
    @State private var isError = false
    @State private var lastOutputURL: URL?
    @State private var isDropTargeted = false
    @State private var documentGeneration = 0

    private static let coral = Color(red: 0.91, green: 0.39, blue: 0.30)
    private let cropper = PDFCropper()

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                CropPreviewPanel(
                    document: document,
                    currentPage: $currentPage,
                    generation: documentGeneration,
                    cropInsets: NSEdgeInsets(
                        top: max(0, cropTop),
                        left: max(0, cropLeft),
                        bottom: max(0, cropBottom),
                        right: max(0, cropRight)
                    ),
                    resizeTarget: computedResizeTarget
                )

                PageThumbnailStripView(
                    document: document,
                    currentPage: $currentPage,
                    selectedPages: applyAll ? nil : $selectedPages
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
                    Text("Crop / Resize")
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
                    applyAll: $applyAll,
                    pageRangeText: $pageRangeText,
                    selectedPages: $selectedPages,
                    shakeOffset: $shakeOffset
                )

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
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
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
            .tint(Self.coral)
        }
    }

    private var computedResizeTarget: CGSize? {
        let paperSize = selectedPaperSize.size
        let target = landscape
            ? CGSize(width: paperSize.height, height: paperSize.width)
            : paperSize
        guard let page = document.page(at: currentPage) else { return target }
        let current = page.bounds(for: .cropBox).size
        if abs(current.width - target.width) < 1 && abs(current.height - target.height) < 1 {
            return nil
        }
        return target
    }

    private var targetIndices: [Int]? {
        if applyAll {
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

        let result = cropper.crop(
            document: document,
            indices: indices,
            top: cropTop,
            bottom: cropBottom,
            left: cropLeft,
            right: cropRight
        )

        if result.pagesModified == 0 && result.pagesSkipped > 0 {
            Formatting.triggerShake($shakeOffset)
            resultMessage = "Crop exceeds page dimensions on all selected pages."
            isError = true
            return
        }

        cropTop = 0
        cropBottom = 0
        cropLeft = 0
        cropRight = 0
        documentGeneration += 1
        resultMessage = result.pagesSkipped > 0
            ? "Cropped \(result.pagesModified) pages (\(result.pagesSkipped) skipped — crop exceeds dimensions)."
            : nil
        isError = false
        onMutate?()
    }

    private func applyResize() {
        guard let indices = targetIndices else {
            Formatting.triggerShake($shakeOffset)
            return
        }

        let paperSize = selectedPaperSize.size
        let targetSize = landscape
            ? CGSize(width: paperSize.height, height: paperSize.width)
            : paperSize

        _ = cropper.resize(document: document, indices: indices, targetSize: targetSize)
        documentGeneration += 1
        resultMessage = nil
        isError = false
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
