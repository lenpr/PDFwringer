import SwiftUI
import PDFKit

struct ReorderPagesView: View {
    let url: URL
    let document: PDFDocument
    let onBack: () -> Void
    let onFilesDropped: ([URL]) -> Void
    var onMutate: (() -> Void)?
    @Binding var currentPage: Int

    @State private var pageOrder: [Int] = []
    @State private var resultMessage: String?
    @State private var isError = false
    @State private var lastOutputURL: URL?
    @State private var isDropTargeted = false
    @State private var isSaving = false

    var body: some View {
        HStack(spacing: 0) {
            // Left: reorderable page list
            VStack(spacing: 0) {
                Text(String(localized: "Drag pages to reorder"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)

                List {
                    ForEach(Array(pageOrder.enumerated()), id: \.element) { position, pageIdx in
                        HStack(spacing: 12) {
                            if let page = document.page(at: pageIdx) {
                                let thumb = page.thumbnail(of: CGSize(width: 50, height: 70), for: .cropBox)
                                Image(nsImage: thumb)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 50, height: 70)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                    .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(localized: "Page \(pageIdx + 1)"))
                                    .font(.callout)
                                if position != pageIdx {
                                    Text(String(localized: "moved from position \(pageIdx + 1)"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Text("\(position + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove { from, to in
                        pageOrder.move(fromOffsets: from, toOffset: to)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
            .frame(minWidth: 280, idealWidth: 400)
            .overlay {
                DropReceiverView(isTargeted: $isDropTargeted) { urls in onFilesDropped(urls) }
            }

            Divider()

            // Right: controls
            VStack(alignment: .leading, spacing: 16) {
                OptionsHeaderView(url: url, onBack: onBack)

                HStack {
                    Text(String(localized: "Reorder Pages"))
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(document.pageCount) pages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Text(String(localized: "Drag page thumbnails to rearrange their order. Changes are saved to a new file."))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Divider()

                // Quick actions
                HStack(spacing: 8) {
                    Button(String(localized: "Reverse")) {
                        withAnimation { pageOrder.reverse() }
                    }
                    .controlSize(.small)

                    Button(String(localized: "Reset")) {
                        withAnimation { pageOrder = Array(0..<document.pageCount) }
                    }
                    .controlSize(.small)
                }

                Spacer()

                HStack {
                    Spacer()
                    Button(String(localized: "Save")) { save() }
                        .keyboardShortcut("s")
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isSaving || pageOrder == Array(0..<document.pageCount))
                }

                if isSaving {
                    ProgressView()
                        .progressViewStyle(.linear)
                }

                if let msg = resultMessage {
                    ResultMessageView(
                        message: msg,
                        isError: isError,
                        outputURL: lastOutputURL
                    )
                }
            }
            .padding(24)
            .frame(minWidth: 280, idealWidth: 320)
            .tint(.coral)
        }
        .onAppear {
            pageOrder = Array(0..<document.pageCount)
        }
    }

    private func save() {
        let suggestedName = url.deletingPathExtension().lastPathComponent + "_reordered.pdf"
        guard let destination = FileDialogHelper.showSavePanel(suggestedName: suggestedName) else { return }

        isSaving = true
        resultMessage = nil
        isError = false
        onMutate?()

        Task {
            defer { isSaving = false }

            guard let sourceDoc = PDFDocument(url: url) else {
                resultMessage = PDFwringerError.cannotOpenDocument.localizedDescription
                isError = true
                return
            }

            let output = PDFDocument()
            for (i, pageIdx) in pageOrder.enumerated() {
                guard let page = sourceDoc.page(at: pageIdx) else { continue }
                output.insert(page, at: i)
            }

            do {
                try AtomicFileWriter.write(to: destination) { tempURL in
                    output.write(to: tempURL)
                }
                resultMessage = String(localized: "Saved.")
                isError = false
                lastOutputURL = destination
            } catch {
                resultMessage = error.localizedDescription
                isError = true
            }
        }
    }
}
