import SwiftUI
import PDFKit

struct CompressOptionsView: View {
    @Environment(AppViewModel.self) private var appVM
    let url: URL
    let document: PDFDocument
    let onBack: () -> Void
    let onFilesDropped: ([URL]) -> Void
    @Binding var currentPage: Int

    @State private var vm = CompressViewModel()
    @State private var isDropTargeted = false
    @Namespace private var qualityNamespace

    private var comparisonDocument: PDFDocument {
        vm.comparisonShowsResult ? (vm.prepared?.previewDocument ?? document) : document
    }

    private func compressionDescription(_ level: CompressionLevel, size: Int64?, heuristic: Bool) -> String {
        var parts = [level.title, level.subtitle]
        if let size {
            parts.append(heuristic ? String(localized: "Approximate size: \(Formatting.fileSize(size))")
                                   : String(localized: "Estimated size: \(Formatting.fileSize(size))"))
            if size >= vm.sourceFileSize && vm.sourceFileSize > 0 {
                parts.append(String(localized: "Larger than original"))
            }
        }
        return parts.joined(separator: ". ")
    }

    var body: some View {
        HSplitView {
            // Left: PDF preview + thumbnails
            VStack(spacing: 0) {
                Picker(String(localized: "Compare"), selection: $vm.comparisonShowsResult) {
                    Text(String(localized: "Original")).tag(false)
                    Text(String(localized: "Result")).tag(true)
                }
                .pickerStyle(.segmented)
                .disabled(!vm.canCompare)
                .opacity(vm.hasPreparedResult ? 1 : 0)
                .accessibilityHidden(!vm.hasPreparedResult)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                PDFPreviewPanel(
                    document: comparisonDocument,
                    currentPage: $currentPage,
                    preserveViewport: true
                )

                PageThumbnailStripView(document: comparisonDocument, currentPage: $currentPage)
                    .padding(.horizontal, 20)
            }
            .frame(minWidth: 260, idealWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                DropReceiverView(isTargeted: $isDropTargeted) { urls in
                    onFilesDropped(urls)
                }
            }

            // Right: Compression options
            VStack(spacing: 0) {
                OptionsHeaderView(url: url, onBack: onBack, allowsEscapeBack: !vm.isProcessing && !vm.hasPreparedResult)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                Divider()
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {

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

                            Picker(String(localized: "Compression mode"), selection: $vm.mode) {
                                Text(String(localized: "Manual")).tag(CompressionMode.manual)
                                Text(String(localized: "Fit under…")).tag(CompressionMode.targetSize)
                            }
                            .pickerStyle(.segmented)
                            .disabled(vm.isProcessing)

                            if vm.mode == .targetSize {
                                HStack {
                                    Text(String(localized: "Limit (MB)"))
                                    TextField(String(localized: "Limit in MB"), text: $vm.targetMegabytes)
                                        .textFieldStyle(.roundedBorder)
                                        .accessibilityLabel(String(localized: "File size limit in megabytes"))
                                }
                                .disabled(vm.isProcessing)
                                Text(vm.targetBytes == nil
                                     ? String(localized: "Enter a number from 0.1 to 1,000 MB using your decimal separator.")
                                     : String(localized: "1 MB = 1,000,000 bytes. The complete result must be below this limit."))
                                    .font(.caption)
                                    .foregroundStyle(vm.targetBytes == nil ? Color.red : Color.secondary)
                                Toggle(String(localized: "Allow image-based compression"), isOn: $vm.allowRasterization)
                                    .toggleStyle(.checkbox)
                                    .disabled(vm.isProcessing)
                                Text(String(localized: "Tries lossless first, then up to three image resolutions if allowed. An unattainable limit leaves your files unchanged."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if vm.mode == .targetSize || !vm.selectedLevel.isRasterize {
                                Text(String(localized: "Standard title, author, and other document-info fields are cleared. Embedded XMP and other identifying content may remain; this is not a privacy sanitizer."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            if document.isEncrypted && vm.rasterizationAllowed {
                                Text(String(localized: "This copy will not be password-protected."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            if vm.rasterizationAllowed {
                                Text(String(localized: "Rasterization turns every page into an image. Searchable text, accessibility tags, links, forms, and digital signatures are not preserved."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            // Compression level options
                            if vm.mode == .manual {
                                ForEach(CompressionLevel.allCases) { level in
                                    let key = PDFCompressor.estimateKey(
                                        level: level,
                                        quality: vm.selectedQuality,
                                        grayscale: vm.grayscale
                                    )
                                    let estimatedSize = vm.estimatedSizes[key]
                                    let heuristicSize = vm.heuristicSizes[key]
                                    let displaySize = estimatedSize ?? heuristicSize
                                    let isHeuristic = estimatedSize == nil && heuristicSize != nil

                                    Button {
                                        vm.selectedLevel = level
                                    } label: {
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
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(vm.isProcessing)
                                    .accessibilityElement(children: .combine)
                                    .accessibilityLabel(compressionDescription(level, size: displaySize, heuristic: isHeuristic))
                                    .accessibilityValue(vm.selectedLevel == level ? "Selected" : "")
                                }

                                if vm.selectedLevel.isRasterize {
                                    Divider()

                                    Text(String(localized: "JPEG Quality"))
                                        .font(.subheadline.weight(.medium))

                                    HStack(spacing: 12) {
                                        ForEach(JPEGQuality.allCases) { q in
                                            Button {
                                                withAnimation(.spring(duration: 0.25)) {
                                                    vm.selectedQuality = q
                                                }
                                            } label: {
                                                Text(q.title)
                                                    .font(.caption.weight(vm.selectedQuality == q ? .bold : .regular))
                                                    .foregroundColor(vm.selectedQuality == q ? .coralText : .primary)
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
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(vm.isProcessing)
                                            .accessibilityLabel("JPEG quality: \(q.title)")
                                            .accessibilityValue(vm.selectedQuality == q ? "Selected" : "")
                                        }
                                    }
                                    Divider()

                                    Toggle(isOn: $vm.grayscale) {
                                        Text(String(localized: "Convert to grayscale"))
                                            .font(.callout)
                                    }
                                    .toggleStyle(.checkbox)
                                    .disabled(vm.isProcessing)
                                } else {
                                    Divider()

                                    Toggle(isOn: $vm.removeAnnotations) {
                                        Text(String(localized: "Remove annotations (including links)"))
                                            .font(.callout)
                                    }
                                    .toggleStyle(.checkbox)
                                    .disabled(vm.isProcessing)

                                    if vm.removeAnnotations {
                                        Text(String(localized: "Forms, signatures, redactions, and unsupported annotations must be flattened instead."))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                            }

                            if vm.mode == .targetSize && vm.allowRasterization {
                                Toggle(String(localized: "Convert to grayscale"), isOn: $vm.grayscale)
                                    .toggleStyle(.checkbox)
                                    .disabled(vm.isProcessing)
                            }

                            if let candidate = vm.prepared {
                                Text("Output: \(candidate.destination.lastPathComponent)")
                                    .font(.caption)
                                    .textSelection(.enabled)
                                    .help(candidate.destination.path(percentEncoded: false))
                                if !vm.canCompare {
                                    Text(String(localized: "Comparison unavailable for this protected result. Its protection will be retained when saved."))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

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
                                if vm.hasPreparedResult {
                                    Button(String(localized: "Discard Result")) { vm.cancel() }
                                        .keyboardShortcut(.cancelAction)
                                    Button(String(localized: "Save Result")) { vm.savePreparedResult() }
                                        .keyboardShortcut("s")
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.large)
                                } else {
                                    Button(String(localized: "Prepare…")) {
                                        Task { await vm.performCompression() }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.large)
                                    .disabled(!vm.canCompress)
                                }
                            }

                            if vm.isProcessing {
                                HStack(spacing: 8) {
                                    ProgressView(String(localized: "Preparing compressed copy…"), value: vm.progress)
                                        .progressViewStyle(.linear)
                                    Button(String(localized: "Cancel")) { vm.cancel() }
                                        .keyboardShortcut(.cancelAction)
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }

                            if let msg = vm.resultMessage {
                                ResultMessageView(
                                    message: msg,
                                    isError: vm.isError,
                                    outputURL: vm.lastOutputURL,
                                    onRetry: vm.isError ? {
                                        // Reselect the destination after an identity change.
                                        // Cancelling the panel keeps the current candidate.
                                        Task { await vm.performCompression() }
                                    } : nil
                                )
                            }

                            Spacer()
                        }
                        .padding(24)
                        .frame(maxWidth: 520, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: vm.resultMessage) { _, message in
                        if message != nil { scroll.scrollTo("operation-result", anchor: .bottom) }
                    }
                }
            }
            .frame(minWidth: 300, idealWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
            .tint(.coral)
        }
        .onAppear { appVM.operationIsRunning = { vm.isProcessing } }
        .onAppear {
            vm.setSource(url, document: document)
        }
        .onChange(of: vm.hasPreparedResult) { _, hasResult in
            appVM.hasUnsavedChanges = hasResult
        }
        .onDisappear {
            vm.cancelEstimation()
            vm.discardPreparedResult()
        }
    }
}
