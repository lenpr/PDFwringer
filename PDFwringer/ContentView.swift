import SwiftUI

struct ContentView: View {
    @State private var appVM = AppViewModel()

    var body: some View {
        Group {
            switch appVM.state {
            case .landing:
                LandingView { urls in
                    withAnimation(.spring(duration: 0.35)) {
                        appVM.handleDrop(urls)
                    }
                }

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
                    onStartOver: {
                        withAnimation(.spring(duration: 0.35)) {
                            appVM.startOver()
                        }
                    },
                    onFilesDropped: { urls in
                        withAnimation(.spring(duration: 0.35)) {
                            appVM.handleDrop(urls)
                        }
                    }
                )

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
                    }
                )

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
                    }
                )

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
            }
        }
        .frame(minWidth: 650, minHeight: 420)
        .animation(.spring(duration: 0.3), value: appVM.state)
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
