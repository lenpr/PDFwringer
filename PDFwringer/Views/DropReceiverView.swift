import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// NSView-based drop receiver that reads file URLs from NSPasteboard directly — more reliable
/// than SwiftUI's `onDrop` modifier when running inside the App Sandbox.
struct DropReceiverView: NSViewRepresentable {
    @Binding var isTargeted: Bool
    let onDrop: ([URL]) -> Void

    func makeNSView(context: Context) -> DropNSView {
        let view = DropNSView()
        view.onDrop = onDrop
        view.onTargetChanged = { [self] targeted in
            MainActor.assumeIsolated { isTargeted = targeted }
        }
        return view
    }

    func updateNSView(_ nsView: DropNSView, context: Context) {
        nsView.onDrop = onDrop
        nsView.onTargetChanged = { [self] targeted in
            MainActor.assumeIsolated { isTargeted = targeted }
        }
    }
}

/// AppKit NSView that accepts PDF file drops. Used as an overlay — returns nil from hitTest
/// so mouse clicks pass through to SwiftUI views underneath while still receiving drag events.
class DropNSView: NSView {
    var onDrop: (([URL]) -> Void)?
    var onTargetChanged: ((Bool) -> Void)?
    private var isDropTargeted = false

    private func setTargeted(_ targeted: Bool) {
        isDropTargeted = targeted
        needsDisplay = true
        onTargetChanged?(targeted)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isDropTargeted else { return }
        NSColor(red: 0.91, green: 0.39, blue: 0.30, alpha: 1).setStroke()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), xRadius: 10, yRadius: 10)
        path.lineWidth = 2
        path.stroke()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    // Transparent to clicks so buttons beneath remain interactive.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let dominated = hasPDFFiles(in: sender)
        setTargeted(dominated)
        return dominated ? .copy : []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        hasPDFFiles(in: sender) ? .copy : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        setTargeted(false)
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        hasPDFFiles(in: sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        setTargeted(false)
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
