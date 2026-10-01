import AppKit
import Darwin
import Foundation
import PDFKit

// Optional optimized release benchmark. Runs each case in a fresh process;
// filenames remain in local output only, never in the application's logs.
@MainActor private final class Heartbeat {
    var maxGap = Duration.zero
    private var task: Task<Void, Never>?
    func start() async {
        task = Task { @MainActor in
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(5))
                let now = ContinuousClock.now
                maxGap = max(maxGap, now - last)
                last = now
            }
        }
        try? await Task.sleep(for: .milliseconds(10))
        maxGap = .zero
    }
    func finish() async -> Double {
        try? await Task.sleep(for: .milliseconds(10))
        task?.cancel()
        return max(0, milliseconds(maxGap) - 5)
    }
}

private func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
}

@main struct PerformanceBenchmark {
    @MainActor static func main() async {
        do { try await run() }
        catch { fputs("Performance benchmark failed: \(error)\n", stderr); exit(1) }
    }

    @MainActor private static func run() async throws {
        guard CommandLine.arguments.count == 4 else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let mode = CommandLine.arguments[1]
        let source = URL(fileURLWithPath: CommandLine.arguments[2])
        let directory = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if mode == "generate" || mode == "generate2000" {
            let count = mode == "generate2000" ? 2_000 : 400
            guard let base = PDFDocument(url: source), base.pageCount > 0 else {
                throw PDFwringerError.cannotOpenDocument
            }
            let document = PDFDocument()
            for index in 0..<count {
                guard let page = base.page(at: index % base.pageCount)?.copy() as? PDFPage else {
                    throw PDFwringerError.cannotOpenDocument
                }
                document.insert(page, at: index)
            }
            guard document.write(to: directory.appending(component: "vector-\(count).pdf")) else {
                throw PDFwringerError.cannotWriteOutput
            }
            return
        }

        if ["preview", "preview-cached", "preview-sized", "preview-source"].contains(mode) {
            try await measurePreview(source: source, mode: mode)
            return
        }
        if mode == "thumbnail-priority" {
            try await measureThumbnails(source: source)
            return
        }

        if mode == "estimates" || mode == "file-open" || mode == "review-save" {
            for iteration in 1...3 {
                let vm = AppViewModel()
                var candidate: PDFCompressor.PreparedCompression?
                if mode == "review-save" {
                    guard let document = PDFDocument(url: source) else { throw PDFwringerError.cannotOpenDocument }
                    candidate = try await PDFCompressor().prepare(document: document, source: source,
                        destination: directory.appending(component: "reviewed.pdf"), level: .lossless,
                        quality: .good, grayscale: false, progress: { _ in })
                }
                let heartbeat = Heartbeat()
                await heartbeat.start()
                let start = ContinuousClock.now
                var count = 0
                if mode == "estimates" {
                    let worker = Task.detached {
                        try PDFCompressor().estimateFirstPageSizes(source: source, quality: .good, grayscale: false)
                    }
                    count = try await worker.value.count
                } else if mode == "file-open" {
                    vm.loadSingleFile(source)
                    await vm.waitForFileIntake()
                    guard vm.hasDocument else { throw PDFwringerError.cannotOpenDocument }
                    count = vm.currentPageCount
                } else if let candidate {
                    try await candidate.commit()
                    count = candidate.previewDocument?.pageCount ?? 0
                }
                let elapsed = milliseconds(ContinuousClock.now - start)
                let gap = await heartbeat.finish()
                vm.startOver()
                try? FileManager.default.removeItem(at: directory.appending(component: "reviewed.pdf"))
                var usage = rusage()
                getrusage(RUSAGE_SELF, &usage)
                let record: [String: Any] = ["operation": mode, "iteration": iteration,
                    "resultCount": count, "elapsedMS": elapsed, "maxMainActorLatenessMS": gap,
                    "peakRSSMiB": Double(usage.ru_maxrss) / 1_048_576]
                print(String(decoding: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), as: UTF8.self))
            }
            return
        }

        if ["tool-entry", "rotate-edit", "crop-edit", "resize-edit"].contains(mode) {
            for iteration in 1...3 {
                guard let document = PDFDocument(url: source), !document.isLocked else {
                    throw PDFwringerError.cannotOpenDocument
                }
                let heartbeat = Heartbeat()
                await heartbeat.start()
                let start = ContinuousClock.now
                switch mode {
                case "tool-entry":
                    let vm = AppViewModel()
                    vm.state = .singleFile(source, document)
                    vm.selectRotate()
                    while vm.isPreparingTool { try await Task.sleep(for: .milliseconds(1)) }
                    guard case .rotating(_, _, let working) = vm.state,
                          working.pageCount == document.pageCount else {
                        throw PDFwringerError.cannotCreateOutput
                    }
                case "rotate-edit":
                    try await PDFRotator().rotateInBatches(document: document, angle: .ninety,
                        pageIndices: Array(0..<document.pageCount), progress: { _ in })
                case "crop-edit":
                    _ = try await PDFCropper().cropInBatches(document: document,
                        indices: Array(0..<document.pageCount), top: 1, bottom: 1, left: 1, right: 1)
                default:
                    _ = try await PDFCropper().resizeInBatches(document: document,
                        indices: Array(0..<document.pageCount), targetSize: CGSize(width: 595, height: 842))
                }
                let elapsed = milliseconds(ContinuousClock.now - start)
                let gap = await heartbeat.finish()
                var usage = rusage()
                getrusage(RUSAGE_SELF, &usage)
                let record: [String: Any] = ["operation": mode, "iteration": iteration,
                    "inputPages": document.pageCount, "elapsedMS": elapsed,
                    "maxMainActorLatenessMS": gap, "peakRSSMiB": Double(usage.ru_maxrss) / 1_048_576]
                print(String(decoding: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), as: UTF8.self))
            }
            return
        }

        for iteration in 1...3 {
            guard let document = PDFDocument(url: source), !document.isLocked else {
                throw PDFwringerError.cannotOpenDocument
            }
            let output = directory.appending(component: "\(mode)-\(iteration).pdf")
            defer { try? FileManager.default.removeItem(at: output) }
            let heartbeat = Heartbeat()
            await heartbeat.start()
            let start = ContinuousClock.now
            switch mode {
            case "merge":
                _ = try await PDFConcatenator().concatenate(sources: Array(repeating: source, count: 10),
                                                           destination: output, progress: { _ in })
            case "reorder":
                try await PDFPageReorderer().reorder(document: document, source: source,
                                                    destination: output,
                                                    pageOrder: Array((0..<document.pageCount).reversed()),
                                                    progress: { _ in })
            case "color":
                try await PDFColorAdjuster().adjust(document: document, source: source,
                                                    destination: output,
                                                    settings: .init(brightness: 0.1, contrast: 1.2, saturation: 0.8),
                                                    pages: nil, progress: { _ in })
            case "save":
                let result = await DocumentSaver.save(document: document, source: source, to: output)
                guard !result.isError, result.outputURL == output else {
                    throw PDFwringerError.cannotWriteOutput
                }
            case "metadata":
                try await PDFMetadataEditor().write(
                    metadata: .init(title: "Benchmark", author: "", subject: "", keywords: "", creator: ""),
                    document: document, source: source, destination: output
                )
            case "lossless":
                _ = try await PDFCompressor().compress(document: document, source: source,
                                                       destination: output, level: .lossless,
                                                       quality: .good, grayscale: false,
                                                       progress: { _ in })
            case "compress":
                let prepared = try await PDFCompressor().prepare(document: document, source: source,
                                                                 destination: output, level: .medium,
                                                                 quality: .good, grayscale: false,
                                                                 progress: { _ in })
                try await prepared.commit()
            default: throw PDFwringerError.cannotCreateOutput
            }
            let elapsed = milliseconds(ContinuousClock.now - start)
            let gap = await heartbeat.finish()
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            guard let verified = PDFDocument(url: output), verified.pageCount > 0 else {
                throw PDFwringerError.cannotWriteOutput
            }
            let record: [String: Any] = [
                "operation": mode, "iteration": iteration, "inputPages": document.pageCount,
                "outputPages": verified.pageCount, "elapsedMS": elapsed,
                "maxMainActorLatenessMS": gap, "peakRSSMiB": Double(usage.ru_maxrss) / 1_048_576
            ]
            let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
        }
    }
    @MainActor private static func measurePreview(source: URL, mode: String) async throws {
        let revision: Int? = mode == "preview" ? nil : 0
        // A fixed device-pixel viewport isolates cache/size effects. The real
        // editor measures its pane and display scale instead of using this size.
        let pixels: CGSize? = ["preview-sized", "preview-source"].contains(mode) ? CGSize(width: 640, height: 1024) : nil
        for iteration in 1...3 {
            guard let document = PDFDocument(url: source), !document.isLocked else {
                throw PDFwringerError.cannotOpenDocument
            }
            let sourceData = mode == "preview-source" ? try Data(contentsOf: source) : nil
            let previewDocument = sourceData.flatMap { PDFDocument(data: $0) } ?? document
            let vm = ColorAdjustViewModel()
            defer { vm.cancelPreview() }
            let heartbeat = Heartbeat()
            await heartbeat.start()
            let firstStart = ContinuousClock.now
            vm.updatePreview(document: previewDocument, page: 0, documentRevision: revision, pixelSize: pixels, sourceData: sourceData)
            try await waitForPreview(vm)
            let firstMS = milliseconds(ContinuousClock.now - firstStart)
            let firstGap = await heartbeat.finish()
            let warmHeartbeat = Heartbeat()
            await warmHeartbeat.start()
            var warm: [Double] = []
            for step in 1...6 {
                vm.brightness = Float(step) * 0.05
                let start = ContinuousClock.now
                vm.updatePreview(document: previewDocument, page: 0, documentRevision: revision, pixelSize: pixels, sourceData: sourceData)
                try await waitForPreview(vm)
                warm.append(milliseconds(ContinuousClock.now - start))
            }
            let warmGap = await warmHeartbeat.finish()
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            let record: [String: Any] = [
                "operation": mode, "input": source.lastPathComponent, "iteration": iteration,
                "firstPreviewMS": firstMS, "firstMainActorLatenessMS": firstGap,
                "warmPreviewMS": warm, "warmMainActorLatenessMS": warmGap,
                "peakRSSMiB": Double(usage.ru_maxrss) / 1_048_576
            ]
            print(String(decoding: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), as: UTF8.self))
        }
    }

    @MainActor private static func waitForPreview(_ vm: ColorAdjustViewModel) async throws {
        let deadline = ContinuousClock.now + .seconds(30)
        while vm.isPreviewUpdating {
            guard ContinuousClock.now < deadline else { throw PDFwringerError.cannotCreateOutput }
            try await Task.sleep(for: .milliseconds(1))
        }
        guard vm.previewImage != nil else { throw PDFwringerError.cannotCreateOutput }
    }

    @MainActor private static func measureThumbnails(source: URL) async throws {
        for iteration in 1...3 {
            guard let document = PDFDocument(url: source), document.pageCount > 1, !document.isLocked else {
                throw PDFwringerError.cannotOpenDocument
            }
            let cache = ThumbnailCache()
            defer { cache.cancel() }
            let size = CGSize(width: 96, height: 128)
            let preferred = document.pageCount - 1
            let older = Array(0..<min(12, preferred))
            let heartbeat = Heartbeat()
            await heartbeat.start()
            let start = ContinuousClock.now
            for index in older { _ = cache.thumbnail(for: index, document: document, size: size) }
            _ = cache.thumbnail(for: preferred, document: document, size: size, priority: true)
            let deadline = ContinuousClock.now + .seconds(30)
            while cache.thumbnail(for: preferred, document: document, size: size, priority: true) == nil {
                guard ContinuousClock.now < deadline else { throw PDFwringerError.cannotCreateOutput }
                try await Task.sleep(for: .milliseconds(1))
            }
            let preferredMS = milliseconds(ContinuousClock.now - start)
            while cache.generation < older.count + 1 {
                guard ContinuousClock.now < deadline else { throw PDFwringerError.cannotCreateOutput }
                try await Task.sleep(for: .milliseconds(1))
            }
            let elapsed = milliseconds(ContinuousClock.now - start)
            let gap = await heartbeat.finish()
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            let record: [String: Any] = [
                "operation": "thumbnail-priority", "input": source.lastPathComponent,
                "iteration": iteration, "queuedOlderPages": older.count,
                "preferredPageMS": preferredMS, "allThumbnailsMS": elapsed,
                "maxMainActorLatenessMS": gap, "peakRSSMiB": Double(usage.ru_maxrss) / 1_048_576
            ]
            print(String(decoding: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), as: UTF8.self))
        }
    }

}
