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
                    Text("Compress")
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

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: vm.selectedLevel == level ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(vm.selectedLevel == level ? .accentColor : .secondary)
                            .font(.body)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(level.title)
                                    .font(.body.weight(.medium))
                                Spacer()
                                if let size = estimatedSize {
                                    Text(Formatting.fileSize(size))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .contentTransition(.numericText())
                                } else {
                                    ProgressView()
                                        .controlSize(.mini)
                                }
                            }
                            Text(level.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
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

                    Text("JPEG Quality")
                        .font(.subheadline.weight(.medium))

                    HStack(spacing: 12) {
                        ForEach(JPEGQuality.allCases) { q in
                            Text(q.title)
                                .font(.caption.weight(vm.selectedQuality == q ? .bold : .regular))
                                .foregroundColor(vm.selectedQuality == q ? .accentColor : .primary)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background {
                                    if vm.selectedQuality == q {
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(Color.accentColor.opacity(0.12))
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
                    Text("Convert to grayscale")
                        .font(.callout)
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: Binding(
                    get: { vm.stripMetadata },
                    set: { vm.stripMetadata = $0 }
                )) {
                    Text("Strip all metadata")
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
                    Button("Compress") {
                        Task { await vm.performCompression() }
                    }
                    .keyboardShortcut("s")
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!vm.canCompress)
                }

                if vm.isProcessing {
                    ProgressView(value: vm.progress)
                        .progressViewStyle(.linear)
                }

                if let msg = vm.resultMessage {
                    ResultMessageView(
                        message: msg,
                        isError: vm.isError,
                        outputURL: vm.lastOutputURL,
                        onRetry: vm.isError ? { Task { await vm.performCompression() } } : nil
                    )
                }

                Spacer()
            }
            .padding(24)
            .frame(minWidth: 300, idealWidth: 340)
            .tint(Color(red: 0.91, green: 0.39, blue: 0.30))
        }
        .onAppear {
            vm.setSource(url)
        }
    }
}
