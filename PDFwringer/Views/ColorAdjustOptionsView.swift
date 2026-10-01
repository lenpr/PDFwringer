import SwiftUI
import PDFKit
import CoreImage

@MainActor
struct ColorAdjustOptionsView: View {
    @Environment(AppViewModel.self) private var appVM
    let url: URL
    let document: PDFDocument
    let onBack: () -> Void
    let onFilesDropped: ([URL]) -> Void
    @Binding var currentPage: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var vm = ColorAdjustViewModel()
    @State private var pageSelection = PageSelection()
    @State private var savedPageSelection = PageSelection()
    @State private var shakeOffset: CGFloat = 0
    @State private var isDropTargeted = false
    @State private var previewPixelSize: CGSize?

    var body: some View {
        HSplitView {
            previewColumn

            VStack(spacing: 0) {
                OptionsHeaderView(url: url, onBack: onBack, allowsEscapeBack: !vm.isSaving)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                Divider()
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {

                            HStack {
                                Text(String(localized: "Adjust Colors"))
                                    .font(.title3.weight(.semibold))
                                Spacer()
                                Text("\(document.pageCount) pages")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Divider()

                            if document.isEncrypted {
                                Text(String(localized: "The saved copy will not be password-protected."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            Text(String(localized: "Adjusted pages become images. Searchable text, accessibility tags, interactive forms, links, and digital signatures on those pages are not preserved."))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            PageSelectionView(
                                pageCount: document.pageCount,
                                selection: $pageSelection,
                                shakeOffset: $shakeOffset,
                                label: String(localized: "Adjust all pages")
                            )
                            .disabled(vm.isSaving)

                            Divider()

                            sliderSection
                                .disabled(vm.isSaving)

                            presetButtons
                                .disabled(vm.isSaving)

                            Spacer()

                            HStack {
                                Spacer()
                                Button(String(localized: "Save Copy…")) {
                                    saveAdjustedPDF()
                                }
                                .keyboardShortcut("s")
                                .buttonStyle(.borderedProminent)
                                .tint(.coralFill)
                                .controlSize(.large)
                                .disabled(vm.isIdentity || vm.isSaving)
                            }

                            if vm.isSaving {
                                HStack(spacing: 8) {
                                    ProgressView(String(localized: "Saving adjusted copy…"), value: vm.progress)
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
                                    onRetry: vm.isError ? { saveAdjustedPDF() } : nil
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
        .onChange(of: hasPendingChanges) { _, dirty in appVM.hasUnsavedChanges = dirty }
        .onChange(of: currentPage) { _, _ in refreshPreview() }
        .onChange(of: pageSelection) { _, _ in refreshPreview(); clearResult() }
        .onChange(of: vm.settings) { _, _ in clearResult(); refreshPreview() }
        .onChange(of: previewPixelSize) { _, _ in refreshPreview() }
        .onChange(of: vm.isSaving) { _, saving in if !saving { refreshPreview() } }
        .onAppear { appVM.operationIsRunning = { vm.isSaving } }
        .onAppear { refreshPreview() }
        .onDisappear {
            vm.cancelPreview()
            vm.cancel()
        }
    }

    private var hasPendingChanges: Bool {
        vm.hasUnsavedChanges || (!vm.isIdentity && pageSelection != savedPageSelection)
    }

    private func refreshPreview() {
        // This editor never mutates the source document. Its revision is stable
        // for the view lifetime; another document/page or geometry invalidates it.
        vm.updatePreview(document: document, page: currentPage, selection: pageSelection,
                         documentRevision: 0, pixelSize: previewPixelSize)
    }

    private func updatePreviewPixelSize(_ size: CGSize) {
        let width = size.width * displayScale
        let height = size.height * displayScale
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return }
        // Round up to small buckets so divider dragging does not rebuild the
        // base image for every pixel. Retina density stays included in the budget.
        let pixels = CGSize(width: min(4096, max(64, ceil(width / 64) * 64)),
                            height: min(4096, max(64, ceil(height / 64) * 64)))
        if previewPixelSize != pixels { previewPixelSize = pixels }
    }

    private func clearResult() {
        guard !vm.isSaving else { return }
        vm.resultMessage = nil
        vm.lastOutputURL = nil
        vm.isError = false
    }

    private func saveAdjustedPDF() {
        guard let resolvedPages = pageSelection.resolvedIndices(pageCount: document.pageCount) else {
            Formatting.triggerShake($shakeOffset)
            return
        }
        let pageIndices = pageSelection.appliesToAll ? nil : resolvedPages
        let selection = pageSelection
        let revision = vm.successfulSaveCount
        Task {
            await vm.save(
                source: url,
                document: document,
                pageIndices: pageIndices
            )
            if vm.successfulSaveCount != revision { savedPageSelection = selection }
        }
    }

    // MARK: - Preview

    private var previewColumn: some View {
        VStack(spacing: 0) {
            previewPanel
                .padding(20)

            PageThumbnailStripView(
                document: document,
                currentPage: $currentPage,
                selectedPages: pageSelection.appliesToAll ? nil : $pageSelection.selectedPages
            )
            .disabled(vm.isSaving)
            .padding(.horizontal, 20)
        }
        .frame(minWidth: 260, idealWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            DropReceiverView(isTargeted: $isDropTargeted) { urls in
                onFilesDropped(urls)
            }
        }
    }

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
                        if vm.previewUnavailable {
                            Label(String(localized: "Preview unavailable"), systemImage: "eye.slash")
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView(String(localized: "Updating preview…"))
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size, initial: true) { _, size in updatePreviewPixelSize(size) }
                    .onChange(of: displayScale) { _, _ in updatePreviewPixelSize(proxy.size) }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .overlay(alignment: .top) {
            if vm.isPreviewUpdating && vm.previewImage != nil {
                Text(String(localized: "Updating preview…"))
                    .font(.caption)
                    .padding(8)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .accessibilityLabel(String(localized: "Page \(currentPage + 1) preview"))
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
                Text(value.wrappedValue.formatted(.number.precision(.fractionLength(2))))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
                .accessibilityLabel(label)
                .accessibilityValue(value.wrappedValue.formatted(.number.precision(.fractionLength(2))))
        }
    }

    // MARK: - Presets

    private var presetButtons: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], alignment: .leading, spacing: 8) {
            ForEach(ColorPreset.allCases, id: \.self) { preset in
                Button(preset.title) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        vm.applyPreset(preset)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(preset.help)
                .accessibilityLabel(preset.help)
            }

            Button(String(localized: "Reset")) {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    vm.reset()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
