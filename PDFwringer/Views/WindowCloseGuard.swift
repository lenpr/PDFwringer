import SwiftUI

/// Intercepts the native close button as well as File > Close, preserving SwiftUI's
/// window delegate for all other callbacks. View disappearance is too late to veto close.
struct WindowCloseGuard: NSViewRepresentable {
    var canClose: @MainActor () -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(canClose: canClose) }
    func makeNSView(context: Context) -> WindowObserver {
        let view = WindowObserver()
        view.coordinator = context.coordinator
        return view
    }
    func updateNSView(_ view: WindowObserver, context: Context) {
        context.coordinator.canClose = canClose
    }
    static func dismantleNSView(_ view: WindowObserver, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class WindowObserver: NSView {
        weak var coordinator: Coordinator?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { coordinator?.attach(to: window) }
        }
    }

    @MainActor final class Coordinator: NSObject, NSWindowDelegate {
        var canClose: @MainActor () -> Bool
        private weak var window: NSWindow?
        // AppKit forwards these Objective-C callbacks on the main thread.
        nonisolated(unsafe) private weak var originalDelegate: (any NSWindowDelegate)?

        init(canClose: @escaping @MainActor () -> Bool) { self.canClose = canClose }
        func attach(to window: NSWindow) {
            guard self.window !== window else { return }
            detach()
            self.window = window
            originalDelegate = window.delegate
            window.delegate = self
        }
        func detach() {
            if window?.delegate === self { window?.delegate = originalDelegate }
            window = nil
        }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            (originalDelegate?.windowShouldClose?(sender) ?? true) && canClose()
        }
        override func responds(to selector: Selector!) -> Bool {
            if super.responds(to: selector) { return true }
            return MainActor.assumeIsolated { originalDelegate?.responds(to: selector) ?? false }
        }
        override func forwardingTarget(for selector: Selector!) -> Any? {
            precondition(Thread.isMainThread)
            return originalDelegate
        }
    }
}
