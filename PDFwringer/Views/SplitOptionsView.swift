import SwiftUI
import PDFKit

struct SplitOptionsView: View {
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

            // Right: Split options
            VStack(alignment: .leading, spacing: 16) {
                OptionsHeaderView(url: url, onBack: onBack)

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

                // Split every N pages
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Split document"))
                        .font(.callout.weight(.medium))
                    HStack {
                        TextField("1", value: $vm.splitPagesPerFile, format: .number)
                            .frame(width: 50)
                            .textFieldStyle(.roundedBorder)
                        Text(String(localized: "page(s) per file"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(String(localized: "Split")) {
                            Task { await vm.splitByPages() }
                        }
                        .buttonStyle(.borderedProminent)
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
                            .offset(x: keepShakeOffset)
                        Button(String(localized: "Extract")) {
                            Task { await vm.keepPages() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!vm.canProcess || vm.keepPagesText.isEmpty)
                    }
                }

                Divider()

                // Remove pages
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Remove these pages"))
                        .font(.callout.weight(.medium))
                    HStack {
                        TextField(String(localized: "e.g. 1, 3-5, 8-"), text: $vm.removePagesText)
                            .textFieldStyle(.roundedBorder)
                            .offset(x: removeShakeOffset)
                        Button(String(localized: "Remove")) {
                            Task { await vm.removePages() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!vm.canProcess || vm.removePagesText.isEmpty)
                    }
                }

                if vm.isProcessing {
                    ProgressView(value: vm.progress)
                        .progressViewStyle(.linear)
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
            .frame(minWidth: 300, idealWidth: 340)
            .tint(.coral)
        }
        .onAppear {
            vm.setSource(url)
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
    }
}
