import SwiftUI
import PDFKit

struct RotateOptionsView: View {
    @Environment(AppViewModel.self) private var appVM
    let url: URL
    let document: PDFDocument
    let onBack: () -> Void
    let onFilesDropped: ([URL]) -> Void
    var onDirtyChange: ((Bool) -> Void)?
    @Binding var currentPage: Int

    @State private var pageSelection = PageSelection()
    @State private var resultMessage: String?
    @State private var isError = false
    @State private var isDropTargeted = false
    @State private var lastOutputURL: URL?
    @State private var shakeOffset: CGFloat = 0
    @State private var documentGeneration = 0
    @State private var isSaving = false
    @State private var isEditing = false
    @State private var showsEditProgress = false
    private var isBusy: Bool { isSaving || isEditing }
    @State private var operationTask: Task<Void, Never>?

    private let rotator = PDFRotator()

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                PDFPreviewPanel(document: document, currentPage: $currentPage, generation: documentGeneration)

                PageThumbnailStripView(
                    document: document,
                    currentPage: $currentPage,
                    selectedPages: pageSelection.appliesToAll ? nil : $pageSelection.selectedPages
                )
                .id(documentGeneration)
                .disabled(isBusy)
                .padding(.horizontal, 20)
            }
            .frame(minWidth: 260, idealWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(!isBusy)
            .overlay {
                DropReceiverView(isTargeted: $isDropTargeted) { urls in
                    onFilesDropped(urls)
                }
            }

            VStack(spacing: 0) {
                OptionsHeaderView(url: url, onBack: onBack, allowsEscapeBack: !isBusy)
                    .disabled(isBusy)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                Divider()
                if isSaving || (isEditing && showsEditProgress) {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(isEditing ? String(localized: "Applying changes…") : String(localized: "Saving…"))
                        Spacer()
                        Button(String(localized: "Cancel")) { operationTask?.cancel() }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                }
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {

                            HStack {
                                Text(String(localized: "Rotate Pages"))
                                    .font(.title3.weight(.semibold))
                                Spacer()
                                Text("\(document.pageCount) pages")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .contentTransition(.numericText())
                            }

                            Divider()

                            PageSelectionView(
                                pageCount: document.pageCount,
                                selection: $pageSelection,
                                shakeOffset: $shakeOffset,
                                label: String(localized: "Rotate all pages")
                            )

                            VStack(alignment: .leading, spacing: 8) {
                                Button(String(localized: "Rotate 90° Clockwise")) { rotateInPlace(angle: .ninety) }
                                    .keyboardShortcut("r")
                                Button(String(localized: "180°")) { rotateInPlace(angle: .oneEighty) }
                                Button(String(localized: "Rotate 90° Counterclockwise")) { rotateInPlace(angle: .twoSeventy) }
                                    .keyboardShortcut("r", modifiers: [.command, .shift])

                            }

                            HStack {
                                Spacer()
                                Button(String(localized: "Save Copy…")) { saveRotated() }
                                    .keyboardShortcut("s")
                                    .buttonStyle(.borderedProminent)
                                    .tint(.coralFill)
                                    .controlSize(.large)
                            }

                            if let msg = resultMessage {
                                ResultMessageView(
                                    message: msg,
                                    isError: isError,
                                    outputURL: lastOutputURL,
                                    onRetry: isError ? { saveRotated() } : nil
                                )
                            }

                            Spacer()
                        }
                        .padding(24)
                        .frame(maxWidth: 520, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .disabled(isBusy)
                    .onChange(of: resultMessage) { _, message in
                        if message != nil { scroll.scrollTo("operation-result", anchor: .bottom) }
                    }
                }
            }
            .frame(minWidth: 300, idealWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
            .tint(.coral)
        }
        .onAppear { appVM.operationIsRunning = { isBusy } }
        .onDisappear { operationTask?.cancel() }
    }

    private func rotateInPlace(angle: PDFRotator.Angle) {
        guard !isBusy else { return }
        guard let indices = pageSelection.resolvedIndices(pageCount: document.pageCount) else {
            Formatting.triggerShake($shakeOffset)
            return
        }

        isEditing = true
        showsEditProgress = indices.count > 100
        operationTask = Task { @MainActor in
            defer { operationTask = nil; isEditing = false }
            do {
                try await rotator.rotateInBatches(
                    document: document,
                    angle: angle,
                    pageIndices: indices,
                    progress: { _ in }
                )
                documentGeneration += 1
                resultMessage = nil
                isError = false
                lastOutputURL = nil
                onDirtyChange?(true)
            } catch is CancellationError {
                documentGeneration += 1
                resultMessage = String(localized: "Cancelled. No changes applied.")
                isError = false
                lastOutputURL = nil
            } catch {
                documentGeneration += 1
                resultMessage = PDFwringerError.userMessage(for: error)
                isError = true
                lastOutputURL = nil
            }
        }
    }

    private func saveRotated() {
        guard !isBusy else { return }
        do {
            try PDFPermissionPolicy.require(.assembleDocument, for: document)
        } catch {
            resultMessage = PDFwringerError.userMessage(for: error)
            isError = true
            lastOutputURL = nil
            return
        }

        let suggestedName = url.deletingPathExtension().lastPathComponent + "_rotated.pdf"
        guard let destination = FileDialogHelper.showSavePanel(suggestedName: suggestedName) else { return }

        resultMessage = nil
        isError = false

        lastOutputURL = nil
        isSaving = true
        operationTask = Task { @MainActor in
            defer { operationTask = nil; isSaving = false }
            let result = await DocumentSaver.save(document: document, source: url, to: destination)
            resultMessage = result.message
            isError = result.isError
            lastOutputURL = result.outputURL
            if result.outputURL != nil { onDirtyChange?(false) }
        }
    }
}
