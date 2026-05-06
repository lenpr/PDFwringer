import SwiftUI

struct ContentView: View {
    @Bindable var appVM: AppViewModel
    @Environment(\.self) private var environment

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
                    onStartOver: {
                        withAnimation(.spring(duration: 0.35)) {
                            appVM.startOver()
                        }
                    },
                    onFilesDropped: { urls in
                        withAnimation(.spring(duration: 0.35)) {
                            appVM.handleDrop(urls)
                        }
                    },
                    currentPage: $appVM.currentPage
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))

            case .multiFile:
                MultiFileView(
                    files: multiFileBinding,
                    onMerge: {
                        withAnimation(.spring(duration: 0.3)) {
                            appVM.selectMerge()
                        }
                    },
                    onStartOver: {
                        withAnimation(.spring(duration: 0.35)) {
                            appVM.startOver()
                        }
                    },
                    onFilesDropped: { urls in
                        addFilesToMultiFile(urls)
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))

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
                .transition(.move(edge: .trailing).combined(with: .opacity))

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
                .transition(.move(edge: .trailing).combined(with: .opacity))

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
                .transition(.move(edge: .trailing).combined(with: .opacity))

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
                    currentPage: $appVM.currentPage
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))

            case .editingMetadata(let url, let doc):
                MetadataView(
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
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(minWidth: 650, minHeight: 420)
        .animation(.spring(duration: 0.3), value: appVM.state)
        .alert("Password Required", isPresented: $appVM.showPasswordPrompt) {
            SecureField("Password", text: $appVM.passwordText)
            Button("Unlock") { appVM.unlockDocument() }
            Button("Cancel", role: .cancel) { appVM.cancelPassword() }
        } message: {
            Text("This PDF is password-protected.")
        }
        .onAppear {
            // Wire AppDelegate to forward Finder-opened files
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.onOpenURLs = { [weak appVM] urls in
                    appVM?.handleDrop(urls)
                }
            }
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
