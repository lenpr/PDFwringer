import SwiftUI

struct SplitView: View {
    @State private var vm = SplitViewModel()

    var body: some View {
        HStack(spacing: 20) {
            PDFDropZone(allowsMultiple: false) { urls in
                if let url = urls.first {
                    vm.setSource(url)
                }
            }
            .frame(minWidth: 220)

            VStack(alignment: .leading, spacing: 16) {
                if let url = vm.sourceURL {
                    HStack {
                        Text(url.lastPathComponent)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        Text("\(vm.sourcePageCount) pages")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                }

                // Split every N pages
                VStack(alignment: .leading, spacing: 4) {
                    Text("Split document")
                        .font(.body.weight(.semibold))
                    HStack {
                        TextField("1", value: $vm.splitPagesPerFile, format: .number)
                            .frame(width: 50)
                            .textFieldStyle(.roundedBorder)
                        Text("page(s) per file")
                            .font(.callout)
                        Spacer()
                        Button("Split!") {
                            Task { await vm.splitByPages() }
                        }
                        .disabled(!vm.canProcess)
                    }
                }

                Divider()

                // Keep pages
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keep only some pages")
                        .font(.body.weight(.semibold))
                    HStack {
                        TextField("e.g. 1,3,4-10", text: $vm.keepPagesText)
                            .textFieldStyle(.roundedBorder)
                        Button("Extract!") {
                            Task { await vm.keepPages() }
                        }
                        .disabled(!vm.canProcess || vm.keepPagesText.isEmpty)
                    }
                }

                Divider()

                // Remove pages
                VStack(alignment: .leading, spacing: 4) {
                    Text("Remove pages")
                        .font(.body.weight(.semibold))
                    HStack {
                        TextField("e.g. 1,3,4-10", text: $vm.removePagesText)
                            .textFieldStyle(.roundedBorder)
                        Button("Remove!") {
                            Task { await vm.removePages() }
                        }
                        .disabled(!vm.canProcess || vm.removePagesText.isEmpty)
                    }
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
            }
            .frame(minWidth: 320)
        }
        .padding(20)
    }
}
