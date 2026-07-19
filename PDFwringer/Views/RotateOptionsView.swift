import SwiftUI
import PDFKit

struct RotateOptionsView: View {
    let url: URL
    let document: PDFDocument
    let onBack: () -> Void
    let onFilesDropped: ([URL]) -> Void
    var onMutate: (() -> Void)?
    @Binding var currentPage: Int

    @State private var pageSelection = PageSelection()
    @State private var resultMessage: String?
    @State private var isError = false
    @State private var isDropTargeted = false
    @State private var lastOutputURL: URL?
    @State private var shakeOffset: CGFloat = 0
    @State private var documentGeneration = 0

    private let rotator = PDFRotator()

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                PDFPreviewPanel(document: document, currentPage: $currentPage, generation: documentGeneration)

                PageThumbnailStripView(
                    document: document,
                    currentPage: $currentPage,
                    selectedPages: pageSelection.appliesToAll ? nil : $pageSelection.selectedPages
                )
                .id(documentGeneration)
                .padding(.horizontal, 20)
            }
            .frame(minWidth: 260, idealWidth: 320)
            .overlay {
                DropReceiverView(isTargeted: $isDropTargeted) { urls in
                    onFilesDropped(urls)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                OptionsHeaderView(url: url, onBack: onBack)

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

                HStack(spacing: 12) {
                    Button(String(localized: "90° CW")) { rotateInPlace(angle: .ninety) }
                        .keyboardShortcut("r")
                    Button(String(localized: "180°")) { rotateInPlace(angle: .oneEighty) }
                    Button(String(localized: "90° CCW")) { rotateInPlace(angle: .twoSeventy) }
                        .keyboardShortcut("r", modifiers: [.command, .shift])

                    Spacer()

                    Button(String(localized: "Save")) { saveRotated() }
                        .keyboardShortcut("s")
                        .buttonStyle(.borderedProminent)
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
            .frame(minWidth: 300, idealWidth: 340)
            .tint(.coral)
        }
    }

    private func rotateInPlace(angle: PDFRotator.Angle) {
        guard let indices = pageSelection.resolvedIndices(pageCount: document.pageCount) else {
            Formatting.triggerShake($shakeOffset)
            return
        }

        do {
            try rotator.rotate(
                document: document,
                angle: angle,
                pageIndices: indices,
                progress: { _ in }
            )
            documentGeneration += 1
            resultMessage = nil
            isError = false
            lastOutputURL = nil
            onMutate?()
        } catch {
            resultMessage = error.localizedDescription
            isError = true
            lastOutputURL = nil
        }
    }

    private func saveRotated() {
        guard document.allowsDocumentAssembly else {
            resultMessage = PDFwringerError.documentAssemblyNotAllowed.localizedDescription
            isError = true
            lastOutputURL = nil
            return
        }

        let suggestedName = url.deletingPathExtension().lastPathComponent + "_rotated.pdf"
        guard let destination = FileDialogHelper.showSavePanel(suggestedName: suggestedName) else { return }

        resultMessage = nil
        isError = false

        let result = DocumentSaver.save(document: document, to: destination)
        resultMessage = result.message
        isError = result.isError
        lastOutputURL = result.outputURL
    }
}
