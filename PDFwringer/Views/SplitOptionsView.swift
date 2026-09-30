import SwiftUI
import PDFKit

struct SplitOptionsView: View {
    @Environment(AppViewModel.self) private var appVM
    let url: URL
    let document: PDFDocument
    let onBack: () -> Void
    let onFilesDropped: ([URL]) -> Void
    @Binding var currentPage: Int

    @State private var vm = SplitViewModel()
    @State private var isDropTargeted = false
    @State private var keepShakeOffset: CGFloat = 0
    @State private var removeShakeOffset: CGFloat = 0

    var body: some View {
        HSplitView {
            // Left: PDF preview + thumbnails
            VStack(spacing: 0) {
                PDFPreviewPanel(document: document, currentPage: $currentPage)

                PageThumbnailStripView(document: document, currentPage: $currentPage)
                    .padding(.horizontal, 20)
            }
            .frame(minWidth: 260, idealWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                DropReceiverView(isTargeted: $isDropTargeted) { urls in
                    onFilesDropped(urls)
                }
            }

            // Right: Split options
            VStack(spacing: 0) {
                OptionsHeaderView(url: url, onBack: onBack, allowsEscapeBack: !vm.isProcessing)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                Divider()
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {

                            HStack {
                                Text(String(localized: "Split / Extract"))
                                    .font(.title3.weight(.semibold))
                                Spacer()
                                Text("\(vm.sourcePageCount) pages")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .contentTransition(.numericText())
                            }

                            Divider()

                            if document.isEncrypted {
                                Text(String(localized: "Extracted and split copies will not be password-protected."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            // Split every N pages
                            VStack(alignment: .leading, spacing: 6) {
                                Text(String(localized: "Split document"))
                                    .font(.callout.weight(.medium))
                                HStack {
                                    TextField("1", value: $vm.splitPagesPerFile, format: .number)
                                        .frame(width: 50)
                                        .textFieldStyle(.roundedBorder)
                                        .accessibilityLabel(String(localized: "Pages per file"))
                                    Text(String(localized: "page(s) per file"))
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button(String(localized: "Split")) {
                                        Task { await vm.splitByPages() }
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(!vm.canProcess)
                                }
                            }

                            Divider()

                            // Keep pages
                            VStack(alignment: .leading, spacing: 6) {
                                Text(String(localized: "Keep only these pages"))
                                    .font(.callout.weight(.medium))
                                HStack {
                                    TextField(String(localized: "e.g. 1, 3-5, 8-"), text: $vm.keepPagesText)
                                        .textFieldStyle(.roundedBorder)
                                        .accessibilityLabel(String(localized: "Pages to keep"))
                                        .offset(x: keepShakeOffset)
                                    Button(String(localized: "Extract")) {
                                        Task { await vm.keepPages() }
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(!vm.canProcess || vm.keepPagesText.isEmpty)
                                }
                            }

                            Divider()

                            // Remove pages
                            VStack(alignment: .leading, spacing: 6) {
                                Text(String(localized: "Save a copy without these pages"))
                                    .font(.callout.weight(.medium))
                                HStack {
                                    TextField(String(localized: "e.g. 1, 3-5, 8-"), text: $vm.removePagesText)
                                        .textFieldStyle(.roundedBorder)
                                        .accessibilityLabel(String(localized: "Pages to omit from the saved copy"))
                                        .offset(x: removeShakeOffset)
                                    Button(String(localized: "Save Copy…")) {
                                        Task { await vm.removePages() }
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(!vm.canProcess || vm.removePagesText.isEmpty)
                                }
                            }

                            if vm.isProcessing {
                                HStack(spacing: 8) {
                                    ProgressView(String(localized: "Creating PDF copies…"), value: vm.progress)
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
                                    outputURL: vm.lastOutputURL,
                                    onRetry: vm.isError ? { Task { await vm.retryLastOperation() } } : nil
                                )
                            }

                            Spacer()
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
        .onAppear { appVM.operationIsRunning = { vm.isProcessing } }
        .onAppear {
            vm.setSource(url, document: document)
        }
        .onChange(of: vm.errorSource) { _, source in
            switch source {
            case .keep:
                Formatting.triggerShake($keepShakeOffset)
            case .remove:
                Formatting.triggerShake($removeShakeOffset)
            case .split, nil:
                break
            }
        }
        .onDisappear { vm.cancel() }
    }
}
