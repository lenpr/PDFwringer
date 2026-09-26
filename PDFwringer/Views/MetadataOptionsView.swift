import SwiftUI
import PDFKit

struct MetadataOptionsView: View {
    @Environment(AppViewModel.self) private var appVM
    let url: URL
    let document: PDFDocument
    let onBack: () -> Void
    let onFilesDropped: ([URL]) -> Void
    @Binding var currentPage: Int

    @State private var savedMetadata: PDFMetadataEditor.Metadata = .empty
    @State private var metadata: PDFMetadataEditor.Metadata = .empty
    @State private var resultMessage: String?
    @State private var isError = false
    @State private var isDropTargeted = false
    @State private var lastOutputURL: URL?
    @State private var setPassword = false
    @State private var requiresCurrentPassword = true
    @State private var passwordText = ""
    @State private var confirmPasswordText = ""
    @State private var removeProtection = false
    @State private var flattenAnnotations = false
    @State private var isSaving = false
    @State private var saveProgress: Double?
    @State private var saveTask: Task<Void, Never>?

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
            ScrollView {
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

                    Text(String(localized: "These fields edit standard document information. Embedded XMP and other identifying content may remain; clearing fields does not sanitize the PDF."))
                        .font(.caption)
                        .foregroundStyle(.secondary)

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
                        .disabled(isSaving)
                        .font(.callout)

                    Text(String(localized: "Turns every page into an image, including annotations and form appearances. Searchable text, accessibility tags, interactive fields, links, and digital signatures are not preserved."))
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
                            .disabled(isSaving)
                            .font(.callout)
                        if !removeProtection && (flattenAnnotations || requiresCurrentPassword) {
                            SecureField(flattenAnnotations ? String(localized: "Password for flattened copy") : String(localized: "Current password (verification only)"), text: $passwordText)
                                .textFieldStyle(.roundedBorder)
                                .disabled(isSaving)
                            if flattenAnnotations {
                                SecureField(String(localized: "Confirm password"), text: $confirmPasswordText)
                                    .textFieldStyle(.roundedBorder)
                                    .disabled(isSaving)
                            }
                        }
                    } else {
                        Toggle(String(localized: "Set AES-128 password for flattened copy"), isOn: $setPassword)
                            .disabled(!flattenAnnotations || isSaving)
                            .toggleStyle(.checkbox)
                            .font(.callout)
                        if setPassword {
                            SecureField(String(localized: "Password"), text: $passwordText)
                                .textFieldStyle(.roundedBorder)
                                .disabled(isSaving)
                            SecureField(String(localized: "Confirm password"), text: $confirmPasswordText)
                                .textFieldStyle(.roundedBorder)
                                .disabled(isSaving)
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

                    Text(flattenAnnotations
                         ? String(localized: "A new password uses AES-128 encryption. Use 1–32 printable ASCII characters.")
                         : String(localized: "Existing protection is retained. New passwords require Flatten annotations; ordinary saves do not create legacy encryption."))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Spacer()
                        Button(String(localized: "Save Metadata")) { startSaving() }
                            .keyboardShortcut("s")
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(isSaving
                                || (setPassword && (passwordText.isEmpty || passwordText != confirmPasswordText))
                                || (document.isEncrypted && !removeProtection
                                    && ((requiresCurrentPassword || flattenAnnotations) && passwordText.isEmpty
                                        || (flattenAnnotations && passwordText != confirmPasswordText)))
                            )
                    }

                    if isSaving {
                        HStack(spacing: 8) {
                            if let progress = saveProgress {
                                ProgressView(value: progress)
                                    .progressViewStyle(.linear)
                            } else {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Button(String(localized: "Cancel")) { saveTask?.cancel() }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }

                    if let msg = resultMessage {
                        ResultMessageView(
                            message: msg,
                            isError: isError,
                            outputURL: lastOutputURL,
                            onRetry: isError ? { startSaving() } : nil
                        )
                    }

                    Spacer()
                }
                .padding(24)
            }
            .frame(minWidth: 300, idealWidth: 340)
            .tint(.coral)
        }
        .onAppear { appVM.operationIsRunning = { isSaving } }
        .onAppear {
            metadata = editor.read(from: document)
            savedMetadata = metadata
            requiresCurrentPassword = PDFDocument(url: url)?.isLocked ?? true
        }
        .onChange(of: hasPendingChanges) { _, dirty in appVM.hasUnsavedChanges = dirty }
        .onChange(of: flattenAnnotations) {
            setPassword = false
            passwordText = ""
            confirmPasswordText = ""
        }
        .onChange(of: setPassword) {
            if !setPassword {
                passwordText = ""
                confirmPasswordText = ""
            }
        }
        .onDisappear {
            saveTask?.cancel()
            saveTask = nil
        }
    }

    private var hasPendingChanges: Bool {
        metadata != savedMetadata || setPassword || removeProtection || flattenAnnotations
            || !passwordText.isEmpty || !confirmPasswordText.isEmpty
    }

    private func metadataField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .disabled(isSaving)
                .onChange(of: text.wrappedValue) { _, newValue in
                    if newValue.count > 1000 {
                        text.wrappedValue = String(newValue.prefix(1000))
                    }
                }
        }
    }

    private func startSaving() {
        guard !isSaving else { return }
        let operationMetadata = metadata
        let operationSetPassword = setPassword
        let operationPassword = passwordText
        let operationRemoveProtection = removeProtection
        let operationFlattenAnnotations = flattenAnnotations
        let sourceWasEncrypted = document.isEncrypted

        saveTask = Task {
            await saveMetadata(
                operationMetadata: operationMetadata,
                setPassword: operationSetPassword,
                passwordText: operationPassword,
                removeProtection: operationRemoveProtection,
                flattenAnnotations: operationFlattenAnnotations,
                sourceWasEncrypted: sourceWasEncrypted
            )
            saveTask = nil
        }
    }

    private func saveMetadata(
        operationMetadata: PDFMetadataEditor.Metadata,
        setPassword: Bool,
        passwordText: String,
        removeProtection: Bool,
        flattenAnnotations: Bool,
        sourceWasEncrypted: Bool
    ) async {
        let suggestedName = url.deletingPathExtension().lastPathComponent + "_metadata.pdf"
        guard let destination = FileDialogHelper.showSavePanel(suggestedName: suggestedName) else { return }

        resultMessage = nil
        isError = false
        isSaving = true
        saveProgress = flattenAnnotations ? 0 : nil
        defer {
            isSaving = false
            saveProgress = nil
        }
        let password: String? = if sourceWasEncrypted && !removeProtection && !passwordText.isEmpty {
            passwordText
        } else if sourceWasEncrypted && !removeProtection && passwordText.isEmpty {
            // Encrypted doc with protection toggle OFF but no password entered — block save
            // to prevent silent deprotection
            nil
        } else if setPassword && !passwordText.isEmpty {
            passwordText
        } else {
            nil
        }

        // Safety: refuse to silently strip encryption from a protected document
        if sourceWasEncrypted && !removeProtection && (flattenAnnotations || requiresCurrentPassword) && password == nil {
            resultMessage = String(localized: "Please enter a password to keep protection, or check 'Remove protection' to save without encryption.")
            isError = true
            return
        }

        do {
            try await editor.write(
                metadata: operationMetadata,
                document: document,
                source: url,
                destination: destination,
                password: flattenAnnotations ? password : nil,
                removeProtection: removeProtection,
                existingPassword: sourceWasEncrypted && !flattenAnnotations && !removeProtection ? passwordText : nil,
                flattenAnnotations: flattenAnnotations,
                progress: flattenAnnotations ? { p in saveProgress = p } : nil
            )
            let securityMessage: String
            if sourceWasEncrypted && !flattenAnnotations && !removeProtection {
                securityMessage = " Existing password protection was retained."
            } else if password != nil {
                securityMessage = " AES-128 password protection is enabled."
            } else if sourceWasEncrypted && removeProtection {
                securityMessage = " Password protection was removed."
            } else {
                securityMessage = ""
            }
            if flattenAnnotations {
                resultMessage = "Saved with annotations flattened.\(securityMessage)"
            } else {
                resultMessage = "Metadata saved successfully.\(securityMessage)"
            }
            isError = false
            lastOutputURL = destination
            savedMetadata = operationMetadata
            self.setPassword = false
            self.removeProtection = false
            self.flattenAnnotations = false
            self.passwordText = ""
            confirmPasswordText = ""
        } catch is CancellationError {
            resultMessage = String(localized: "Cancelled.")
            isError = false
            lastOutputURL = nil
        } catch {
            resultMessage = error.localizedDescription
            isError = true
            lastOutputURL = nil
        }
    }
}
