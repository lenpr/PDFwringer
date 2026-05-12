import SwiftUI
import PDFKit

struct WatermarkOptionsView: View {
    let url: URL
    let document: PDFDocument
    let onBack: () -> Void
    let onFilesDropped: ([URL]) -> Void
    var onMutate: (() -> Void)?
    @Binding var currentPage: Int

    @State private var text: String = "DRAFT"
    @State private var fontSize: CGFloat = 60
    @State private var color: Color = .red
    @State private var opacity: CGFloat = 0.3
    @State private var rotation: CGFloat = -45
    @State private var position: PDFWatermarker.Position = .center
    @State private var applyAll = true
    @State private var pageRangeText = ""
    @State private var selectedPages: Set<Int> = []
    @State private var shakeOffset: CGFloat = 0

    @State private var isProcessing = false
    @State private var progress: Double = 0
    @State private var resultMessage: String?
    @State private var isError = false
    @State private var lastOutputURL: URL?
    @State private var isDropTargeted = false
    @State private var operationTask: Task<Void, Never>?
    @State private var previewAnnotation: PDFAnnotation?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                PDFPreviewPanel(document: document, currentPage: $currentPage)

                PageThumbnailStripView(
                    document: document,
                    currentPage: $currentPage,
                    selectedPages: applyAll ? nil : $selectedPages
                )
                .padding(.horizontal, 20)
            }
            .frame(minWidth: 260, idealWidth: 320)
            .overlay {
                DropReceiverView(isTargeted: $isDropTargeted) { urls in onFilesDropped(urls) }
            }

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                OptionsHeaderView(url: url, onBack: onBack)

                HStack {
                    Text(String(localized: "Add Watermark"))
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(document.pageCount) pages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                PageSelectionView(
                    pageCount: document.pageCount,
                    applyAll: $applyAll,
                    pageRangeText: $pageRangeText,
                    selectedPages: $selectedPages,
                    shakeOffset: $shakeOffset,
                    label: String(localized: "Watermark all pages")
                )

                Divider()

                // Watermark text
                HStack {
                    Text(String(localized: "Text"))
                        .font(.callout)
                    TextField(String(localized: "DRAFT"), text: $text)
                        .textFieldStyle(.roundedBorder)
                }

                // Position
                HStack {
                    Text(String(localized: "Position"))
                        .font(.callout)
                    Spacer()
                    Picker("", selection: $position) {
                        ForEach(PDFWatermarker.Position.allCases) { pos in
                            Text(pos.title).tag(pos)
                        }
                    }
                    .frame(width: 140)
                }

                // Font size
                HStack {
                    Text(String(localized: "Size"))
                        .font(.callout)
                    Slider(value: $fontSize, in: 20...120, step: 2)
                    Text("\(Int(fontSize)) pt")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 40)
                }

                // Opacity
                HStack {
                    Text(String(localized: "Opacity"))
                        .font(.callout)
                    Slider(value: $opacity, in: 0.05...0.8)
                    Text("\(Int(opacity * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 35)
                }

                // Rotation
                HStack {
                    Text(String(localized: "Angle"))
                        .font(.callout)
                    Slider(value: $rotation, in: -90...90, step: 5)
                    Text("\(Int(rotation))°")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 35)
                }

                // Color
                HStack {
                    Text(String(localized: "Color"))
                        .font(.callout)
                    Spacer()
                    ColorPicker("", selection: $color, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 40)
                }

                Spacer()

                HStack {
                    Spacer()
                    Button(String(localized: "Save")) { save() }
                        .keyboardShortcut("s")
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(text.isEmpty || isProcessing)
                }

                if isProcessing {
                    HStack(spacing: 8) {
                        ProgressView(value: progress).progressViewStyle(.linear)
                        Button(String(localized: "Cancel")) { operationTask?.cancel() }
                            .buttonStyle(.plain).foregroundStyle(.secondary).font(.caption)
                    }
                }

                if let msg = resultMessage {
                    ResultMessageView(
                        message: msg,
                        isError: isError,
                        outputURL: lastOutputURL
                    )
                }
            }
            .padding(24)
            .frame(minWidth: 300, idealWidth: 340)
            .tint(.coral)
        }
        .onAppear { updatePreview() }
        .onDisappear { removePreview() }
        .onChange(of: text) { updatePreview() }
        .onChange(of: fontSize) { updatePreview() }
        .onChange(of: color) { updatePreview() }
        .onChange(of: opacity) { updatePreview() }
        .onChange(of: rotation) { updatePreview() }
        .onChange(of: position) { updatePreview() }
        .onChange(of: currentPage) { updatePreview() }
    }

    // MARK: - Preview

    private func updatePreview() {
        removePreview()
        guard !text.isEmpty, let page = document.page(at: currentPage) else { return }

        let font = NSFont(name: "Helvetica-Bold", size: min(fontSize, 40)) ?? NSFont.boldSystemFont(ofSize: min(fontSize, 40))
        let nsColor = NSColor(color).withAlphaComponent(opacity)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: nsColor]
        let textSize = (text as NSString).size(withAttributes: attrs)

        let pageBounds = page.bounds(for: .cropBox)
        let cx: CGFloat
        let cy: CGFloat
        switch position {
        case .center:     cx = pageBounds.midX; cy = pageBounds.midY
        case .topLeft:    cx = pageBounds.minX + 80; cy = pageBounds.maxY - 80
        case .topRight:   cx = pageBounds.maxX - 80; cy = pageBounds.maxY - 80
        case .bottomLeft: cx = pageBounds.minX + 80; cy = pageBounds.minY + 80
        case .bottomRight:cx = pageBounds.maxX - 80; cy = pageBounds.minY + 80
        }

        let rect = CGRect(x: cx - textSize.width / 2, y: cy - textSize.height / 2, width: textSize.width, height: textSize.height)
        let annotation = PDFAnnotation(bounds: rect, forType: .freeText, withProperties: nil)
        annotation.font = font
        annotation.fontColor = nsColor
        annotation.color = .clear
        annotation.contents = text
        annotation.alignment = .center
        let border = PDFBorder()
        border.lineWidth = 0
        annotation.border = border

        page.addAnnotation(annotation)
        previewAnnotation = annotation
    }

    private func removePreview() {
        if let annotation = previewAnnotation, let page = annotation.page {
            page.removeAnnotation(annotation)
        }
        previewAnnotation = nil
    }

    // MARK: - Save

    private func save() {
        removePreview()

        let suggestedName = url.deletingPathExtension().lastPathComponent + "_watermarked.pdf"
        guard let destination = FileDialogHelper.showSavePanel(suggestedName: suggestedName) else {
            updatePreview()
            return
        }

        let pages: [Int]?
        if applyAll {
            pages = nil
        } else if let parsed = try? PageRangeParser.parse(pageRangeText, pageCount: document.pageCount), !parsed.isEmpty {
            pages = parsed
        } else if !selectedPages.isEmpty {
            pages = Array(selectedPages.sorted())
        } else {
            Formatting.triggerShake($shakeOffset)
            updatePreview()
            return
        }

        isProcessing = true
        progress = 0
        resultMessage = nil
        isError = false
        onMutate?()

        let nsColor = NSColor(color)

        operationTask = Task {
            defer { operationTask = nil; isProcessing = false; updatePreview() }
            do {
                let watermarker = PDFWatermarker()
                let options = PDFWatermarker.Options(
                    text: text,
                    fontSize: fontSize,
                    color: nsColor,
                    opacity: opacity,
                    rotation: rotation,
                    position: position
                )
                try await watermarker.addWatermark(
                    source: url, destination: destination,
                    options: options, pageIndices: pages,
                    progress: { p in progress = p }
                )
                resultMessage = String(localized: "Saved.")
                isError = false
                lastOutputURL = destination
            } catch is CancellationError {
                resultMessage = String(localized: "Cancelled.")
                isError = false
            } catch {
                resultMessage = error.localizedDescription
                isError = true
            }
        }
    }
}
