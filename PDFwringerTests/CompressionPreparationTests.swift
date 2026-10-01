import Foundation
import PDFKit
import Testing

@Suite("Compression preparation")
@MainActor
struct CompressionPreparationTests {
    @Test("Size limits use complete localized decimal input and exact byte boundaries")
    func targetParsing() {
        let english = Locale(identifier: "en_US")
        let german = Locale(identifier: "de_DE")
        #expect(CompressionTarget.bytes(from: "0.1", locale: english) == 100_000)
        #expect(CompressionTarget.bytes(from: "1.000001", locale: english) == 1_000_001)
        #expect(CompressionTarget.bytes(from: " 10.5 ", locale: english) == 10_500_000)
        #expect(CompressionTarget.bytes(from: "1000", locale: english) == 1_000_000_000)
        #expect(CompressionTarget.bytes(from: "1,5", locale: german) == 1_500_000)
        for invalid in ["", "0", "-1", "NaN", "inf", "1e2", "1 MB", "1.2junk", "1,000", "0.099999", "1000.000001", "1.0000001", String(repeating: "9", count: 400)] {
            #expect(CompressionTarget.bytes(from: invalid, locale: english) == nil)
        }
        #expect(CompressionTarget.bytes(from: "1.5", locale: german) == nil)
    }

    @Test("Preparation preserves source and destination, then saves exactly the reviewed bytes")
    func reviewBeforePublication() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2)
        let directory = TestPDFGenerator.makeTempDirectory()
        defer { TestPDFGenerator.cleanup(source); try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appending(component: "output.pdf")
        let previous = Data("existing destination".utf8)
        try previous.write(to: destination)
        let original = try Data(contentsOf: source)
        let document = try #require(PDFDocument(url: source))
        let candidate = try await PDFCompressor().prepare(document: document, source: source,
            destination: destination, level: .medium, quality: .good, grayscale: false, progress: { _ in })
        #expect(try Data(contentsOf: destination) == previous)
        #expect(try Data(contentsOf: source) == original)
        #expect(candidate.previewDocument?.pageCount == 2)
        let reviewed = try Data(contentsOf: candidate.url)
        try await candidate.commit()
        #expect(try Data(contentsOf: destination) == reviewed)
        #expect(try Data(contentsOf: source) == original)
        #expect(!FileManager.default.fileExists(atPath: candidate.url.path))
    }

    @Test("Late destination replacement and creation are rejected without clobbering")
    func changedDestination() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        let directory = TestPDFGenerator.makeTempDirectory()
        defer { TestPDFGenerator.cleanup(source); try? FileManager.default.removeItem(at: directory) }
        let document = try #require(PDFDocument(url: source))
        for existed in [false, true] {
            let destination = directory.appending(component: "result-\(existed).pdf")
            if existed { try Data("first".utf8).write(to: destination) }
            let candidate = try await PDFCompressor().prepare(document: document, source: source,
                destination: destination, level: .lossless, quality: .good, grayscale: false, progress: { _ in })
            let replacement = Data("external replacement".utf8)
            let replacementURL = directory.appending(component: "replacement.pdf")
            try replacement.write(to: replacementURL)
            if existed { try FileManager.default.moveItem(at: destination, to: directory.appending(component: "original.pdf")) }
            try FileManager.default.moveItem(at: replacementURL, to: destination)
            do { try await candidate.commit(); Issue.record("Expected changed-destination rejection") }
            catch { guard case PDFwringerError.destinationChanged = error else { Issue.record("Unexpected error: \(error)"); return } }
            #expect(try Data(contentsOf: destination) == replacement)
            #expect(FileManager.default.fileExists(atPath: candidate.url.path))
        }
    }

    @Test("Abandoning a candidate removes its staged file and directory")
    func discardedCandidate() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        let directory = TestPDFGenerator.makeTempDirectory()
        defer { TestPDFGenerator.cleanup(source); try? FileManager.default.removeItem(at: directory) }
        let vm = CompressViewModel()
        vm.setSource(source)
        await vm.prepare(to: directory.appending(component: "result.pdf"))
        let url = try #require(vm.prepared?.url)
        #expect(vm.hasPreparedResult)
        vm.cancel()
        #expect(!vm.hasPreparedResult)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
    }

    @Test("Settings changes invalidate the result and reset explicit raster consent on a new source")
    func settingsAndSourceChanges() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        let directory = TestPDFGenerator.makeTempDirectory()
        defer { TestPDFGenerator.cleanup(source); try? FileManager.default.removeItem(at: directory) }
        let vm = CompressViewModel()
        vm.setSource(source)
        await vm.prepare(to: directory.appending(component: "result.pdf"))
        let url = try #require(vm.prepared?.url)
        vm.selectedQuality = .best
        #expect(!vm.hasPreparedResult)
        #expect(!vm.comparisonShowsResult)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        vm.allowRasterization = true
        vm.setSource(source)
        #expect(!vm.allowRasterization)
        vm.mode = .targetSize
        vm.targetMegabytes = "bad"
        #expect(!vm.canCompress)
    }

    @Test("A failed save keeps the candidate; re-preparing captures the new destination identity")
    func saveFailureAndRecovery() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        let directory = TestPDFGenerator.makeTempDirectory()
        defer { TestPDFGenerator.cleanup(source); try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appending(component: "result.pdf")
        let vm = CompressViewModel()
        vm.setSource(source)
        await vm.prepare(to: destination)
        let firstURL = try #require(vm.prepared?.url)
        let external = Data("external file arrived".utf8)
        try external.write(to: destination)
        await vm.savePreparedResult()
        #expect(vm.isError)
        #expect(vm.hasPreparedResult)
        #expect(vm.lastOutputURL == nil)
        #expect(try Data(contentsOf: destination) == external)
        await vm.prepare(to: destination)
        #expect(!FileManager.default.fileExists(atPath: firstURL.path))
        let reviewed = try Data(contentsOf: #require(vm.prepared?.url))
        await vm.savePreparedResult()
        #expect(!vm.isError)
        #expect(!vm.hasPreparedResult)
        #expect(vm.lastOutputURL == destination)
        #expect(try Data(contentsOf: destination) == reviewed)
    }

    @Test("Already-under-limit preflight measures the current file and clears stale errors")
    func currentFileSizePreflight() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        defer { TestPDFGenerator.cleanup(source) }
        let vm = CompressViewModel()
        vm.setSource(source)
        vm.mode = .targetSize
        vm.isError = true
        await vm.performCompression()
        #expect(!vm.isError)
        #expect(vm.resultMessage?.contains("Already below") == true)
        try FileManager.default.removeItem(at: source)
        await vm.performCompression()
        #expect(vm.isError)
        #expect(!vm.hasPreparedResult)
        #expect(vm.lastOutputURL == nil)
    }

    @Test("Publication permission failures preserve the reviewed result and allow retry", arguments: [false, true])
    func publicationPermissionRecovery(existing: Bool) async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        let directory = TestPDFGenerator.makeTempDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(directory)
        }
        let destination = directory.appending(component: "result.pdf")
        let original = try Data(contentsOf: source)
        if existing { try original.write(to: destination) }
        let vm = CompressViewModel()
        vm.setSource(source)
        vm.selectedLevel = .lossless
        await vm.prepare(to: destination)
        let staged = try #require(vm.prepared?.url)
        let reviewed = try Data(contentsOf: staged)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        await vm.savePreparedResult()
        #expect(vm.isError)
        #expect(vm.resultMessage?.contains("Choose a folder") == true)
        #expect(vm.hasPreparedResult)
        #expect(vm.lastOutputURL == nil)
        #expect((try? Data(contentsOf: destination)) == (existing ? original : nil))
        #expect(try Data(contentsOf: staged) == reviewed)
        #expect(try Data(contentsOf: source) == original)

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        await vm.savePreparedResult()
        #expect(!vm.isError)
        #expect(!vm.hasPreparedResult)
        #expect(vm.lastOutputURL == destination)
        #expect(try Data(contentsOf: destination) == reviewed)
        #expect(PDFDocument(url: destination)?.pageCount == 1)
        #expect(!FileManager.default.fileExists(atPath: staged.deletingLastPathComponent().path))
    }

    @Test("A source change during rendering suppresses late completion")
    func supersededPreparation() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 4)
        let second = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        let directory = TestPDFGenerator.makeTempDirectory()
        defer {
            TestPDFGenerator.cleanup(source); TestPDFGenerator.cleanup(second)
            try? FileManager.default.removeItem(at: directory)
        }
        let vm = CompressViewModel()
        vm.setSource(source)
        let task = Task { await vm.prepare(to: directory.appending(component: "result.pdf")) }
        while !vm.isProcessing { await Task.yield() }
        vm.setSource(second)
        await task.value
        #expect(vm.sourceURL == second)
        #expect(!vm.hasPreparedResult)
        #expect(!vm.isProcessing)
        #expect(!FileManager.default.fileExists(atPath: directory.appending(component: "result.pdf").path))
    }

    @Test("Already-small originals and unattainable targets do not publish files")
    func noOutputNeededOrPossible() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        let directory = TestPDFGenerator.makeTempDirectory()
        defer { TestPDFGenerator.cleanup(source); try? FileManager.default.removeItem(at: directory) }
        let document = try #require(PDFDocument(url: source))
        let destination = directory.appending(component: "result.pdf")
        let original = try Data(contentsOf: source)
        let sentinel = Data("previous destination".utf8)
        try sentinel.write(to: destination)
        let small = try await PDFCompressor().prepareToFit(document: document, source: source,
            destination: destination, limitBytes: Int64(original.count) + 1, allowRasterization: true,
            grayscale: false, progress: { _ in Issue.record("Already-small input must not render") })
        guard case .alreadyUnderLimit = small else { Issue.record("Expected already-small result"); return }
        var progress: [Double] = []
        let impossible = try await PDFCompressor().prepareToFit(document: document, source: source,
            destination: destination, limitBytes: 1, allowRasterization: true,
            grayscale: false, progress: { progress.append($0) })
        guard case .unattainable(let smallest) = impossible else { Issue.record("Expected unmet target"); return }
        #expect(smallest > 1)
        #expect(progress.last == 1)
        #expect(zip(progress, progress.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(try Data(contentsOf: source) == original)
        #expect(try Data(contentsOf: destination) == sentinel)
        let outputs = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "pdf" }.map(\.lastPathComponent)
        #expect(outputs == [destination.lastPathComponent])
    }

    @Test("Lossless success and exactly-at-limit output use measured complete files")
    func losslessThreshold() async throws {
        let source = try makeTextPDF()
        let directory = TestPDFGenerator.makeTempDirectory()
        defer { TestPDFGenerator.cleanup(source); try? FileManager.default.removeItem(at: directory) }
        let document = try #require(PDFDocument(url: source))
        document.documentAttributes = [PDFDocumentAttribute.titleAttribute: String(repeating: "metadata", count: 30_000)]
        #expect(document.write(to: source))
        let baseline = try await PDFCompressor().prepare(document: document, source: source,
            destination: directory.appending(component: "baseline.pdf"), level: .lossless,
            quality: .good, grayscale: false, progress: { _ in })
        for extra in [Int64(0), 1] {
            let result = try await PDFCompressor().prepareToFit(document: document, source: source,
                destination: directory.appending(component: "target-\(extra).pdf"),
                limitBytes: baseline.outputSize + extra, allowRasterization: false,
                grayscale: false, progress: { _ in })
            if extra == 0 {
                guard case .unattainable = result else { Issue.record("Equal size must not qualify"); return }
            } else {
                guard case .prepared(let candidate) = result else { Issue.record("Expected lossless fit"); return }
                #expect(candidate.level == .lossless)
                #expect(candidate.previewDocument?.string?.contains("Page 1") == true)
            }
        }
    }

    @Test("Each raster preset can win only after explicit consent, in highest-resolution-first order")
    func rasterThresholds() async throws {
        let directory = TestPDFGenerator.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try makeNoisePDF(in: directory)
        let document = try #require(PDFDocument(url: source))
        var sizes: [CompressionLevel: Int64] = [:]
        for level in [CompressionLevel.lossless, .high, .medium, .low] {
            let candidate = try await PDFCompressor().prepare(document: document, source: source,
                destination: directory.appending(component: "baseline-\(level).pdf"), level: level,
                quality: .good, grayscale: false, progress: { _ in })
            sizes[level] = candidate.outputSize
        }
        #expect(try #require(sizes[.lossless]) > #require(sizes[.high]))
        #expect(try #require(sizes[.high]) > #require(sizes[.medium]))
        #expect(try #require(sizes[.medium]) > #require(sizes[.low]))
        for level in [CompressionLevel.high, .medium, .low] {
            let limit = try #require(sizes[level]) + 1
            let destination = directory.appending(component: "target-\(level).pdf")
            let denied = try await PDFCompressor().prepareToFit(document: document, source: source,
                destination: destination, limitBytes: limit, allowRasterization: false,
                grayscale: false, progress: { _ in })
            guard case .unattainable = denied else { Issue.record("Rasterization requires consent"); return }
            let allowed = try await PDFCompressor().prepareToFit(document: document, source: source,
                destination: destination, limitBytes: limit, allowRasterization: true,
                grayscale: false, progress: { _ in })
            guard case .prepared(let candidate) = allowed else { Issue.record("Expected raster fit"); return }
            #expect(candidate.level == level)
            #expect(candidate.outputSize < limit)
            #expect(!FileManager.default.fileExists(atPath: destination.path))
        }
    }

    @Test("Cancellation before review never reports completion or changes existing files",
          arguments: [CompressionLevel.lossless, .medium])
    func cancelledPreparation(level: CompressionLevel) async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        let directory = TestPDFGenerator.makeTempDirectory()
        defer { TestPDFGenerator.cleanup(source); try? FileManager.default.removeItem(at: directory) }
        let document = try #require(PDFDocument(url: source))
        let destination = directory.appending(component: "result.pdf")
        let old = Data("existing".utf8)
        try old.write(to: destination)
        let original = try Data(contentsOf: source)
        var completed = false
        let task = Task {
            try await PDFCompressor().prepare(document: document, source: source,
                destination: destination, level: level, quality: .good, grayscale: false,
                progress: { value in
                    if value == 1 { completed = true }
                    if value >= 0.99 { withUnsafeCurrentTask { $0?.cancel() } }
                })
        }
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch { #expect(error is CancellationError) }
        #expect(!completed)
        #expect(try Data(contentsOf: source) == original)
        #expect(try Data(contentsOf: destination) == old)
    }

    @Test("Target mode preserves permission failures instead of treating them as size misses")
    func permissionsFailClosed() async throws {
        let source = TestPDFGenerator.makeAssemblyRestrictedPDF()
        let directory = TestPDFGenerator.makeTempDirectory()
        defer { TestPDFGenerator.cleanup(source); try? FileManager.default.removeItem(at: directory) }
        let document = try #require(PDFDocument(url: source))
        var progressCalls = 0
        do {
            _ = try await PDFCompressor().prepareToFit(document: document, source: source,
                destination: directory.appending(component: "result.pdf"), limitBytes: 1,
                allowRasterization: true, grayscale: false, progress: { _ in progressCalls += 1 })
            Issue.record("Expected permissions rejection")
        } catch { #expect(error is PDFwringerError) }
        #expect(progressCalls == 0)
        #expect(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).isEmpty)
    }

    @Test("Protected lossless candidates retain protection without exposing a preview or storing a password")
    func protectedLosslessCandidate() async throws {
        let source = try makeTextPDF()
        let directory = TestPDFGenerator.makeTempDirectory()
        defer { TestPDFGenerator.cleanup(source); try? FileManager.default.removeItem(at: directory) }
        let base = try #require(PDFDocument(url: source))
        #expect(base.write(to: source, withOptions: [.ownerPasswordOption: "owner-test", .userPasswordOption: "user-test"]))
        let document = try #require(PDFDocument(url: source))
        #expect(document.unlock(withPassword: "user-test"))
        let candidate = try await PDFCompressor().prepare(document: document, source: source,
            destination: directory.appending(component: "protected.pdf"), level: .lossless,
            quality: .good, grayscale: false, progress: { _ in })
        #expect(candidate.previewDocument == nil)
        let reviewed = try Data(contentsOf: candidate.url)
        try await candidate.commit()
        #expect(try Data(contentsOf: candidate.destination) == reviewed)
        let saved = try #require(PDFDocument(url: candidate.destination))
        #expect(saved.isEncrypted && saved.isLocked)
        #expect(!saved.unlock(withPassword: "wrong"))
        #expect(saved.unlock(withPassword: "user-test"))
        #expect(saved.string?.contains("Page 1") == true)
    }

    private func makeTextPDF() throws -> URL {
        let url = URL.temporaryDirectory.appending(component: "text-\(UUID()).pdf")
        var box = CGRect(x: 0, y: 0, width: 200, height: 300)
        let context = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        ("Page 1" as NSString).draw(at: CGPoint(x: 20, y: 100), withAttributes: [.font: NSFont.systemFont(ofSize: 20)])
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        return url
    }

    private func makeNoisePDF(in directory: URL) throws -> URL {
        var seed: UInt32 = 42
        let bytes: [UInt8] = (0..<(400 * 500 * 3)).map { _ in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return UInt8(truncatingIfNeeded: seed >> 24)
        }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let image = try #require(CGImage(width: 400, height: 500, bitsPerComponent: 8, bitsPerPixel: 24,
            bytesPerRow: 400 * 3, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: 0),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent))
        let url = directory.appending(component: "noise.pdf")
        var box = CGRect(x: 0, y: 0, width: 144, height: 192)
        let context = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.draw(image, in: box)
        context.endPDFPage()
        context.closePDF()
        return url
    }
}
