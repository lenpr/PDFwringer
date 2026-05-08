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
                if files.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 32))
                            .foregroundStyle(.quaternary)
                        Text(String(localized: "No files added"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "Drop PDF files here or click Add Files"))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        DropReceiverView(isTargeted: $isDropTargeted) { urls in
                            addFiles(urls)
                        }
                    }
                } else {
                    List {
                        ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                            HStack(spacing: 8) {
                                Image(systemName: "doc.fill")
                                    .foregroundColor(.coral)
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

                    Button(String(localized: "Add Files...")) {
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

            Divider()

            // Right: Merge action
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button(action: onBack) {
                        Label("Back", systemImage: "chevron.left")
                            .font(.caption.weight(.medium))
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Spacer()
                }

                Text(String(localized: "Merge"))
                    .font(.title3.weight(.semibold))

                Text(String(localized: "Drag files to reorder. They will be merged top to bottom."))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("\(files.count) files")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                    Text("\u{2022}")
                        .foregroundStyle(.quaternary)
                    Text("\(totalPages) total pages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }

                HStack {
                    Spacer()
                    Button(String(localized: "Merge")) {
                        Task { await performMerge() }
                    }
                    .keyboardShortcut("s")
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(files.count < 2 || vm.isProcessing)
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
                        onRetry: vm.isError ? { Task { await performMerge() } } : nil
                    )
                }

                Spacer()
            }
            .padding(24)
            .frame(minWidth: 300, idealWidth: 340)
            .tint(.coral)
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
