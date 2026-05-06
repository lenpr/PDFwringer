import SwiftUI
import PDFKit

struct RotateOptionsView: View {
    let url: URL
    let document: PDFDocument
    let onBack: () -> Void
    let onFilesDropped: ([URL]) -> Void

    @State private var selectedAngle: PDFRotator.Angle = .ninety
    @State private var pageRangeText: String = ""
    @State private var rotateAll = true
    @State private var selectedPages: Set<Int> = []
    @State private var isProcessing = false
    @State private var progress: Double = 0
    @State private var resultMessage: String?
    @State private var isError = false
    @State private var isDropTargeted = false
    @State private var lastOutputURL: URL?
    @State private var currentPage: Int = 0
    @State private var syncingFromThumbnails = false
    @State private var shakeOffset: CGFloat = 0

    private let rotator = PDFRotator()

    var body: some View {
        HStack(spacing: 0) {
            // Left: PDF preview + thumbnails
            VStack(spacing: 0) {
                PDFPreviewView(document: document, currentPage: $currentPage)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: Color(nsColor: .shadowColor).opacity(0.15), radius: 8, y: 2)
                    .padding(20)

                PageThumbnailStripView(
                    document: document,
                    currentPage: $currentPage,
                    selectedPages: rotateAll ? nil : $selectedPages
                )
                .onChange(of: selectedPages) {
                    syncingFromThumbnails = true
                    pageRangeText = selectedPages.sorted().map { "\($0 + 1)" }.joined(separator: ", ")
                    syncingFromThumbnails = false
                }
            }
            .frame(minWidth: 260, idealWidth: 320)
            .overlay {
                DropReceiverView(isTargeted: $isDropTargeted) { urls in
                    onFilesDropped(urls)
                }
            }

            // Right: Rotation options
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

                HStack {
                    Text("Rotate Pages")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(document.pageCount) pages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Angle selection
                Text("Rotation angle")
                    .font(.callout.weight(.medium))

                HStack(spacing: 12) {
                    ForEach(PDFRotator.Angle.allCases) { angle in
                        Text(angle.title)
                            .font(.caption.weight(selectedAngle == angle ? .bold : .regular))
                            .foregroundColor(selectedAngle == angle ? .accentColor : .primary)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(selectedAngle == angle ? Color.accentColor.opacity(0.12) : Color.clear)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { selectedAngle = angle }
                    }
                }

                Divider()

                // Page selection
                Toggle(isOn: $rotateAll) {
                    Text("Rotate all pages")
                        .font(.callout)
                }
                .toggleStyle(.checkbox)

                if !rotateAll {
                    HStack {
                        TextField("e.g. 1, 3-5, 8-", text: $pageRangeText)
                            .textFieldStyle(.roundedBorder)
                            .offset(x: shakeOffset)
                            .onChange(of: pageRangeText) {
                                guard !syncingFromThumbnails else { return }
                                if let indices = try? PageRangeParser.parse(pageRangeText, pageCount: document.pageCount) {
                                    selectedPages = Set(indices)
                                }
                            }
                    }
                    Text("Tap thumbnails or type page numbers, ranges, or comma-separated values")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if isProcessing {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                }

                if let msg = resultMessage {
                    HStack {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(isError ? .red : .green)
                            .lineLimit(3)
                        Spacer()
                        if isError {
                            Button("Try Again") { Task { await performRotation() } }
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
                    Button("Rotate & Save") {
                        Task { await performRotation() }
                    }
                    .keyboardShortcut("s")
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isProcessing)
                }
            }
            .padding(24)
            .frame(minWidth: 300, idealWidth: 340)
        }
        .background {
            Button("") { Task { await performRotation() } }
                .keyboardShortcut("r")
                .hidden()
        }
    }

    private func performRotation() async {
        let suggestedName = url.deletingPathExtension().lastPathComponent + "_rotated.pdf"
        guard let destination = FileDialogHelper.showSavePanel(suggestedName: suggestedName) else { return }

        isProcessing = true
        progress = 0
        resultMessage = nil
        isError = false

        do {
            var indices: [Int]? = nil
            if !rotateAll {
                indices = try PageRangeParser.parse(pageRangeText, pageCount: document.pageCount)
                if indices?.isEmpty == true {
                    resultMessage = "No pages specified."
                    isError = true
                    isProcessing = false
                    triggerShake()
                    return
                }
            }

            try await rotator.rotate(
                source: url,
                destination: destination,
                angle: selectedAngle,
                pageIndices: indices,
                progress: { p in progress = p }
            )

            let pagesRotated = indices?.count ?? document.pageCount
            resultMessage = "Done! Rotated \(pagesRotated) pages by \(selectedAngle.rawValue)°."
            isError = false
            lastOutputURL = destination
        } catch is CancellationError {
            resultMessage = "Cancelled."
            isError = false
        } catch let error as PDFwringerError {
            resultMessage = error.localizedDescription
            isError = true
            if case .invalidPageRange = error { triggerShake() }
        } catch {
            resultMessage = error.localizedDescription
            isError = true
        }

        isProcessing = false
    }

    private func triggerShake() {
        withAnimation(.default) { shakeOffset = 8 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.default) { shakeOffset = -6 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.default) { shakeOffset = 4 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            withAnimation(.default) { shakeOffset = 0 }
        }
    }
}
