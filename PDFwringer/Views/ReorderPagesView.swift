import SwiftUI
import PDFKit

struct ReorderPagesView: View {
    let url: URL
    let document: PDFDocument
    let onBack: () -> Void
    let onFilesDropped: ([URL]) -> Void

    @State private var isDropTargeted = false
    @State private var thumbnailCache = ThumbnailCache()
    @State private var vm = ReorderPagesViewModel()

    var body: some View {
        HStack(spacing: 0) {
            // Left: reorderable page list
            VStack(spacing: 0) {
                Text(String(localized: "Drag pages to reorder"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)

                List {
                    ForEach(Array(vm.pageOrder.enumerated()), id: \.element) { position, pageIdx in
                        let _ = thumbnailCache.generation
                        HStack(spacing: 12) {
                            if let thumb = thumbnailCache.thumbnail(
                                for: pageIdx,
                                document: document,
                                size: CGSize(width: 100, height: 140)
                            ) {
                                Image(nsImage: thumb)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 50, height: 70)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                    .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                            } else {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 50, height: 70)
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
                        vm.pageOrder.move(fromOffsets: from, toOffset: to)
                    }
                    .moveDisabled(vm.isSaving)
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
                        withAnimation { vm.pageOrder.reverse() }
                    }
                    .controlSize(.small)
                    .disabled(vm.isSaving)

                    Button(String(localized: "Reset")) {
                        withAnimation { vm.reset() }
                    }
                    .controlSize(.small)
                    .disabled(vm.isSaving)
                }

                Spacer()

                HStack {
                    Spacer()
                    Button(String(localized: "Save")) {
                        Task { await vm.save(source: url, document: document) }
                    }
                    .keyboardShortcut("s")
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!vm.canSave)
                }

                if vm.isSaving {
                    HStack(spacing: 8) {
                        ProgressView(value: vm.progress)
                            .progressViewStyle(.linear)
                        Button(String(localized: "Cancel")) { vm.cancel() }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                if let msg = vm.resultMessage {
                    ResultMessageView(
                        message: msg,
                        isError: vm.isError,
                        outputURL: vm.lastOutputURL
                    )
                }
            }
            .padding(24)
            .frame(minWidth: 280, idealWidth: 320)
            .tint(.coral)
        }
        .onAppear {
            vm.setDocument(document)
        }
        .onDisappear { vm.cancel() }
    }
}
