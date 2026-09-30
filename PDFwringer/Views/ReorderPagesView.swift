import SwiftUI
import PDFKit

struct ReorderPagesView: View {
    @Environment(AppViewModel.self) private var appVM
    let url: URL
    let document: PDFDocument
    let onBack: () -> Void
    let onFilesDropped: ([URL]) -> Void

    @State private var selectedPage: Int?

    private var selectedPosition: Int? {
        selectedPage.flatMap { vm.pageOrder.firstIndex(of: $0) }
    }

    @State private var isDropTargeted = false
    @State private var thumbnailCache = ThumbnailCache()
    @State private var vm = ReorderPagesViewModel()

    var body: some View {
        HSplitView {
            // Left: reorderable page list
            VStack(spacing: 0) {
                Text(String(localized: "Drag pages or select a page and use the arrow buttons"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)

                List(selection: $selectedPage) {
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
                        .tag(pageIdx)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Page \(pageIdx + 1), position \(position + 1) of \(vm.pageOrder.count)")
                    }
                    .onMove { from, to in
                        vm.pageOrder.move(fromOffsets: from, toOffset: to)
                    }
                    .moveDisabled(vm.isSaving)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))

                HStack {
                    Button {
                        if let selectedPage { vm.movePage(selectedPage, by: -1) }
                    } label: {
                        Label("Move Earlier", systemImage: "arrow.up")
                    }
                    .keyboardShortcut(.upArrow, modifiers: .option)
                    .disabled(vm.isSaving || selectedPosition == nil || selectedPosition == 0)

                    Button {
                        if let selectedPage { vm.movePage(selectedPage, by: 1) }
                    } label: {
                        Label("Move Later", systemImage: "arrow.down")
                    }
                    .keyboardShortcut(.downArrow, modifiers: .option)
                    .disabled(vm.isSaving || selectedPosition == nil || selectedPosition == vm.pageOrder.count - 1)
                }
                .controlSize(.small)
                .padding(8)
            }
            .frame(minWidth: 260, idealWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                DropReceiverView(isTargeted: $isDropTargeted) { urls in onFilesDropped(urls) }
            }

            // Right: controls
            VStack(spacing: 0) {
                OptionsHeaderView(url: url, onBack: onBack, allowsEscapeBack: !vm.isSaving)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                Divider()
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {

                            HStack {
                                Text(String(localized: "Reorder Pages"))
                                    .font(.title3.weight(.semibold))
                                Spacer()
                                Text("\(document.pageCount) pages")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Divider()

                            if document.isEncrypted {
                                Text(String(localized: "The reordered copy will not be password-protected."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            Text(String(localized: "Drag pages to rearrange them, or select a page and use Move Earlier or Move Later (Option–Up/Down Arrow). Changes are saved to a new file."))
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
                                Button(String(localized: "Save Copy…")) {
                                    Task { await vm.save(source: url, document: document) }
                                }
                                .keyboardShortcut("s")
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .disabled(!vm.canSave)
                            }

                            if vm.isSaving {
                                HStack(spacing: 8) {
                                    ProgressView(String(localized: "Saving reordered copy…"), value: vm.progress)
                                        .progressViewStyle(.linear)
                                    Button(String(localized: "Cancel")) { vm.cancel() }
                                            .keyboardShortcut(.cancelAction)
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
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
                        .frame(maxWidth: 520, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: vm.resultMessage) { _, message in
                        if message != nil { scroll.scrollTo("operation-result", anchor: .bottom) }
                    }
                }
            }
            .frame(minWidth: 300, idealWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
            .tint(.coral)
        }
        .onAppear { appVM.operationIsRunning = { vm.isSaving } }
        .onAppear {
            vm.setDocument(document)
        }
        .onChange(of: vm.hasUnsavedChanges) { _, dirty in appVM.hasUnsavedChanges = dirty }
        .onDisappear {
            vm.cancel()
            thumbnailCache.cancel()
        }
    }
}
