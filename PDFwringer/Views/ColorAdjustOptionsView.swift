import SwiftUI
import PDFKit
import CoreImage

struct ColorAdjustOptionsView: View {
    let url: URL
    let document: PDFDocument
    let onBack: () -> Void
    let onFilesDropped: ([URL]) -> Void
    var onMutate: (() -> Void)?
    @Binding var currentPage: Int

    @State private var brightness: Float = 0
    @State private var contrast: Float = 1
    @State private var saturation: Float = 1

    @State private var applyAll = true
    @State private var pageRangeText = ""
    @State private var selectedPages: Set<Int> = []
    @State private var shakeOffset: CGFloat = 0

    @State private var previewImage: NSImage?
    @State private var previewTask: Task<Void, Never>?

    @State private var resultMessage: String?
    @State private var isError = false
    @State private var lastOutputURL: URL?
    @State private var isDropTargeted = false
    @State private var isSaving = false

    private var settings: PDFColorAdjuster.Settings {
        .init(brightness: brightness, contrast: contrast, saturation: saturation)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                previewPanel
                    .padding(20)

                PageThumbnailStripView(
                    document: document,
                    currentPage: $currentPage,
                    selectedPages: applyAll ? nil : $selectedPages
                )
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
                    Text("Adjust Colors")
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
                    label: "Adjust all pages"
                )

                Divider()

                sliderSection

                presetButtons

                Spacer()

                HStack {
                    Spacer()
                    Button("Save") { Task { await save() } }
                        .keyboardShortcut("s")
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(settings.isIdentity || isSaving)
                }

                if let msg = resultMessage {
                    ResultMessageView(
                        message: msg,
                        isError: isError,
                        outputURL: lastOutputURL,
                        onRetry: isError ? { Task { await save() } } : nil
                    )
                }
            }
            .padding(24)
            .frame(minWidth: 300, idealWidth: 340)
            .tint(.coral)
        }
        .onChange(of: currentPage) { updatePreview() }
        .onChange(of: brightness) { updatePreview() }
        .onChange(of: contrast) { updatePreview() }
        .onChange(of: saturation) { updatePreview() }
        .onAppear { updatePreview() }
    }

    // MARK: - Preview

    private var previewPanel: some View {
        Group {
            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: Color(nsColor: .shadowColor).opacity(0.15), radius: 8, y: 2)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .aspectRatio(0.707, contentMode: .fit)
                    .overlay {
                        ProgressView()
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func updatePreview() {
        previewTask?.cancel()
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }

            guard let pdfPage = document.page(at: currentPage) else { return }
            let cgPage = pdfPage.pageRef
            guard let page = cgPage else { return }

            let currentSettings = settings
            guard let (rendered, _) = PDFCompressor.renderPage(page, dpi: 150, grayscale: false) else { return }
            guard !Task.isCancelled else { return }

            let adjusted = PDFColorAdjuster.adjustImage(rendered, settings: currentSettings) ?? rendered
            guard !Task.isCancelled else { return }

            let nsImage = NSImage(cgImage: adjusted, size: NSSize(width: adjusted.width, height: adjusted.height))
            previewImage = nsImage
        }
    }

    // MARK: - Sliders

    private var sliderSection: some View {
        VStack(spacing: 12) {
            sliderRow(label: "Brightness", value: $brightness, range: -1...1)
            sliderRow(label: "Contrast", value: $contrast, range: 0.25...4.0)
            sliderRow(label: "Saturation", value: $saturation, range: 0...4.0)
        }
    }

    private func sliderRow(label: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.callout)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    // MARK: - Presets

    private var presetButtons: some View {
        HStack(spacing: 8) {
            ForEach(ColorPreset.allCases, id: \.self) { preset in
                Button(preset.title) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        brightness = preset.settings.brightness
                        contrast = preset.settings.contrast
                        saturation = preset.settings.saturation
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button("Reset") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    brightness = 0
                    contrast = 1
                    saturation = 1
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Save

    private func save() async {
        let suggestedName = url.deletingPathExtension().lastPathComponent + "_adjusted.pdf"
        guard let destination = FileDialogHelper.showSavePanel(suggestedName: suggestedName) else { return }

        resultMessage = nil
        isError = false
        isSaving = true
        onMutate?()

        let pages: [Int]?
        if applyAll {
            pages = nil
        } else if let parsed = try? PageRangeParser.parse(pageRangeText, pageCount: document.pageCount), !parsed.isEmpty {
            pages = parsed
        } else if !selectedPages.isEmpty {
            pages = Array(selectedPages.sorted())
        } else {
            Formatting.triggerShake($shakeOffset)
            isSaving = false
            return
        }

        do {
            let adjuster = PDFColorAdjuster()
            try await adjuster.adjust(
                source: url,
                destination: destination,
                settings: settings,
                pages: pages,
                dpi: 150,
                quality: 0.85,
                progress: { _ in }
            )
            resultMessage = "Saved."
            isError = false
            lastOutputURL = destination
        } catch {
            resultMessage = error.localizedDescription
            isError = true
        }

        isSaving = false
    }
}

// MARK: - Presets

enum ColorPreset: String, CaseIterable {
    case vivid
    case muted
    case blackAndWhite
    case highContrast

    var title: String {
        switch self {
        case .vivid: "Vivid"
        case .muted: "Muted"
        case .blackAndWhite: "B&W"
        case .highContrast: "Hi-Con"
        }
    }

    var settings: PDFColorAdjuster.Settings {
        switch self {
        case .vivid: .init(brightness: 0.05, contrast: 1.2, saturation: 1.5)
        case .muted: .init(brightness: 0, contrast: 0.9, saturation: 0.4)
        case .blackAndWhite: .init(brightness: 0, contrast: 1.1, saturation: 0)
        case .highContrast: .init(brightness: 0, contrast: 1.8, saturation: 1.0)
        }
    }
}
