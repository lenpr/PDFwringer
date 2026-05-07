import SwiftUI

struct MultiFileView: View {
    @Binding var files: [PDFFileItem]
    let onMerge: () -> Void
    let onStartOver: () -> Void
    let onFilesDropped: ([URL]) -> Void

    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            // Left: File list
            VStack(spacing: 0) {
                List {
                    ForEach(files) { file in
                        HStack(spacing: 10) {
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
                        }
                        .padding(.vertical, 2)
                    }
                    .onMove { files.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { files.remove(atOffsets: $0) }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .overlay {
                    DropReceiverView(isTargeted: $isDropTargeted) { urls in
                        onFilesDropped(urls)
                    }
                }

                // Bottom bar
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

            Divider()

            // Right: Actions
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(files.count) files selected")
                            .font(.headline)
                        Text("\(totalPages) total pages")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: onStartOver) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Start over")
                }

                Divider()

                Text("What would you like to do?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ActionCardView(
                    icon: "doc.on.doc",
                    title: "Merge",
                    description: "Combine all files into a single PDF in the order shown",
                    action: onMerge
                )

                Text("Drag to reorder files in the list.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()
            }
            .padding(24)
            .frame(minWidth: 300, idealWidth: 340)
        }
    }

    private var totalPages: Int {
        files.reduce(0) { $0 + $1.pageCount }
    }

    private func addFiles(_ urls: [URL]) {
        files.append(contentsOf: PDFFileItem.from(urls: urls))
    }
}
