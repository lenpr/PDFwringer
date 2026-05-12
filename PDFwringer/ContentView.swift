import SwiftUI

struct ContentView: View {
    @Bindable var appVM: AppViewModel

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

            case .multiFile:
                MultiFileView(
                    files: multiFileBinding,
                    onMerge: {
                        withAnimation(.spring(duration: 0.3)) {
                            appVM.selectMerge()
                        }
                    },
                    onStartOver: {
                        appVM.confirmStartOver()
                    },
                    onFilesDropped: { urls in
                        addFilesToMultiFile(urls)
                    }
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
                    },
                    onFilesDropped: { urls in
                        addFilesToMerge(urls)
                    }
                )
                .transition(.move(edge: appVM.navigationDirection).combined(with: .opacity))

            case .rotating(let url, let doc):
                RotateOptionsView(
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
                    onMutate: { appVM.hasUnsavedChanges = true },
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
                    onMutate: { appVM.hasUnsavedChanges = true },
                    currentPage: $appVM.currentPage
                )
                .transition(.move(edge: appVM.navigationDirection).combined(with: .opacity))

            case .cropping(let url, let doc):
                CropOptionsView(
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
                    onMutate: { appVM.hasUnsavedChanges = true },
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
                    onMutate: { appVM.hasUnsavedChanges = true },
                    currentPage: $appVM.currentPage
                )
                .transition(.move(edge: appVM.navigationDirection).combined(with: .opacity))
            }
        }
        .frame(minWidth: 650, minHeight: 420)
        .overlay(alignment: .bottomTrailing) {
            Text(appVersion)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.trailing, 8)
                .padding(.bottom, 4)
        }
        .animation(.spring(duration: 0.3), value: appVM.state)
        .alert(String(localized: "Password Required"), isPresented: $appVM.showPasswordPrompt) {
            SecureField(String(localized: "Password"), text: $appVM.passwordText)
            Button(String(localized: "Unlock")) { appVM.unlockDocument() }
            Button(String(localized: "Cancel"), role: .cancel) { appVM.cancelPassword() }
        } message: {
            if appVM.wrongPasswordAttempt {
                Text(String(localized: "Incorrect password. Please try again."))
            } else {
                Text(String(localized: "This PDF is password-protected."))
            }
        }
        .alert(String(localized: "Cannot Open File"), isPresented: $appVM.showErrorAlert) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(appVM.errorMessage)
        }
        .alert(String(localized: "Start Over?"), isPresented: $appVM.showStartOverConfirm) {
            Button(String(localized: "Start Over"), role: .destructive) {
                withAnimation(.spring(duration: 0.35)) {
                    appVM.startOver()
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "This will discard your current selection."))
        }
        .onAppear {
            // Wire AppDelegate to forward Finder-opened files and check dirty state
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.onOpenURLs = { [weak appVM] urls in
                    appVM?.handleDrop(urls)
                }
                delegate.hasUnsavedChanges = { [weak appVM] in
                    appVM?.hasUnsavedChanges ?? false
                }
            }
            // Persist window frame across launches
            NSApp.keyWindow?.setFrameAutosaveName("MainWindow")
        }
    }

    // MARK: - Bindings for mutable file lists

    private var multiFileBinding: Binding<[PDFFileItem]> {
        Binding(
            get: {
                if case .multiFile(let items) = appVM.state { return items }
                return []
            },
            set: { newItems in
                if newItems.isEmpty {
                    appVM.startOver()
                } else if newItems.count == 1 {
                    appVM.loadSingleFile(newItems[0].url)
                } else {
                    appVM.state = .multiFile(newItems)
                }
            }
        )
    }

    private var mergeFileBinding: Binding<[PDFFileItem]> {
        Binding(
            get: {
                if case .merging(let items) = appVM.state { return items }
                return []
            },
            set: { newItems in
                if newItems.isEmpty {
                    appVM.startOver()
                } else {
                    appVM.state = .merging(newItems)
                }
            }
        )
    }

    private func addFilesToMultiFile(_ urls: [URL]) {
        guard case .multiFile(var items) = appVM.state else { return }
        items.append(contentsOf: PDFFileItem.from(urls: urls))
        appVM.state = .multiFile(items)
    }

    private func addFilesToMerge(_ urls: [URL]) {
        guard case .merging(var items) = appVM.state else { return }
        items.append(contentsOf: PDFFileItem.from(urls: urls))
        appVM.state = .merging(items)
    }
}
