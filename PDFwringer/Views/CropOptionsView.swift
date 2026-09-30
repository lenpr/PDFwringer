import SwiftUI
import PDFKit

struct CropOptionsView: View {
    let url: URL
    let document: PDFDocument
    let onBack: () -> Void
    let onFilesDropped: ([URL]) -> Void
    var onDirtyChange: ((Bool) -> Void)?
    @Binding var currentPage: Int

    @State private var cropTop: Double = 0
    @State private var cropBottom: Double = 0
    @State private var cropLeft: Double = 0
    @State private var cropRight: Double = 0

    @State private var selectedPaperSize: PaperSize = .a4
    @State private var landscape = false

    @State private var pageSelection = PageSelection()
    @State private var shakeOffset: CGFloat = 0

    @State private var resultMessage: String?
    @State private var isError = false
    @State private var lastOutputURL: URL?
    @State private var isDropTargeted = false
    @State private var documentGeneration = 0
    @State private var workingCopyHasChanges = false
    @State private var resizePending = false
    @State private var showingResizeGuide = false
    @State private var isWarning = false

    private var hasPendingCrop: Bool {
        [cropTop, cropBottom, cropLeft, cropRight].contains { $0 != 0 }
    }
    private var hasPendingSettings: Bool { hasPendingCrop || resizePending }
    private var hasUnsavedChanges: Bool { workingCopyHasChanges || hasPendingSettings }

    private let cropper = PDFCropper()

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                CropPreviewPanel(
                    document: document,
                    currentPage: $currentPage,
                    generation: documentGeneration,
                    cropInsets: NSEdgeInsets(
                        top: !pageSelection.includes(currentPage) || showingResizeGuide ? 0 : max(0, cropTop),
                        left: !pageSelection.includes(currentPage) || showingResizeGuide ? 0 : max(0, cropLeft),
                        bottom: !pageSelection.includes(currentPage) || showingResizeGuide ? 0 : max(0, cropBottom),
                        right: !pageSelection.includes(currentPage) || showingResizeGuide ? 0 : max(0, cropRight)
                    ),
                    resizeTarget: pageSelection.includes(currentPage) && showingResizeGuide && resizePending ? computedResizeTarget : nil
                )

                PageThumbnailStripView(
                    document: document,
                    currentPage: $currentPage,
                    selectedPages: pageSelection.appliesToAll ? nil : $pageSelection.selectedPages
                )
                .id(documentGeneration)
                .padding(.horizontal, 20)
            }
            .frame(minWidth: 260, idealWidth: 320)
            .overlay {
                DropReceiverView(isTargeted: $isDropTargeted) { urls in
                    onFilesDropped(urls)
                }
            }

            Divider()

            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        OptionsHeaderView(url: url, onBack: onBack)

                        HStack {
                            Text(String(localized: "Crop / Resize"))
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
                            selection: $pageSelection,
                            shakeOffset: $shakeOffset
                        )

                        Divider()

                        // Crop margins section
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(localized: "Crop margins (points)"))
                                .font(.callout.weight(.medium))

                            Grid(horizontalSpacing: 16, verticalSpacing: 8) {
                                GridRow {
                                    marginField(String(localized: "Top"), value: $cropTop)
                                    marginField(String(localized: "Bottom"), value: $cropBottom)
                                }
                                GridRow {
                                    marginField(String(localized: "Left"), value: $cropLeft)
                                    marginField(String(localized: "Right"), value: $cropRight)
                                }
                            }
                            Button(String(localized: "Apply Crop")) { applyCrop() }
                                .buttonStyle(.bordered)
                                .disabled(!hasPendingCrop)

                        }

                        Divider()

                        // Resize section
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(localized: "Set page size"))
                                .font(.callout.weight(.medium))

                            HStack(spacing: 12) {
                                Picker(String(localized: "Page size"), selection: $selectedPaperSize) {
                                    ForEach(PaperSize.allCases) { size in
                                        Text(size.rawValue).tag(size)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 80)

                                Toggle(String(localized: "Landscape"), isOn: $landscape)
                                    .toggleStyle(.checkbox)
                                    .font(.caption)

                            }
                            Button(String(localized: "Apply Page Size")) { applyResize() }
                                .buttonStyle(.bordered)

                            Text(String(localized: "Changes the page bounds without scaling content. Content outside the new bounds may be hidden."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if hasPendingSettings {
                            Text(String(localized: "Guide only — apply the pending changes before saving."))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Button(String(localized: "Discard Pending Changes")) {
                                cropTop = 0; cropBottom = 0; cropLeft = 0; cropRight = 0
                                resizePending = false
                                showingResizeGuide = false
                                clearFeedback()
                            }
                            .buttonStyle(.bordered)
                        }

                        // Save button
                        HStack {
                            Spacer()
                            Button(String(localized: "Save Copy…")) { saveCropped() }
                                .keyboardShortcut("s")
                                .controlSize(.large)
                                .buttonStyle(.borderedProminent)
                        }

                        if let msg = resultMessage {
                            ResultMessageView(
                                message: msg,
                                isError: isError,
                                outputURL: lastOutputURL,
                                onRetry: nil,
                                isWarning: isWarning
                            )
                        }

                        Spacer()
                    }
                    .padding(24)
                    .frame(maxWidth: 520, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: resultMessage) { _, message in
                    if message != nil { scroll.scrollTo("operation-result", anchor: .bottom) }
                }
            }
            .frame(minWidth: 300, idealWidth: 340)
            .tint(.coral)
        }
        .onChange(of: [cropTop, cropBottom, cropLeft, cropRight]) { _, values in
            if values.contains(where: { $0 != 0 }) { showingResizeGuide = false; clearFeedback() }
        }
        .onChange(of: selectedPaperSize) { _, _ in resizePending = true; showingResizeGuide = true; clearFeedback() }
        .onChange(of: landscape) { _, _ in resizePending = true; showingResizeGuide = true; clearFeedback() }
        .onChange(of: pageSelection) { _, _ in clearFeedback() }
        .onChange(of: hasUnsavedChanges) { _, dirty in onDirtyChange?(dirty) }
    }

    private func marginField(_ label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField("0", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("\(label) margin in points")
        }
    }

    private func clearFeedback() {
        resultMessage = nil
        lastOutputURL = nil
        isError = false
        isWarning = false
    }

    private var computedResizeTarget: CGSize? {
        let paperSize = selectedPaperSize.size
        let target = landscape
            ? CGSize(width: paperSize.height, height: paperSize.width)
            : paperSize
        guard let page = document.page(at: currentPage) else { return target }
        let current = page.bounds(for: .cropBox).size
        let pageTarget = PDFCropGeometry.pageSpaceSize(for: target, rotation: page.rotation)
        if abs(current.width - pageTarget.width) < 1 && abs(current.height - pageTarget.height) < 1 {
            return nil
        }
        return target
    }

    private var targetIndices: [Int]? {
        pageSelection.resolvedIndices(pageCount: document.pageCount)
    }

    private func applyCrop() {
        clearFeedback()
        guard let indices = targetIndices else {
            Formatting.triggerShake($shakeOffset)
            return
        }

        let result: PDFCropper.CropResult
        do {
            result = try cropper.crop(
                document: document,
                indices: indices,
                top: cropTop,
                bottom: cropBottom,
                left: cropLeft,
                right: cropRight
            )
        } catch {
            resultMessage = PDFwringerError.userMessage(for: error)
            isError = true
            return
        }

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
        isWarning = result.pagesSkipped > 0
        if result.pagesModified > 0 { workingCopyHasChanges = true }
    }

    private func applyResize() {
        clearFeedback()
        guard let indices = targetIndices else {
            Formatting.triggerShake($shakeOffset)
            return
        }

        let paperSize = selectedPaperSize.size
        let targetSize = landscape
            ? CGSize(width: paperSize.height, height: paperSize.width)
            : paperSize

        let result: PDFCropper.CropResult
        do {
            result = try cropper.resize(
                document: document,
                indices: indices,
                targetSize: targetSize
            )
        } catch {
            resultMessage = PDFwringerError.userMessage(for: error)
            isError = true
            return
        }
        resizePending = false
        documentGeneration += 1
        resultMessage = nil
        isError = false
        isWarning = result.pagesSkipped > 0
        if result.pagesModified > 0 { workingCopyHasChanges = true }
    }

    private func saveCropped() {
        guard !hasPendingSettings else {
            resultMessage = String(localized: "Apply or discard the pending changes before saving. Nothing saved.")
            isError = false
            isWarning = true
            lastOutputURL = nil
            return
        }
        let suggestedName = url.deletingPathExtension().lastPathComponent + "_cropped.pdf"
        guard let destination = FileDialogHelper.showSavePanel(suggestedName: suggestedName) else { return }

        resultMessage = nil
        isError = false

        let result = DocumentSaver.save(document: document, source: url, to: destination)
        resultMessage = result.message
        isError = result.isError
        lastOutputURL = result.outputURL
        isWarning = false
        if !result.isError { workingCopyHasChanges = false }
    }
}
