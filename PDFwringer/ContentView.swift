import SwiftUI

struct ContentView: View {
    @Bindable var appVM: AppViewModel
    let appDelegate: AppDelegate
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch appVM.state {
            case .landing:
                LandingView { urls in
                    withAnimation(.spring(duration: 0.35)) {
                        appVM.handleDrop(urls)
                    }
                }
                .transition(.opacity)

            case .singleFile(let url, let doc):
                DocumentView(
                    url: url,
                    document: doc,
                    fileSize: appVM.currentFileSize,
                    onMerge: { appVM.selectMerge() },
                    onCompress: {
                        withAnimation(.spring(duration: 0.3)) {
                            appVM.selectCompress()
                        }
                    },
                    onSplit: {
                        withAnimation(.spring(duration: 0.3)) {
                            appVM.selectSplit()
                        }
                    },
                    onRotate: {
                        withAnimation(.spring(duration: 0.3)) {
                            appVM.selectRotate()
                        }
                    },
                    onMetadata: {
                        withAnimation(.spring(duration: 0.3)) {
                            appVM.selectMetadata()
                        }
                    },
                    onCrop: {
                        withAnimation(.spring(duration: 0.3)) {
                            appVM.selectCrop()
                        }
                    },
                    onAdjustColor: {
                        withAnimation(.spring(duration: 0.3)) {
                            appVM.selectAdjustColor()
                        }
                    },
                    onExportImages: {
                        withAnimation(.spring(duration: 0.3)) {
                            appVM.selectExportImages()
                        }
                    },
                    onReorderPages: {
                        withAnimation(.spring(duration: 0.3)) {
                            appVM.selectReorderPages()
                        }
                    },
                    onStartOver: {
                        appVM.confirmStartOver()
                    },
                    onFilesDropped: { urls in
                        withAnimation(.spring(duration: 0.35)) {
                            appVM.handleDrop(urls)
                        }
                    },
                    currentPage: $appVM.currentPage
                )
                .transition(.move(edge: appVM.navigationDirection).combined(with: .opacity))

            case .compressing(let url, let doc):
                CompressOptionsView(
                    url: url,
                    document: doc,
                    onBack: {
                        withAnimation(.spring(duration: 0.3)) {
                            appVM.goBack()
                        }
                    },
                    onFilesDropped: { urls in
                        withAnimation(.spring(duration: 0.35)) {
                            appVM.handleDrop(urls)
                        }
                    },
                    currentPage: $appVM.currentPage
                )
                .transition(.move(edge: appVM.navigationDirection).combined(with: .opacity))

            case .splitting(let url, let doc):
                SplitOptionsView(
                    url: url,
                    document: doc,
                    onBack: {
                        withAnimation(.spring(duration: 0.3)) {
                            appVM.goBack()
                        }
                    },
                    onFilesDropped: { urls in
                        withAnimation(.spring(duration: 0.35)) {
                            appVM.handleDrop(urls)
                        }
                    },
                    currentPage: $appVM.currentPage
                )
                .transition(.move(edge: appVM.navigationDirection).combined(with: .opacity))

            case .merging:
                MergeOptionsView(
                    files: mergeFileBinding,
                    onBack: {
                        withAnimation(.spring(duration: 0.3)) {
                            appVM.goBack()
                        }
                    }
                )
                .transition(.move(edge: appVM.navigationDirection).combined(with: .opacity))

            case .rotating(let url, _, let workingDocument):
                RotateOptionsView(
                    url: url,
                    document: workingDocument,
                    onBack: {
                        withAnimation(.spring(duration: 0.3)) {
                            appVM.goBack()
                        }
                    },
                    onFilesDropped: { urls in
                        withAnimation(.spring(duration: 0.35)) {
                            appVM.handleDrop(urls)
                        }
                    },
                    onDirtyChange: { appVM.hasUnsavedChanges = $0 },
                    currentPage: $appVM.currentPage
                )
                .transition(.move(edge: appVM.navigationDirection).combined(with: .opacity))

            case .editingMetadata(let url, let doc):
                MetadataOptionsView(
                    url: url,
                    document: doc,
                    onBack: {
                        withAnimation(.spring(duration: 0.3)) {
                            appVM.goBack()
                        }
                    },
                    onFilesDropped: { urls in
                        withAnimation(.spring(duration: 0.35)) {
                            appVM.handleDrop(urls)
                        }
                    },
                    currentPage: $appVM.currentPage
                )
                .transition(.move(edge: appVM.navigationDirection).combined(with: .opacity))

            case .cropping(let url, _, let workingDocument):
                CropOptionsView(
                    url: url,
                    document: workingDocument,
                    onBack: {
                        withAnimation(.spring(duration: 0.3)) {
                            appVM.goBack()
                        }
                    },
                    onFilesDropped: { urls in
                        withAnimation(.spring(duration: 0.35)) {
                            appVM.handleDrop(urls)
                        }
                    },
                    onDirtyChange: { appVM.hasUnsavedChanges = $0 },
                    currentPage: $appVM.currentPage
                )
                .transition(.move(edge: appVM.navigationDirection).combined(with: .opacity))

            case .adjustingColor(let url, let doc):
                ColorAdjustOptionsView(
                    url: url,
                    document: doc,
                    onBack: {
                        withAnimation(.spring(duration: 0.3)) {
                            appVM.goBack()
                        }
                    },
                    onFilesDropped: { urls in
                        withAnimation(.spring(duration: 0.35)) {
                            appVM.handleDrop(urls)
                        }
                    },
                    currentPage: $appVM.currentPage
                )
                .transition(.move(edge: appVM.navigationDirection).combined(with: .opacity))

            case .exportingImages(let url, let doc):
                ExportImagesOptionsView(
                    url: url,
                    document: doc,
                    onBack: {
                        withAnimation(.spring(duration: 0.3)) {
                            appVM.goBack()
                        }
                    },
                    onFilesDropped: { urls in
                        withAnimation(.spring(duration: 0.35)) {
                            appVM.handleDrop(urls)
                        }
                    },
                    currentPage: $appVM.currentPage
                )
                .transition(.move(edge: appVM.navigationDirection).combined(with: .opacity))

            case .reorderingPages(let url, let doc):
                ReorderPagesView(
                    url: url,
                    document: doc,
                    onBack: {
                        withAnimation(.spring(duration: 0.3)) {
                            appVM.goBack()
                        }
                    },
                    onFilesDropped: { urls in
                        withAnimation(.spring(duration: 0.35)) {
                            appVM.handleDrop(urls)
                        }
                    }
                )
                .transition(.move(edge: appVM.navigationDirection).combined(with: .opacity))
            }
        }
        .environment(appVM)
        .transaction { if reduceMotion { $0.animation = nil } }
        .frame(minWidth: 650, minHeight: 420)
        .background(WindowCloseGuard { appVM.closeWorkflow() })
        .overlay(alignment: .bottomTrailing) {
            Text(appVersion)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.trailing, 8)
                .padding(.bottom, 4)
        }
        .sheet(isPresented: Binding(
            get: { appVM.showPasswordPrompt },
            set: { if !$0 { appVM.cancelPassword() } }
        )) {
            PasswordPromptView(appVM: appVM)
        }
        .alert(String(localized: "PDFwringer"), isPresented: $appVM.showErrorAlert) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(appVM.errorMessage)
        }
        .onAppear {
            appDelegate.configure(with: appVM)
            // Persist window frame across launches
            NSApp.keyWindow?.setFrameAutosaveName("MainWindow")
            // Load recent documents once at launch
            appVM.refreshRecentDocuments()
        }
    }

    // MARK: - Bindings for mutable file lists

    private var mergeFileBinding: Binding<[PDFFileItem]> {
        Binding(
            get: {
                if case .merging(let items) = appVM.state { return items }
                return []
            },
            set: { newItems in
                appVM.updateMergeFiles(newItems)
            }
        )
    }

}

/// Alert buttons dismiss automatically, even when unlocking fails. A sheet keeps
/// the same input focused until the document unlocks or the user cancels.
private struct PasswordPromptView: View {
    @Bindable var appVM: AppViewModel
    @FocusState private var passwordIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Password Required"))
                .font(.headline)
            Text(appVM.wrongPasswordAttempt
                 ? String(localized: "Incorrect password. Please try again.")
                 : String(localized: "This PDF is password-protected."))
                .foregroundStyle(appVM.wrongPasswordAttempt ? Color.red : Color.secondary)
            SecureField(String(localized: "Password"), text: $appVM.passwordText)
                .textFieldStyle(.roundedBorder)
                .focused($passwordIsFocused)
                .onSubmit { appVM.unlockDocument() }
            HStack {
                Spacer()
                Button(String(localized: "Cancel")) { appVM.cancelPassword() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Unlock")) { appVM.unlockDocument() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360)
        .interactiveDismissDisabled()
        .onAppear { passwordIsFocused = true }
        .onChange(of: appVM.wrongPasswordAttempt) { _, failed in
            if failed { passwordIsFocused = true }
        }
    }
}
