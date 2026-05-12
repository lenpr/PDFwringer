import SwiftUI
import PDFKit
import CoreImage

struct ColorAdjustOptionsView: View {
    let url: URL
    let document: PDFDocument
    let onBack: () -> Void
    let onFilesDropped: ([URL]) -> Void
    var onMutate: (() -> Void)?
    @Binding var currentPage: Int

    @State private var vm = ColorAdjustViewModel()
    @State private var shakeOffset: CGFloat = 0
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                previewPanel
                    .padding(20)

                PageThumbnailStripView(
                    document: document,
                    currentPage: $currentPage,
                    selectedPages: vm.applyAll ? nil : $vm.selectedPages
                )
                .padding(.horizontal, 20)
                .onChange(of: vm.selectedPages) {
                    vm.pageRangeText = vm.selectedPages.sorted().map { "\($0 + 1)" }.joined(separator: ", ")
                }
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
                    Text(String(localized: "Adjust Colors"))
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(document.pageCount) pages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                PageSelectionView(
                    pageCount: document.pageCount,
                    applyAll: $vm.applyAll,
                    pageRangeText: $vm.pageRangeText,
                    selectedPages: $vm.selectedPages,
                    shakeOffset: $shakeOffset,
                    label: String(localized: "Adjust all pages")
                )

                Divider()

                sliderSection

                presetButtons

                Spacer()

                HStack {
                    Spacer()
                    Button(String(localized: "Save")) {
                        Task { await vm.save(source: url, pageCount: document.pageCount, onMutate: onMutate) }
                    }
                    .keyboardShortcut("s")
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(vm.isIdentity || vm.isSaving)
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
                        isWarning: vm.isWarning,
                        outputURL: vm.lastOutputURL,
                        onRetry: vm.isError ? { Task { await vm.save(source: url, pageCount: document.pageCount, onMutate: onMutate) } } : nil
                    )
                }
            }
            .padding(24)
            .frame(minWidth: 300, idealWidth: 340)
            .tint(.coral)
        }
        .onChange(of: currentPage) { vm.updatePreview(document: document, page: currentPage) }
        .onChange(of: vm.brightness) { vm.updatePreview(document: document, page: currentPage) }
        .onChange(of: vm.contrast) { vm.updatePreview(document: document, page: currentPage) }
        .onChange(of: vm.saturation) { vm.updatePreview(document: document, page: currentPage) }
        .onAppear { vm.updatePreview(document: document, page: currentPage) }
        .onDisappear { vm.cancelPreview() }
    }

    // MARK: - Preview

    private var previewPanel: some View {
        Group {
            if let previewImage = vm.previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: Color(nsColor: .shadowColor).opacity(0.15), radius: 8, y: 2)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .aspectRatio(0.707, contentMode: .fit)
                    .overlay {
                        ProgressView()
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sliders

    private var sliderSection: some View {
        VStack(spacing: 12) {
            sliderRow(label: String(localized: "Brightness"), value: $vm.brightness, range: -1...1)
            sliderRow(label: String(localized: "Contrast"), value: $vm.contrast, range: 0.25...4.0)
            sliderRow(label: String(localized: "Saturation"), value: $vm.saturation, range: 0...4.0)
        }
    }

    private func sliderRow(label: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.callout)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
                .accessibilityLabel(label)
                .accessibilityValue(String(format: "%.2f", value.wrappedValue))
        }
    }

    // MARK: - Presets

    private var presetButtons: some View {
        HStack(spacing: 8) {
            ForEach(ColorPreset.allCases, id: \.self) { preset in
                Button(preset.title) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        vm.applyPreset(preset)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button(String(localized: "Reset")) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    vm.reset()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
