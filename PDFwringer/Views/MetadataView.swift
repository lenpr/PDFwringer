import SwiftUI
import PDFKit

struct MetadataView: View {
    let url: URL
    let document: PDFDocument
    let onBack: () -> Void
    let onFilesDropped: ([URL]) -> Void

    @State private var metadata: PDFMetadataEditor.Metadata = .empty
    @State private var isProcessing = false
    @State private var resultMessage: String?
    @State private var isError = false
    @State private var isDropTargeted = false
    @State private var lastOutputURL: URL?
    @State private var currentPage: Int = 0

    private let editor = PDFMetadataEditor()

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

            // Right: Metadata fields
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

                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text("Edit Metadata")
                    .font(.title3.weight(.semibold))

                Divider()

                Group {
                    metadataField("Title", text: $metadata.title)
                    metadataField("Author", text: $metadata.author)
                    metadataField("Subject", text: $metadata.subject)
                    metadataField("Keywords", text: $metadata.keywords)
                    metadataField("Creator", text: $metadata.creator)
                }

                Text("Keywords should be comma-separated")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                if let msg = resultMessage {
                    HStack {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(isError ? .red : .green)
                            .lineLimit(3)
                        Spacer()
                        if isError {
                            Button("Try Again") { saveMetadata() }
                                .font(.caption)
                        } else if let outputURL = lastOutputURL {
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                            }
                            .font(.caption)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("Save Metadata") { saveMetadata() }
                        .keyboardShortcut("s")
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isProcessing)
                }
            }
            .padding(24)
            .frame(minWidth: 300, idealWidth: 340)
        }
        .onAppear {
            metadata = editor.read(from: url)
        }
    }

    private func metadataField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func saveMetadata() {
        let suggestedName = url.deletingPathExtension().lastPathComponent + "_metadata.pdf"
        guard let destination = FileDialogHelper.showSavePanel(suggestedName: suggestedName) else { return }

        isProcessing = true
        resultMessage = nil
        isError = false

        do {
            try editor.write(metadata: metadata, source: url, destination: destination)
            resultMessage = "Metadata saved successfully."
            isError = false
            lastOutputURL = destination
        } catch {
            resultMessage = error.localizedDescription
            isError = true
        }

        isProcessing = false
    }
}
