import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct PDFDropZone: View {
    let allowsMultiple: Bool
    let onDrop: ([URL]) -> Void

    @State private var isTargeted = false
    @State private var droppedFiles: [URL] = []

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: isTargeted ? [] : [6, 4])
                )

            if droppedFiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text(allowsMultiple ? "Drop PDF files here" : "Drop a PDF file here")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if droppedFiles.count == 1 {
                VStack(spacing: 8) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.tint)
                    Text(droppedFiles[0].lastPathComponent)
                        .font(.callout)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.tint)
                    Text("\(droppedFiles.count) files")
                        .font(.callout)
                }
            }
        }
        .overlay {
            DropReceiverView(isTargeted: $isTargeted) { urls in
                let pdfURLs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
                guard !pdfURLs.isEmpty else { return }
                if allowsMultiple {
                    droppedFiles = pdfURLs
                } else {
                    droppedFiles = [pdfURLs[0]]
                }
                onDrop(droppedFiles)
            }
        }
    }
}

// NSView-based drop receiver that uses NSPasteboard directly (reliable in sandbox)
struct DropReceiverView: NSViewRepresentable {
    @Binding var isTargeted: Bool
    let onDrop: ([URL]) -> Void

    func makeNSView(context: Context) -> DropNSView {
        let view = DropNSView()
        view.onDrop = onDrop
        view.onTargetChanged = { targeted in
            DispatchQueue.main.async { isTargeted = targeted }
        }
        return view
    }

    func updateNSView(_ nsView: DropNSView, context: Context) {
        nsView.onDrop = onDrop
        nsView.onTargetChanged = { targeted in
            DispatchQueue.main.async { isTargeted = targeted }
        }
    }
}

class DropNSView: NSView {
    var onDrop: (([URL]) -> Void)?
    var onTargetChanged: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let dominated = hasPDFFiles(in: sender)
        onTargetChanged?(dominated)
        return dominated ? .copy : []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        hasPDFFiles(in: sender) ? .copy : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onTargetChanged?(false)
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        hasPDFFiles(in: sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        onTargetChanged?(false)
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingContentsConformToTypes: [UTType.pdf.identifier]
        ]) as? [URL], !urls.isEmpty else {
            return false
        }
        onDrop?(urls)
        return true
    }

    private func hasPDFFiles(in info: NSDraggingInfo) -> Bool {
        guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] else { return false }
        return urls.contains { $0.pathExtension.lowercased() == "pdf" }
    }
}
