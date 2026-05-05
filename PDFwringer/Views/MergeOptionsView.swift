import SwiftUI

struct MergeOptionsView: View {
    @Binding var files: [PDFFileItem]
    let onBack: () -> Void
    let onFilesDropped: ([URL]) -> Void

    @State private var vm = ConcatenateViewModel()
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            // Left: File list with reordering
            VStack(spacing: 0) {
                List {
                    ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                        HStack(spacing: 6) {
                            VStack(spacing: 2) {
                                Button {
                                    guard index > 0 else { return }
                                    files.swapAt(index, index - 1)
                                } label: {
                                    Image(systemName: "chevron.up")
                                        .font(.caption2.weight(.semibold))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(index > 0 ? .primary : .quaternary)
                                .disabled(index == 0)

                                Button {
                                    guard index < files.count - 1 else { return }
                                    files.swapAt(index, index + 1)
                                } label: {
                                    Image(systemName: "chevron.down")
                                        .font(.caption2.weight(.semibold))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(index < files.count - 1 ? .primary : .quaternary)
                                .disabled(index >= files.count - 1)
                            }

                            Image(systemName: "doc.fill")
                                .foregroundColor(.accentColor)
                                .font(.body)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(file.filename)
                                    .font(.callout)
                                    .lineLimit(1)
                                Text("\(file.pageCount) pages")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()

                            Button {
                                files.remove(at: index)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                    .onMove { files.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { files.remove(atOffsets: $0) }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .overlay {
                    DropReceiverView(isTargeted: $isDropTargeted) { urls in
                        addFiles(urls)
                    }
                }

                HStack(spacing: 8) {
                    Button("A\u{2009}\u{2192}\u{2009}Z") {
                        files.sort { $0.filename.localizedCaseInsensitiveCompare($1.filename) == .orderedAscending }
                    }
                    .controlSize(.small)
                    .disabled(files.count < 2)

                    Button("Z\u{2009}\u{2192}\u{2009}A") {
                        files.sort { $0.filename.localizedCaseInsensitiveCompare($1.filename) == .orderedDescending }
                    }
                    .controlSize(.small)
                    .disabled(files.count < 2)

                    Spacer()

                    Button("Add Files...") {
                        guard let urls = FileDialogHelper.showOpenPanel(allowsMultiple: true) else { return }
                        addFiles(urls)
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .windowBackgroundColor))
            }
            .frame(minWidth: 260, idealWidth: 300)

            // Right: Merge action
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button(action: onBack) {
                        Label("Back", systemImage: "chevron.left")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Spacer()
                }

                Text("Merge")
                    .font(.title3.weight(.semibold))

                Text("Files will be merged in the order shown. Drag to reorder.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("\(files.count) files")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\u{2022}")
                        .foregroundStyle(.quaternary)
                    Text("\(totalPages) total pages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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
                                Task { await performMerge() }
                            }
                            .font(.caption)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("Merge") {
                        Task { await performMerge() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(files.count < 2 || vm.isProcessing)
                }
            }
            .padding(24)
            .frame(minWidth: 260, idealWidth: 300)
        }
    }

    private var totalPages: Int {
        files.reduce(0) { $0 + $1.pageCount }
    }

    private func addFiles(_ urls: [URL]) {
        files.append(contentsOf: PDFFileItem.from(urls: urls))
    }

    private func performMerge() async {
        vm.files = files
        await vm.concatenate()
    }
}
