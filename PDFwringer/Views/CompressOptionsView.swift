import SwiftUI
import PDFKit

struct CompressOptionsView: View {
    let url: URL
    let document: PDFDocument
    let onBack: () -> Void
    let onFilesDropped: ([URL]) -> Void
    @Binding var currentPage: Int

    @State private var vm = CompressViewModel()
    @State private var isDropTargeted = false
    @Namespace private var qualityNamespace

    var body: some View {
        HStack(spacing: 0) {
            // Left: PDF preview + thumbnails
            VStack(spacing: 0) {
                PDFPreviewPanel(document: document, currentPage: $currentPage)

                PageThumbnailStripView(document: document, currentPage: $currentPage)
                    .padding(.horizontal, 20)
            }
            .frame(minWidth: 260, idealWidth: 320)
            .overlay {
                DropReceiverView(isTargeted: $isDropTargeted) { urls in
                    onFilesDropped(urls)
                }
            }

            Divider()

            // Right: Compression options
            VStack(alignment: .leading, spacing: 16) {
                OptionsHeaderView(url: url, onBack: onBack)

                HStack {
                    Text(String(localized: "Compress"))
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(vm.sourcePageCount) pages, \(Formatting.fileSize(vm.sourceFileSize))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }

                Divider()

                // Compression level options
                ForEach(CompressionLevel.allCases) { level in
                    let key = "\(level.rawValue)-\(vm.selectedQuality.rawValue)-\(vm.grayscale)"
                    let estimatedSize = vm.estimatedSizes[key]
                    let heuristicSize = vm.heuristicSizes[key]
                    let displaySize = estimatedSize ?? heuristicSize
                    let isHeuristic = estimatedSize == nil && heuristicSize != nil

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: vm.selectedLevel == level ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(vm.selectedLevel == level ? .coral : .secondary)
                            .font(.body)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            let exceedsOriginal = displaySize.map { $0 >= vm.sourceFileSize && vm.sourceFileSize > 0 } ?? false
                            HStack(alignment: .firstTextBaseline) {
                                Text(level.title)
                                    .font(.body.weight(.medium))
                                Spacer()
                                if let size = displaySize {
                                    HStack(spacing: 4) {
                                        if exceedsOriginal {
                                            Image(systemName: "arrow.up")
                                                .font(.caption2)
                                        }
                                        Text(isHeuristic ? "~\(Formatting.fileSize(size))" : Formatting.fileSize(size))
                                            .font(.caption)
                                            .strikethrough(exceedsOriginal)
                                    }
                                    .foregroundStyle(exceedsOriginal ? .red : .secondary)
                                    .contentTransition(.numericText())
                                } else if vm.sourceFileSize > 0 {
                                    ProgressView()
                                        .controlSize(.mini)
                                }
                            }
                            Text(exceedsOriginal ? String(localized: "Larger than original") : level.subtitle)
                                .font(.caption)
                                .foregroundStyle(exceedsOriginal ? .red.opacity(0.8) : .secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        vm.selectedLevel = level
                        vm.onSettingsChanged()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("\(level.title): \(level.subtitle)")
                    .accessibilityValue(vm.selectedLevel == level ? "Selected" : "")
                }

                if vm.selectedLevel.isRasterize {
                    Divider()

                    Text(String(localized: "JPEG Quality"))
                        .font(.subheadline.weight(.medium))

                    HStack(spacing: 12) {
                        ForEach(JPEGQuality.allCases) { q in
                            Text(q.title)
                                .font(.caption.weight(vm.selectedQuality == q ? .bold : .regular))
                                .foregroundColor(vm.selectedQuality == q ? .coral : .primary)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background {
                                    if vm.selectedQuality == q {
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(Color.coral.opacity(0.12))
                                            .matchedGeometryEffect(id: "quality", in: qualityNamespace)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.spring(duration: 0.25)) {
                                        vm.selectedQuality = q
                                    }
                                    vm.onSettingsChanged()
                                }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityLabel("JPEG quality: \(q.title)")
                                .accessibilityValue(vm.selectedQuality == q ? "Selected" : "")
                        }
                    }
                }

                Divider()

                Toggle(isOn: Binding(
                    get: { vm.grayscale },
                    set: { vm.grayscale = $0; vm.onSettingsChanged() }
                )) {
                    Text(String(localized: "Convert to grayscale"))
                        .font(.callout)
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: Binding(
                    get: { vm.stripMetadata },
                    set: { vm.stripMetadata = $0 }
                )) {
                    Text(String(localized: "Strip all metadata"))
                        .font(.callout)
                }
                .toggleStyle(.checkbox)

                if let warning = vm.largeFileWarning {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Spacer()
                    Button(String(localized: "Compress")) {
                        Task { await vm.performCompression() }
                    }
                    .keyboardShortcut("s")
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!vm.canCompress)
                }

                if vm.isProcessing {
                    HStack(spacing: 8) {
                        ProgressView(value: vm.progress)
                            .progressViewStyle(.linear)
                        Button(String(localized: "Cancel")) { vm.cancel() }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                if let msg = vm.resultMessage {
                    ResultMessageView(
                        message: msg,
                        isError: vm.isError,
                        isWarning: vm.isWarning,
                        outputURL: vm.lastOutputURL,
                        onRetry: vm.isError ? { Task { await vm.performCompression() } } : nil
                    )
                }

                Spacer()
            }
            .padding(24)
            .frame(minWidth: 300, idealWidth: 340)
            .tint(.coral)
        }
        .onAppear {
            vm.setSource(url)
        }
    }
}
