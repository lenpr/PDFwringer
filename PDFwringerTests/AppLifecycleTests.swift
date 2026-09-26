import AppKit
import PDFKit
import Testing

@Suite("Application lifecycle")
@MainActor
struct AppLifecycleTests {
    @MainActor private final class OperationState { var running = true }
    @Test("Adapted delegate delivers cold and warm file-open events")
    func fileOpenDelivery() throws {
        let first = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        let second = TestPDFGenerator.makeRenderedPDF(pageCount: 2)
        defer { TestPDFGenerator.cleanup(first); TestPDFGenerator.cleanup(second) }
        let delegate = AppDelegate()
        delegate.application(NSApplication.shared, open: [first])
        let vm = AppViewModel()
        delegate.configure(with: vm)
        #expect(vm.currentPageCount == 1)
        delegate.application(NSApplication.shared, open: [second])
        #expect(vm.currentPageCount == 2)
    }

    @Test("Rejecting discard preserves edits across Back, Open, drop, Start Over, Close and Quit")
    func rejectedDiscard() async throws {
        let first = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        let second = TestPDFGenerator.makeRenderedPDF(pageCount: 2)
        defer { TestPDFGenerator.cleanup(first); TestPDFGenerator.cleanup(second) }
        var prompts = 0
        let vm = AppViewModel(confirmDiscard: { prompts += 1; return false })
        vm.loadSingleFile(first)
        vm.selectMetadata()
        vm.hasUnsavedChanges = true
        vm.goBack()
        vm.loadSingleFile(second)
        vm.handleDrop([second])
        await vm.loadMultipleFiles([first, second]).value
        vm.confirmStartOver()
        #expect(!vm.closeWorkflow())
        let delegate = AppDelegate()
        delegate.configure(with: vm)
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateCancel)
        #expect(prompts == 7)
        guard case .editingMetadata(let url, _) = vm.state else {
            Issue.record("Unsaved editor was discarded")
            return
        }
        #expect(url == first)
        #expect(vm.hasUnsavedChanges)
    }

    @Test("Active writes block leaving even when discard would be accepted")
    func activeOperationBlocksLeaving() {
        var prompts = 0
        let vm = AppViewModel(confirmDiscard: { prompts += 1; return true })
        vm.hasUnsavedChanges = true
        let operation = OperationState()
        vm.operationIsRunning = { operation.running }
        #expect(!vm.canLeaveWorkflow())
        #expect(!vm.closeWorkflow())
        #expect(prompts == 0)
        #expect(vm.showErrorAlert)
        operation.running = false
        #expect(vm.closeWorkflow())
        #expect(prompts == 1)
        #expect(vm.isLanding)
        #expect(!vm.hasUnsavedChanges)
    }
}
