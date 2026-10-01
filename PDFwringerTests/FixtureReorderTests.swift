import Foundation
import PDFKit
import Testing

@Suite("Fixture: Reorder preservation", .serialized)
@MainActor
struct FixtureReorderTests {
    @Test("Optimized reordering matches the established page serialization path",
          arguments: FixtureDiscovery.assemblyDerivationFixtures)
    func preservePages(fixture: FixtureDiscovery.Fixture) async throws {
        let document = try #require(PDFDocument(url: fixture.url))
        let directory = TestPDFGenerator.makeTempDirectory()
        let destination = directory.appending(component: "reordered.pdf")
        defer { TestPDFGenerator.cleanup(directory) }
        let sourceBytes = try Data(contentsOf: fixture.url)
        let order = Array((0..<document.pageCount).reversed())
        try await PDFPageReorderer().reorder(document: document, source: fixture.url,
                                            destination: destination, pageOrder: order,
                                            progress: { _ in })
        // PDFKit normalizes text ordering, nonzero box origins and some widget
        // values during serialization. Compare against the established path,
        // rather than silently allowing an optimization to add new losses.
        let reference = PDFDocument()
        for index in order {
            let page = try #require(document.page(at: index))
            let data = try #require(page.dataRepresentation)
            let isolated = try #require(PDFDocument(data: data))
            let copy = try #require(isolated.page(at: 0)?.copy() as? PDFPage)
            reference.insert(copy, at: reference.pageCount)
        }
        let referenceURL = directory.appending(component: "reference.pdf")
        #expect(reference.write(to: referenceURL))
        let serializedReference = try #require(PDFDocument(url: referenceURL))
        let output = try #require(PDFDocument(url: destination))
        #expect(output.pageCount == order.count)
        for position in order.indices {
            let original = try #require(serializedReference.page(at: position))
            let moved = try #require(output.page(at: position))
            // PDFKit may infer slightly different whitespace from equivalent
            // glyph positioning. Every non-whitespace character must survive.
            #expect(moved.string?.filter { !$0.isWhitespace } == original.string?.filter { !$0.isWhitespace })
            #expect(moved.rotation == original.rotation)
            #expect(moved.bounds(for: .mediaBox) == original.bounds(for: .mediaBox))
            #expect(moved.bounds(for: .cropBox) == original.bounds(for: .cropBox))
            #expect(moved.annotations.map(\.contents) == original.annotations.map(\.contents))
            #expect(moved.annotations.count == original.annotations.count)
            for (actual, expected) in zip(moved.annotations, original.annotations) {
                #expect(PDFAssertions.rectanglesMatch(actual.bounds, expected.bounds, tolerance: 0.001))
            }
            #expect(moved.annotations.map(\.widgetStringValue) == original.annotations.map(\.widgetStringValue))
        }
        #expect(try Data(contentsOf: fixture.url) == sourceBytes)
    }
}
