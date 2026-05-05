import SwiftUI
import PDFKit

struct CompressOptionsView: View {
    let url: URL
    let document: PDFDocument
    let onBack: () -> Void
    let onFilesDropped: ([URL]) -> Void

    @State private var vm = CompressViewModel()
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            // Left: PDF preview
            VStack(spacing: 0) {
                PDFPreviewView(document: document)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
                    .padding(20)
            }
            .frame(minWidth: 260, idealWidth: 320)
            .overlay {
                DropReceiverView(isTargeted: $isDropTargeted) { urls in
                    onFilesDropped(urls)
                }
            }

            // Right: Compression options
            VStack(alignment: .leading, spacing: 10) {
                // Header with back button
                HStack {
                    Button(action: onBack) {
                        Label("Back", systemImage: "chevron.left")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    Text("Compress")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(vm.sourcePageCount) pages, \(Formatting.fileSize(vm.sourceFileSize))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(vm.selectedQuality == q ? Color.accentColor.opacity(0.12) : Color.clear)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    vm.selectedQuality = q
                                    vm.onSettingsChanged()
                                }
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

                Spacer()

                if vm.isProcessing {
                    ProgressView(value: vm.progress)
                        .progressViewStyle(.linear)
                }

                if let msg = vm.resultMessage {
                    HStack {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(vm.isError ? .red : .green)
                            .lineLimit(3)
                        if vm.isError {
                            Button("Try Again") {
                                Task { await vm.performCompression() }
                            }
                            .font(.caption)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("Compress") {
                        Task { await vm.performCompression() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!vm.canCompress)
                }
            }
            .padding(24)
            .frame(minWidth: 300, idealWidth: 340)
        }
        .onAppear {
            vm.setSource(url)
        }
    }
}
