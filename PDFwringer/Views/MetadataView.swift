import SwiftUI
import PDFKit

struct MetadataView: View {
    let url: URL
    let document: PDFDocument
    let onBack: () -> Void
    let onFilesDropped: ([URL]) -> Void
    @Binding var currentPage: Int

    @State private var metadata: PDFMetadataEditor.Metadata = .empty
    @State private var resultMessage: String?
    @State private var isError = false
    @State private var isDropTargeted = false
    @State private var lastOutputURL: URL?
    @State private var setPassword = false
    @State private var passwordText = ""
    @State private var removeProtection = false

    private let editor = PDFMetadataEditor()

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
                    .contentShape(Rectangle())
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)

                    Spacer()

                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    Text("Edit Metadata")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(document.pageCount) pages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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

                Divider()

                Text("Security")
                    .font(.callout.weight(.medium))

                if document.isEncrypted {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text("This document is encrypted")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Remove protection on save", isOn: $removeProtection)
                        .toggleStyle(.checkbox)
                        .font(.callout)
                    if !removeProtection {
                        SecureField("Re-enter password to keep protection", text: $passwordText)
                            .textFieldStyle(.roundedBorder)
                    }
                } else {
                    Toggle("Set password", isOn: $setPassword)
                        .toggleStyle(.checkbox)
                        .font(.callout)
                    if setPassword {
                        SecureField("Password", text: $passwordText)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                HStack {
                    Spacer()
                    Button("Save Metadata") { saveMetadata() }
                        .keyboardShortcut("s")
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }

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

                Spacer()
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
                .onChange(of: text.wrappedValue) { _, newValue in
                    if newValue.count > 1000 {
                        text.wrappedValue = String(newValue.prefix(1000))
                    }
                }
        }
    }

    private func saveMetadata() {
        let suggestedName = url.deletingPathExtension().lastPathComponent + "_metadata.pdf"
        guard let destination = FileDialogHelper.showSavePanel(suggestedName: suggestedName) else { return }

        resultMessage = nil
        isError = false

        let password: String? = if document.isEncrypted && !removeProtection && !passwordText.isEmpty {
            passwordText
        } else if setPassword && !passwordText.isEmpty {
            passwordText
        } else {
            nil
        }

        do {
            try editor.write(metadata: metadata, source: url, destination: destination, password: password)
            if password != nil {
                resultMessage = "Saved with password protection."
            } else if removeProtection {
                resultMessage = "Saved without password protection."
            } else {
                resultMessage = "Metadata saved successfully."
            }
            isError = false
            lastOutputURL = destination
        } catch {
            resultMessage = error.localizedDescription
            isError = true
        }
    }
}
