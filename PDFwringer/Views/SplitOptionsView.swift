import SwiftUI
import PDFKit

struct SplitOptionsView: View {
    let url: URL
    let document: PDFDocument
    let onBack: () -> Void
    let onFilesDropped: ([URL]) -> Void

    @State private var vm = SplitViewModel()
    @State private var isDropTargeted = false
    @State private var currentPage: Int = 0

    var body: some View {
        HStack(spacing: 0) {
            // Left: PDF preview + thumbnails
            VStack(spacing: 0) {
                PDFPreviewView(document: document, currentPage: $currentPage)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: Color(nsColor: .shadowColor).opacity(0.15), radius: 8, y: 2)
                    .padding(20)

                PageThumbnailStripView(document: document, currentPage: $currentPage)
            }
            .frame(minWidth: 260, idealWidth: 320)
            .overlay {
                DropReceiverView(isTargeted: $isDropTargeted) { urls in
                    onFilesDropped(urls)
                }
            }

            // Right: Split options
            VStack(alignment: .leading, spacing: 16) {
                // Header with back button
                HStack {
                    Button(action: onBack) {
                        Label("Back", systemImage: "chevron.left")
                            .font(.caption.weight(.medium))
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    Text("Split / Extract")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(vm.sourcePageCount) pages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Split every N pages
                VStack(alignment: .leading, spacing: 6) {
                    Text("Split document")
                        .font(.callout.weight(.medium))
                    HStack {
                        TextField("1", value: $vm.splitPagesPerFile, format: .number)
                            .frame(width: 50)
                            .textFieldStyle(.roundedBorder)
                        Text("page(s) per file")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Split") {
                            Task { await vm.splitByPages() }
                        }
                        .disabled(!vm.canProcess)
                    }
                }

                Divider()

                // Keep pages
                VStack(alignment: .leading, spacing: 6) {
                    Text("Keep only these pages")
                        .font(.callout.weight(.medium))
                    HStack {
                        TextField("e.g. 1, 3-5, 8-", text: $vm.keepPagesText)
                            .textFieldStyle(.roundedBorder)
                        Button("Extract") {
                            Task { await vm.keepPages() }
                        }
                        .disabled(!vm.canProcess || vm.keepPagesText.isEmpty)
                    }
                }

                Divider()

                // Remove pages
                VStack(alignment: .leading, spacing: 6) {
                    Text("Remove these pages")
                        .font(.callout.weight(.medium))
                    HStack {
                        TextField("e.g. 1, 3-5, 8-", text: $vm.removePagesText)
                            .textFieldStyle(.roundedBorder)
                        Button("Remove") {
                            Task { await vm.removePages() }
                        }
                        .disabled(!vm.canProcess || vm.removePagesText.isEmpty)
                    }
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
                        Spacer()
                        if vm.isError {
                            Button("Try Again") {
                                Task { await vm.retryLastOperation() }
                            }
                            .font(.caption)
                        } else if let outputURL = vm.lastOutputURL {
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                            }
                            .font(.caption)
                        }
                    }
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
