import SwiftUI
import PDFKit

struct MetadataOptionsView: View {
    let url: URL
    let document: PDFDocument
    let onBack: () -> Void
    let onFilesDropped: ([URL]) -> Void
    var onMutate: (() -> Void)?
    @Binding var currentPage: Int

    @State private var metadata: PDFMetadataEditor.Metadata = .empty
    @State private var initialMetadata: PDFMetadataEditor.Metadata = .empty
    @State private var resultMessage: String?
    @State private var isError = false
    @State private var isDropTargeted = false
    @State private var lastOutputURL: URL?
    @State private var setPassword = false
    @State private var passwordText = ""
    @State private var confirmPasswordText = ""
    @State private var removeProtection = false
    @State private var flattenAnnotations = false
    @State private var isSaving = false
    @State private var saveProgress: Double?

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
                OptionsHeaderView(url: url, onBack: onBack)

                HStack {
                    Text(String(localized: "Edit Metadata"))
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(document.pageCount) pages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }

                Divider()

                Group {
                    metadataField(String(localized: "Title"), text: $metadata.title)
                    metadataField(String(localized: "Author"), text: $metadata.author)
                    metadataField(String(localized: "Subject"), text: $metadata.subject)
                    metadataField(String(localized: "Keywords"), text: $metadata.keywords)
                    metadataField(String(localized: "Creator"), text: $metadata.creator)
                }

                Text(String(localized: "Keywords should be comma-separated"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Divider()

                Text(String(localized: "Annotations"))
                    .font(.callout.weight(.medium))

                Toggle(String(localized: "Flatten annotations"), isOn: $flattenAnnotations)
                    .toggleStyle(.checkbox)
                    .font(.callout)

                Text(String(localized: "Burns highlights, comments, and form fields into the page content so they cannot be edited"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Divider()

                Text(String(localized: "Security"))
                    .font(.callout.weight(.medium))

                if document.isEncrypted {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text(String(localized: "This document is encrypted"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Toggle(String(localized: "Remove protection on save"), isOn: $removeProtection)
                        .toggleStyle(.checkbox)
                        .font(.callout)
                    if !removeProtection {
                        SecureField(String(localized: "Re-enter password to keep protection"), text: $passwordText)
                            .textFieldStyle(.roundedBorder)
                    }
                } else {
                    Toggle(String(localized: "Set password"), isOn: $setPassword)
                        .toggleStyle(.checkbox)
                        .font(.callout)
                    if setPassword {
                        SecureField(String(localized: "Password"), text: $passwordText)
                            .textFieldStyle(.roundedBorder)
                        SecureField(String(localized: "Confirm password"), text: $confirmPasswordText)
                            .textFieldStyle(.roundedBorder)
                        if !confirmPasswordText.isEmpty && passwordText != confirmPasswordText {
                            Text(String(localized: "Passwords do not match"))
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else if !confirmPasswordText.isEmpty && passwordText == confirmPasswordText {
                            Text(String(localized: "Passwords match"))
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button(String(localized: "Save Metadata")) { Task { await saveMetadata() } }
                        .keyboardShortcut("s")
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isSaving
                            || (setPassword && (passwordText.isEmpty || passwordText != confirmPasswordText))
                            || (document.isEncrypted && !removeProtection && passwordText.isEmpty)
                        )
                }

                if let progress = saveProgress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                }

                if let msg = resultMessage {
                    ResultMessageView(
                        message: msg,
                        isError: isError,
                        outputURL: lastOutputURL,
                        onRetry: isError ? { Task { await saveMetadata() } } : nil
                    )
                }

                Spacer()
            }
            .padding(24)
            .frame(minWidth: 300, idealWidth: 340)
            .tint(.coral)
        }
        .onAppear {
            metadata = editor.read(from: url)
            initialMetadata = metadata
        }
        .onChange(of: metadata) {
            if metadata != initialMetadata {
                onMutate?()
            }
        }
        .onChange(of: setPassword) {
            if !setPassword {
                passwordText = ""
                confirmPasswordText = ""
            }
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

    private func saveMetadata() async {
        let suggestedName = url.deletingPathExtension().lastPathComponent + "_metadata.pdf"
        guard let destination = FileDialogHelper.showSavePanel(suggestedName: suggestedName) else { return }

        resultMessage = nil
        isError = false
        isSaving = true
        saveProgress = flattenAnnotations ? 0 : nil
        onMutate?()

        let password: String? = if document.isEncrypted && !removeProtection && !passwordText.isEmpty {
            passwordText
        } else if document.isEncrypted && !removeProtection && passwordText.isEmpty {
            // Encrypted doc with protection toggle OFF but no password entered — block save
            // to prevent silent deprotection
            nil
        } else if setPassword && !passwordText.isEmpty {
            passwordText
        } else {
            nil
        }

        // Safety: refuse to silently strip encryption from a protected document
        if document.isEncrypted && !removeProtection && password == nil {
            resultMessage = String(localized: "Please enter a password to keep protection, or check 'Remove protection' to save without encryption.")
            isError = true
            isSaving = false
            return
        }

        do {
            try await editor.write(
                metadata: metadata,
                source: url,
                destination: destination,
                password: password,
                flattenAnnotations: flattenAnnotations,
                progress: flattenAnnotations ? { p in saveProgress = p } : nil
            )
            if flattenAnnotations {
                resultMessage = "Saved with annotations flattened."
            } else if password != nil {
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

        isSaving = false
        saveProgress = nil
    }
}
