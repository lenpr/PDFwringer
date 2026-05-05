import SwiftUI
import PDFKit

struct CompressView: View {
    @State private var vm = CompressViewModel()

    var body: some View {
        HStack(spacing: 20) {
            // Left: Drop zone / PDF preview
            ZStack {
                if let doc = vm.pdfDocument {
                    PDFPreviewView(document: doc)
                } else {
                    PDFDropZone(allowsMultiple: false) { urls in
                        if let url = urls.first {
                            vm.setSource(url)
                        }
                    }
                }
            }
            .frame(minWidth: 250)
            .overlay {
                if vm.pdfDocument != nil {
                    DropReceiverView(isTargeted: .constant(false)) { urls in
                        if let url = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) {
                            vm.setSource(url)
                        }
                    }
                }
            }

            // Right: Options
            VStack(alignment: .leading, spacing: 10) {
                if let url = vm.sourceURL {
                    HStack {
                        Text(url.lastPathComponent)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        Text("\(vm.sourcePageCount) pages, \(CompressViewModel.formatBytes(vm.sourceFileSize))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                }

                // Compression level radio buttons with estimated sizes
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
                                if let size = estimatedSize, vm.sourceURL != nil {
                                    Text(CompressViewModel.formatBytes(size))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if vm.sourceURL != nil {
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

                // JPEG Quality picker (only relevant for rasterize levels)
                if vm.selectedLevel.isRasterize {
                    Divider()

                    Text("JPEG Quality")
                        .font(.subheadline.weight(.medium))

                    HStack(spacing: 12) {
                        ForEach(JPEGQuality.allCases) { q in
                            VStack(spacing: 2) {
                                Text(q.title)
                                    .font(.caption.weight(vm.selectedQuality == q ? .bold : .regular))
                                    .foregroundColor(vm.selectedQuality == q ? .accentColor : .primary)
                            }
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

                // Grayscale toggle
                Toggle(isOn: Binding(
                    get: { vm.grayscale },
                    set: { vm.grayscale = $0; vm.onSettingsChanged() }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Convert to grayscale")
                            .font(.body)
                        Text("Removes color, further reduces file size")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

                // Strip metadata toggle
                Toggle(isOn: Binding(
                    get: { vm.stripMetadata },
                    set: { vm.stripMetadata = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Strip all metadata")
                            .font(.body)
                        Text("Removes annotations, form fields, and document info")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

                Spacer()

                if vm.isProcessing {
                    ProgressView(value: vm.progress)
                        .progressViewStyle(.linear)
                }

                if let msg = vm.resultMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(vm.isError ? .red : .green)
                        .lineLimit(3)
                }

                HStack {
                    Spacer()
                    Button("Compress!") {
                        Task { await vm.performCompression() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!vm.canCompress)
                }
            }
            .frame(minWidth: 300)
        }
        .padding(20)
    }
}

struct PDFPreviewView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displaysPageBreaks = false
        pdfView.pageShadowsEnabled = false
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
    }
}
