import SwiftUI
import PDFKit

struct PageNumberOptionsView: View {
    let url: URL
    let document: PDFDocument
    let onBack: () -> Void
    let onFilesDropped: ([URL]) -> Void
    var onMutate: (() -> Void)?
    @Binding var currentPage: Int

    @State private var position: PDFPageNumberer.Position = .bottomCenter
    @State private var startNumber: Int = 1
    @State private var fontSize: CGFloat = 11
    @State private var prefix: String = ""
    @State private var suffix: String = ""
    @State private var color: Color = .black
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

    private var previewText: String {
        "\(prefix)\(startNumber + currentPage)\(suffix)"
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: preview with number overlay
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
                    Text(String(localized: "Add Page Numbers"))
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
                    label: String(localized: "Number all pages")
                )

                Divider()

                // Position picker
                HStack {
                    Text(String(localized: "Position"))
                        .font(.callout)
                    Spacer()
                    Picker("", selection: $position) {
                        ForEach(PDFPageNumberer.Position.allCases) { pos in
                            Text(pos.title).tag(pos)
                        }
                    }
                    .frame(width: 160)
                }

                // Start number
                HStack {
                    Text(String(localized: "Start at"))
                        .font(.callout)
                    TextField("1", value: $startNumber, format: .number)
                        .frame(width: 50)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(String(localized: "Starting page number"))
                    Spacer()
                }

                // Font size
                HStack {
                    Text(String(localized: "Size"))
                        .font(.callout)
                    Slider(value: $fontSize, in: 8...24, step: 1)
                    Text("\(Int(fontSize)) pt")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 35)
                }

                // Color picker
                HStack {
                    Text(String(localized: "Color"))
                        .font(.callout)
                    Spacer()
                    ColorPicker("", selection: $color, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 40)
                }

                // Prefix/suffix
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Text(String(localized: "Prefix"))
                            .font(.callout)
                        TextField("", text: $prefix)
                            .frame(width: 50)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack(spacing: 4) {
                        Text(String(localized: "Suffix"))
                            .font(.callout)
                        TextField("", text: $suffix)
                            .frame(width: 50)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                // Preview showing formatted number and position
                HStack(spacing: 4) {
                    Text(String(localized: "Preview:"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\"\(previewText)\"")
                        .font(.caption.bold())
                        .foregroundStyle(color)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(position.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack {
                    Spacer()
                    Button(String(localized: "Save")) { save() }
                        .keyboardShortcut("s")
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isProcessing)
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
        .onAppear { updatePreviewAnnotation() }
        .onDisappear { removePreviewAnnotation() }
        .onChange(of: position) { updatePreviewAnnotation() }
        .onChange(of: startNumber) { updatePreviewAnnotation() }
        .onChange(of: fontSize) { updatePreviewAnnotation() }
        .onChange(of: prefix) { updatePreviewAnnotation() }
        .onChange(of: suffix) { updatePreviewAnnotation() }
        .onChange(of: color) { updatePreviewAnnotation() }
        .onChange(of: currentPage) { updatePreviewAnnotation() }
    }

    // MARK: - Preview Annotation

    private func updatePreviewAnnotation() {
        removePreviewAnnotation()

        guard let page = document.page(at: currentPage) else { return }

        let font = NSFont(name: "Helvetica", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let nsColor = NSColor(color)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: nsColor]
        let textSize = (previewText as NSString).size(withAttributes: attrs)
        let pageBounds = page.bounds(for: .cropBox)

        let padding: CGFloat = 4
        let width = textSize.width + padding * 2
        let height = textSize.height + padding * 2
        let margin: CGFloat = 36

        let x: CGFloat
        let y: CGFloat
        switch position {
        case .bottomLeft:   x = pageBounds.minX + margin; y = pageBounds.minY + margin
        case .bottomCenter: x = pageBounds.midX - width / 2; y = pageBounds.minY + margin
        case .bottomRight:  x = pageBounds.maxX - margin - width; y = pageBounds.minY + margin
        case .topLeft:      x = pageBounds.minX + margin; y = pageBounds.maxY - margin - height
        case .topCenter:    x = pageBounds.midX - width / 2; y = pageBounds.maxY - margin - height
        case .topRight:     x = pageBounds.maxX - margin - width; y = pageBounds.maxY - margin - height
        }

        let rect = CGRect(x: x, y: y, width: width, height: height)
        let annotation = PDFAnnotation(bounds: rect, forType: .freeText, withProperties: nil)
        annotation.font = font
        annotation.fontColor = nsColor
        annotation.color = .clear
        annotation.contents = previewText
        annotation.alignment = .center
        let border = PDFBorder()
        border.lineWidth = 0
        annotation.border = border

        page.addAnnotation(annotation)
        previewAnnotation = annotation
    }

    private func removePreviewAnnotation() {
        if let annotation = previewAnnotation, let page = annotation.page {
            page.removeAnnotation(annotation)
        }
        previewAnnotation = nil
    }

    private func save() {
        // Remove preview annotation so it doesn't interfere with the source
        removePreviewAnnotation()

        let suggestedName = url.deletingPathExtension().lastPathComponent + "_numbered.pdf"
        guard let destination = FileDialogHelper.showSavePanel(suggestedName: suggestedName) else {
            updatePreviewAnnotation()
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
            return
        }

        isProcessing = true
        progress = 0
        resultMessage = nil
        isError = false
        onMutate?()

        let nsColor = NSColor(color)

        operationTask = Task {
            defer { operationTask = nil; isProcessing = false }
            do {
                let numberer = PDFPageNumberer()
                let options = PDFPageNumberer.Options(
                    position: position,
                    startNumber: startNumber,
                    fontSize: fontSize,
                    prefix: prefix,
                    suffix: suffix,
                    color: nsColor
                )
                try await numberer.addPageNumbers(
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
