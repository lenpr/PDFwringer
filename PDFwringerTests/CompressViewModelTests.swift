import Testing
import PDFKit

@Suite("CompressViewModel")
@MainActor
struct CompressViewModelTests {

    @Test("setSource loads page count and file size")
    func setSourceLoadsInfo() {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 5)
        defer { TestPDFGenerator.cleanup(source) }

        let vm = CompressViewModel()
        vm.setSource(source)

        #expect(vm.sourceURL == source)
        #expect(vm.sourcePageCount == 5)
        #expect(vm.sourceFileSize > 0)
    }

    @Test("canCompress requires source and not processing")
    func canCompressLogic() {
        let vm = CompressViewModel()
        #expect(vm.canCompress == false)

        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        defer { TestPDFGenerator.cleanup(source) }

        vm.setSource(source)
        #expect(vm.canCompress == true)
    }

    @Test("setSource clears previous result")
    func setSourceClearsResult() {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        defer { TestPDFGenerator.cleanup(source) }

        let vm = CompressViewModel()
        vm.resultMessage = "old result"
        vm.isError = true

        vm.setSource(source)
        #expect(vm.resultMessage == nil)
        #expect(vm.isError == false)
    }

    @Test("Heuristic estimates are computed on setSource")
    func heuristicsComputed() {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 3)
        defer { TestPDFGenerator.cleanup(source) }

        let vm = CompressViewModel()
        vm.setSource(source)

        // Heuristics should be populated for all rasterize levels
        let key = "\(CompressionLevel.medium.rawValue)-\(JPEGQuality.good.rawValue)-false"
        #expect(vm.heuristicSizes[key] != nil)
        #expect(vm.heuristicSizes[key]! > 0)
    }

    @Test("Cancelling estimation prevents exact results from publishing")
    func cancellingEstimationSuppressesResults() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        defer { TestPDFGenerator.cleanup(source) }

        let vm = CompressViewModel()
        vm.setSource(source)
        vm.cancelEstimation()

        try await Task.sleep(for: .milliseconds(300))
        #expect(vm.estimatedSizes.isEmpty)
        #expect(!vm.heuristicSizes.isEmpty)
    }
}
