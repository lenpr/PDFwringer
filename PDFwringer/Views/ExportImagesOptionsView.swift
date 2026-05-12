import SwiftUI
import PDFKit

struct ExportImagesOptionsView: View {
    let url: URL
    let document: PDFDocument
    let onBack: () -> Void
    let onFilesDropped: ([URL]) -> Void
    @Binding var currentPage: Int

    @State private var format: PDFImageExporter.ImageFormat = .jpeg
    @State private var dpi: CGFloat = 150
    @State private var quality: CGFloat = 0.85
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
                    Text(String(localized: "Export as Images"))
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
                    label: String(localized: "Export all pages")
                )

                Divider()

                // Format selection
                HStack {
                    Text(String(localized: "Format"))
                        .font(.callout)
                    Spacer()
                    Picker("", selection: $format) {
                        ForEach(PDFImageExporter.ImageFormat.allCases) { f in
                            Text(f.title).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }

                // DPI
                HStack {
                    Text(String(localized: "Resolution"))
                        .font(.callout)
                    Spacer()
                    Picker("", selection: $dpi) {
                        Text("72 DPI").tag(CGFloat(72))
                        Text("150 DPI").tag(CGFloat(150))
                        Text("300 DPI").tag(CGFloat(300))
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }

                // JPEG quality (only for JPEG)
                if format == .jpeg {
                    HStack {
                        Text(String(localized: "Quality"))
                            .font(.callout)
                        Slider(value: $quality, in: 0.3...1.0)
                        Text("\(Int(quality * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 35)
                    }
                }

                Spacer()

                HStack {
                    Spacer()
                    Button(String(localized: "Export")) { exportImages() }
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
    }

    private func exportImages() {
        guard let outputDir = FileDialogHelper.showDirectoryPanel() else { return }

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

        operationTask = Task {
            defer { operationTask = nil; isProcessing = false }
            do {
                let exporter = PDFImageExporter()
                let options = PDFImageExporter.Options(format: format, dpi: dpi, quality: quality)
                let outputs = try await exporter.exportPages(
                    source: url, outputDirectory: outputDir,
                    options: options, pageIndices: pages,
                    progress: { p in progress = p }
                )
                resultMessage = String(localized: "Done! Exported \(outputs.count) images.")
                isError = false
                lastOutputURL = outputDir
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
