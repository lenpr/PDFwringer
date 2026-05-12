import Testing
import PDFKit

@Suite("ConcatenateViewModel")
@MainActor
struct ConcatenateViewModelTests {

    @Test("canConcatenate requires at least 2 files")
    func canConcatenateRequiresMinimumFiles() {
        let vm = ConcatenateViewModel()
        #expect(vm.canConcatenate == false)

        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        defer { TestPDFGenerator.cleanup(source) }

        vm.files = [PDFFileItem(url: source, pageCount: 1)]
        #expect(vm.canConcatenate == false)

        vm.files.append(PDFFileItem(url: source, pageCount: 1))
        #expect(vm.canConcatenate == true)
    }

    @Test("canConcatenate is false while processing")
    func canConcatenateFalseWhenProcessing() {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        defer { TestPDFGenerator.cleanup(source) }

        let vm = ConcatenateViewModel()
        vm.files = [
            PDFFileItem(url: source, pageCount: 1),
            PDFFileItem(url: source, pageCount: 1)
        ]
        #expect(vm.canConcatenate == true)

        vm.isProcessing = true
        #expect(vm.canConcatenate == false)
    }
}
