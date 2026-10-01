import SwiftUI

struct MergeOptionsView: View {
    @Environment(AppViewModel.self) private var appVM
    @Binding var files: [PDFFileItem]
    let onBack: () -> Void

    @State private var vm = ConcatenateViewModel()
    @State private var isDropTargeted = false
    @State private var fileIntakeTask: Task<Void, Never>?
    @State private var fileIntakeID: UUID?
    @State private var isAddingFiles = false
    @State private var savedFileIDs: [UUID] = []
    @State private var selectedFileID: UUID?
    private var selectedPosition: Int? { files.firstIndex { $0.id == selectedFileID } }

    var body: some View {
        HSplitView {
            // Left: File list with reordering
            VStack(spacing: 0) {
                if files.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 32))
                            .foregroundStyle(.quaternary)
                        Text(String(localized: "No files added"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "Drop PDF files here or click Add Files below"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        DropReceiverView(isTargeted: $isDropTargeted) { urls in
                            addFiles(urls)
                        }
                    }
                } else {
                    List(selection: $selectedFileID) {
                        ForEach(files) { file in
                            HStack(spacing: 8) {
                                Image(systemName: "doc.fill")
                                    .foregroundColor(.coral)
                                    .font(.body)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(file.filename)
                                        .font(.callout)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .help(file.url.path(percentEncoded: false))
                                    Text("\(file.pageCount) pages")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()

                                Button {
                                    if let idx = files.firstIndex(where: { $0.id == file.id }) {
                                        files.remove(at: idx)
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .disabled(vm.isProcessing)
                                .accessibilityLabel(String(localized: "Remove \(file.filename) from merge"))
                            }
                            .padding(.vertical, 2)
                            .tag(file.id)
                        }
                        .onMove { files.move(fromOffsets: $0, toOffset: $1) }
                        .onDelete { offsets in
                            if !vm.isProcessing { files.remove(atOffsets: offsets) }
                        }
                        .moveDisabled(vm.isProcessing)
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                    .overlay {
                        DropReceiverView(isTargeted: $isDropTargeted) { urls in
                            addFiles(urls)
                        }
                    }
                }

                HStack {
                    Button { moveSelectedFile(by: -1) } label: {
                        Label(String(localized: "Move Earlier"), systemImage: "arrow.up")
                    }
                    .keyboardShortcut(.upArrow, modifiers: .option)
                    .disabled(vm.isProcessing || selectedPosition == nil || selectedPosition == 0)
                    Button { moveSelectedFile(by: 1) } label: {
                        Label(String(localized: "Move Later"), systemImage: "arrow.down")
                    }
                    .keyboardShortcut(.downArrow, modifiers: .option)
                    .disabled(vm.isProcessing || selectedPosition == nil || selectedPosition == files.count - 1)
                }
                .controlSize(.small)
                .padding(8)

                HStack(spacing: 8) {
                    Button("A\u{2009}\u{2192}\u{2009}Z") {
                        files.sort { $0.filename.localizedCaseInsensitiveCompare($1.filename) == .orderedAscending }
                    }
                    .controlSize(.small)
                    .disabled(files.count < 2 || vm.isProcessing)
                    .accessibilityLabel(String(localized: "Sort ascending"))

                    Button("Z\u{2009}\u{2192}\u{2009}A") {
                        files.sort { $0.filename.localizedCaseInsensitiveCompare($1.filename) == .orderedDescending }
                    }
                    .controlSize(.small)
                    .disabled(files.count < 2 || vm.isProcessing)
                    .accessibilityLabel(String(localized: "Sort descending"))

                    Spacer()

                    if isAddingFiles {
                        ProgressView()
                            .controlSize(.small)
                        Button(String(localized: "Cancel")) { cancelFileIntake() }
                            .keyboardShortcut(.cancelAction)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }

                    Button(String(localized: "Add Files...")) {
                        guard let urls = FileDialogHelper.showOpenPanel(allowsMultiple: true) else { return }
                        addFiles(urls)
                    }
                    .controlSize(.small)
                    .disabled(vm.isProcessing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .windowBackgroundColor))
            }
            .frame(minWidth: 260, idealWidth: 320, maxWidth: .infinity, maxHeight: .infinity)

            // Right: Merge action
            VStack(spacing: 0) {
                OptionsHeaderView(onBack: onBack, allowsEscapeBack: !vm.isProcessing && !isAddingFiles, backTitle: appVM.mergeReturnsToDocument ? String(localized: "Back") : String(localized: "Close Files"), backHelp: appVM.mergeReturnsToDocument ? String(localized: "Return to tool selection") : String(localized: "Close these files and choose others"))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                Divider()
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {

                            Text(String(localized: "Merge"))
                                .font(.title3.weight(.semibold))

                            Text(String(localized: "Select a file and use Move Earlier/Later, or drag to reorder. Files merge top to bottom."))
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            Text(String(localized: "The merged copy will not be password-protected, even if an input has protection."))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack {
                                Text(files.count == 1 ? String(localized: "1 file") : String(localized: "\(files.count) files"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .contentTransition(.numericText())
                                Text("\u{2022}")
                                    .foregroundStyle(.quaternary)
                                Text("\(totalPages) total pages")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .contentTransition(.numericText())
                            }

                            if files.count < 2 {
                                Text(files.count == 1
                                     ? String(localized: "Add another PDF using Add Files, or drop it into the list.")
                                     : String(localized: "Add two or more PDFs using Add Files, or drop them into the list."))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                Spacer()
                                Button(String(localized: "Save Merged Copy…")) {
                                    Task { await performMerge() }
                                }
                                .keyboardShortcut("s")
                                .buttonStyle(.borderedProminent)
                                .tint(.coralFill)
                                .controlSize(.large)
                                .disabled(files.count < 2 || vm.isProcessing || isAddingFiles)
                            }

                            if vm.isProcessing {
                                HStack(spacing: 8) {
                                    ProgressView(String(localized: "Merging PDFs…"), value: vm.progress)
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
                                    onRetry: vm.isError ? { Task { await performMerge() } } : nil
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
        .onAppear {
            savedFileIDs = files.map(\.id)
            appVM.operationIsRunning = { vm.isProcessing || isAddingFiles }
        }
        .onChange(of: files.map(\.id)) { _, ids in
            appVM.hasUnsavedChanges = ids != savedFileIDs
            if !vm.isProcessing { vm.resultMessage = nil; vm.lastOutputURL = nil; vm.isError = false }
        }
        .onDisappear {
            vm.cancel()
            cancelFileIntake()
        }
    }

    private func moveSelectedFile(by offset: Int) {
        guard !vm.isProcessing, let position = selectedPosition,
              files.indices.contains(position + offset) else { return }
        files.swapAt(position, position + offset)
    }

    private var totalPages: Int {
        files.reduce(0) { $0 + $1.pageCount }
    }

    private func addFiles(_ urls: [URL]) {
        guard !vm.isProcessing else { return }
        cancelFileIntake()
        let requestID = UUID()
        fileIntakeID = requestID
        isAddingFiles = true

        fileIntakeTask = Task {
            defer {
                if fileIntakeID == requestID {
                    fileIntakeTask = nil
                    fileIntakeID = nil
                    isAddingFiles = false
                }
            }
            do {
                let newFiles = try await PDFFileItem.load(urls: urls)
                try Task.checkCancellation()
                guard fileIntakeID == requestID else { return }
                files.append(contentsOf: newFiles)
            } catch is CancellationError {
                // A newer selection or navigation transition superseded this batch.
            } catch {
                guard fileIntakeID == requestID else { return }
                vm.resultMessage = PDFwringerError.userMessage(for: error)
                vm.isError = true
                vm.lastOutputURL = nil
            }
        }
    }

    private func cancelFileIntake() {
        fileIntakeTask?.cancel()
        fileIntakeTask = nil
        fileIntakeID = nil
        isAddingFiles = false
    }

    private func performMerge() async {
        vm.files = files
        let revision = vm.successfulSaveCount
        await vm.concatenate()
        if vm.successfulSaveCount != revision {
            savedFileIDs = files.map(\.id)
            appVM.hasUnsavedChanges = false
        }
    }
}
