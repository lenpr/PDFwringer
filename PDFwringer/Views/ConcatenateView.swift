import SwiftUI
import UniformTypeIdentifiers

struct ConcatenateView: View {
    @State private var vm = ConcatenateViewModel()
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 20) {
            VStack(spacing: 8) {
                if vm.files.isEmpty {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                                style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                            )
                        VStack(spacing: 8) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 36))
                                .foregroundStyle(.secondary)
                            Text("Drop PDF files here")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .overlay {
                        DropReceiverView(isTargeted: $isDropTargeted) { urls in
                            vm.addFiles(urls)
                        }
                    }
                } else {
                    List {
                        ForEach(vm.files) { file in
                            HStack {
                                Image(systemName: "doc.fill")
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading) {
                                    Text(file.filename)
                                        .lineLimit(1)
                                    Text("\(file.pageCount) pages")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .onMove { vm.moveFiles(from: $0, to: $1) }
                        .onDelete { vm.removeFile(at: $0) }
                    }
                    .overlay {
                        DropReceiverView(isTargeted: $isDropTargeted) { urls in
                            vm.addFiles(urls)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button("A → Z") { vm.sortAlphabetical() }
                        .controlSize(.small)
                        .disabled(vm.files.count < 2)
                    Button("Z → A") { vm.sortReverseAlphabetical() }
                        .controlSize(.small)
                        .disabled(vm.files.count < 2)
                    Spacer()
                    Button("Clear") { vm.clearFiles() }
                        .controlSize(.small)
                        .disabled(vm.files.isEmpty)
                }
            }
            .frame(minWidth: 280)

            VStack(alignment: .leading, spacing: 16) {
                Text("Concatenate PDFs")
                    .font(.headline)
                Text("Drop PDF files into the list on the left. Drag to reorder. Files will be merged top-to-bottom.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if !vm.files.isEmpty {
                    Text("\(vm.files.count) files, \(vm.files.reduce(0) { $0 + $1.pageCount }) total pages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if vm.isProcessing {
                    ProgressView(value: vm.progress)
                        .progressViewStyle(.linear)
                }

                if let msg = vm.resultMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(vm.isError ? .red : .green)
                }

                HStack {
                    Spacer()
                    Button("Concatenate!") {
                        Task { await vm.concatenate() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!vm.canConcatenate)
                }
            }
            .frame(minWidth: 200)
        }
        .padding(20)
    }
}
