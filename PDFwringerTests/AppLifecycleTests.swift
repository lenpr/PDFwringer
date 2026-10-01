import AppKit
import PDFKit
import Testing

@Suite("Application lifecycle")
@MainActor
struct AppLifecycleTests {
    @MainActor private final class OperationState { var running = true }
    @Test("Adapted delegate delivers cold and warm file-open events")
    func fileOpenDelivery() async throws {
        let first = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        let second = TestPDFGenerator.makeRenderedPDF(pageCount: 2)
        defer { TestPDFGenerator.cleanup(first); TestPDFGenerator.cleanup(second) }
        let delegate = AppDelegate()
        delegate.application(NSApplication.shared, open: [first])
        let vm = AppViewModel()
        delegate.configure(with: vm)
        await vm.waitForFileIntake()
        #expect(vm.currentPageCount == 1)
        delegate.application(NSApplication.shared, open: [second])
        await vm.waitForFileIntake()
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
        await vm.waitForFileIntake()
        vm.selectMetadata()
        vm.hasUnsavedChanges = true
        vm.goBack()
        vm.loadSingleFile(second)
        await vm.waitForFileIntake()
        vm.handleDrop([second])
        await vm.waitForFileIntake()
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
    func activeOperationBlocksLeaving() async {
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
    @Test("File panels preserve the workflow against reentrant application events")
    func filePanelBlocksReplacement() async throws {
        let first = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        let second = TestPDFGenerator.makeRenderedPDF(pageCount: 2)
        defer { TestPDFGenerator.cleanup(first); TestPDFGenerator.cleanup(second) }
        var prompts = 0
        let vm = AppViewModel(confirmDiscard: { prompts += 1; return true })
        vm.loadSingleFile(first)
        await vm.waitForFileIntake()
        vm.selectCompress()
        guard case .compressing(_, let originalDocument) = vm.state else { return }
        vm.hasUnsavedChanges = true
        let delegate = AppDelegate()
        delegate.configure(with: vm)

        let response = FileDialogHelper.withFilePanel {
            delegate.application(NSApplication.shared, open: [second])
            vm.openRecentDocument(second)
            vm.handleDrop([first, second])
            vm.goBack()
            vm.startOver()
            #expect(!vm.closeWorkflow())
            #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateCancel)
            if case .compressing(let url, let document) = vm.state {
                #expect(url == first)
                #expect(document === originalDocument)
            } else {
                Issue.record("The file panel allowed the active workflow to be replaced")
            }
            #expect(vm.hasUnsavedChanges)
            #expect(prompts == 0)
            #expect(!vm.showErrorAlert)
            return NSApplication.ModalResponse.cancel
        }
        #expect(response == .cancel)
        #expect(!FileDialogHelper.isPresentingFilePanel)
        // The guard must be released after cancellation: a subsequent open works.
        delegate.application(NSApplication.shared, open: [second])
        await vm.waitForFileIntake()
        #expect(vm.currentPageCount == 2)
    }

    @Test("Nested file panels are rejected and either response releases the guard")
    func nestedFilePanels() async {
        for response in [NSApplication.ModalResponse.OK, .cancel] {
            let result = FileDialogHelper.withFilePanel {
                #expect(FileDialogHelper.isPresentingFilePanel)
                let nested = FileDialogHelper.withFilePanel {
                    Issue.record("A second panel was presented during an active panel")
                    return NSApplication.ModalResponse.OK
                }
                #expect(nested == nil)
                #expect(FileDialogHelper.isPresentingFilePanel)
                return response
            }
            #expect(result == response)
            #expect(!FileDialogHelper.isPresentingFilePanel)
        }
    }

}
