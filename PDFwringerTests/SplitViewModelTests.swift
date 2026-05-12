import Testing
import PDFKit

@Suite("SplitViewModel")
@MainActor
struct SplitViewModelTests {

    @Test("setSource updates page count")
    func setSourceUpdatesPageCount() {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 7)
        defer { TestPDFGenerator.cleanup(source) }

        let vm = SplitViewModel()
        vm.setSource(source)

        #expect(vm.sourcePageCount == 7)
        #expect(vm.sourceURL == source)
    }

    @Test("canProcess requires source and not processing")
    func canProcessLogic() {
        let vm = SplitViewModel()
        #expect(vm.canProcess == false)

        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 3)
        defer { TestPDFGenerator.cleanup(source) }

        vm.setSource(source)
        #expect(vm.canProcess == true)
    }

    @Test("splitByPages rejects pagesPerFile < 1")
    func splitValidatesMinimum() async {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 5)
        defer { TestPDFGenerator.cleanup(source) }

        let vm = SplitViewModel()
        vm.setSource(source)
        vm.splitPagesPerFile = 0

        await vm.splitByPages()

        #expect(vm.isError == true)
        #expect(vm.errorSource == .split)
        #expect(vm.resultMessage?.contains("at least 1") == true)
    }

    @Test("splitByPages rejects pagesPerFile exceeding page count")
    func splitValidatesMaximum() async {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 5)
        defer { TestPDFGenerator.cleanup(source) }

        let vm = SplitViewModel()
        vm.setSource(source)
        vm.splitPagesPerFile = 10

        await vm.splitByPages()

        #expect(vm.isError == true)
        #expect(vm.errorSource == .split)
        #expect(vm.resultMessage?.contains("exceeds") == true)
    }

    @Test("setSource clears previous state")
    func setSourceClearsState() {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2)
        defer { TestPDFGenerator.cleanup(source) }

        let vm = SplitViewModel()
        vm.resultMessage = "old"
        vm.isError = true

        vm.setSource(source)
        #expect(vm.resultMessage == nil)
        #expect(vm.isError == false)
    }
}
