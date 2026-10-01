import Foundation
import PDFKit
import Testing

@Suite("Fixture: Read-only snapshot fidelity", .serialized)
@MainActor
struct FixtureSnapshotTests {
    @Test("Source-byte preview snapshots match the established path",
          arguments: FixtureDiscovery.openableFixtures)
    func pixelParity(fixture: FixtureDiscovery.Fixture) async throws {
        let source = try Data(contentsOf: fixture.url)
        let document = try #require(PDFDocument(data: source))
        for index in Set([0, max(0, document.pageCount - 1)]) {
            let page = try #require(document.page(at: index))
            let snapshot = try await PDFPageWorker.readOnlySnapshot(sourceData: source, index: index,
                rotation: page.rotation, cropBox: page.bounds(for: .cropBox), mediaBox: page.bounds(for: .mediaBox))
            if document.isEncrypted || !page.annotations.isEmpty {
                #expect(snapshot == nil)
                continue
            }
            let actualData = try #require(snapshot)
            let referenceData = try #require(page.dataRepresentation)
            let pixels = CGSize(width: 192, height: 256)
            let reference = try await PDFPageWorker.run(pageData: referenceData) {
                try #require(PDFRasterizer.renderPreview($0, pixelSize: pixels))
            }
            let actual = try await PDFPageWorker.run(pageData: actualData) {
                try #require(PDFRasterizer.renderPreview($0, pixelSize: pixels))
            }
            #expect(reference.width == actual.width && reference.height == actual.height)
            #expect(reference.dataProvider?.data == actual.dataProvider?.data)
        }
    }
}
