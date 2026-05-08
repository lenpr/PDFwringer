import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

@MainActor
struct PDFColorAdjuster {

    struct Settings: Equatable, Hashable {
        var brightness: Float = 0
        var contrast: Float = 1
        var saturation: Float = 1

        var isIdentity: Bool {
            brightness == 0 && contrast == 1 && saturation == 1
        }
    }

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    nonisolated static func adjustImage(_ image: CGImage, settings: Settings) -> CGImage? {
        guard !settings.isIdentity else { return image }

        let ciImage = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(settings.brightness, forKey: kCIInputBrightnessKey)
        filter.setValue(settings.contrast, forKey: kCIInputContrastKey)
        filter.setValue(settings.saturation, forKey: kCIInputSaturationKey)

        guard let output = filter.outputImage else { return image }

        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgResult = ctx.createCGImage(output, from: output.extent) else { return image }
        return cgResult
    }

    func adjust(
        source: URL,
        destination: URL,
        settings: Settings,
        pages: [Int]?,
        dpi: CGFloat = 150,
        quality: CGFloat = 0.85,
        progress: (Double) -> Void
    ) async throws {
        guard !settings.isIdentity else {
            try FileManager.default.copyItem(at: source, to: destination)
            progress(1.0)
            return
        }

        guard let doc = PDFCompressor.openPDF(at: source) else {
            throw PDFwringerError.cannotOpenDocument
        }

        let pageCount = doc.numberOfPages
        guard pageCount > 0 else { throw PDFwringerError.cannotOpenDocument }

        let targetPages: Set<Int>
        if let pages {
            targetPages = Set(pages.map { $0 + 1 })
        } else {
            targetPages = Set(1...pageCount)
        }

        let tempURL = URL.temporaryDirectory.appending(component: UUID().uuidString + ".pdf")

        var emptyBox = CGRect.zero
        guard let outputCtx = CGContext(tempURL as CFURL, mediaBox: &emptyBox, nil) else {
            throw PDFwringerError.cannotCreateOutput
        }

        do {
            for i in 1...pageCount {
                try Task.checkCancellation()

                autoreleasepool {
                    guard let page = doc.page(at: i) else { return }
                    guard let (rendered, displaySize) = PDFCompressor.renderPage(page, dpi: dpi, grayscale: false) else { return }

                    let finalImage: CGImage
                    if targetPages.contains(i) {
                        finalImage = Self.adjustImage(rendered, settings: settings) ?? rendered
                    } else {
                        finalImage = rendered
                    }

                    guard let jpegData = PDFCompressor.jpegEncode(image: finalImage, quality: quality) else { return }

                    guard let provider = CGDataProvider(data: jpegData as CFData),
                          let jpegImage = CGImage(
                              jpegDataProviderSource: provider,
                              decode: nil,
                              shouldInterpolate: true,
                              intent: .defaultIntent
                          )
                    else { return }

                    var outBox = CGRect(origin: .zero, size: displaySize)
                    outputCtx.beginPage(mediaBox: &outBox)
                    outputCtx.draw(jpegImage, in: outBox)
                    outputCtx.endPage()
                }

                progress(Double(i) / Double(pageCount))
                await Task.yield()
            }

            outputCtx.closePDF()

            try AtomicFileWriter.write(to: destination) { tempDest in
                try FileManager.default.moveItem(at: tempURL, to: tempDest)
                return true
            }
        } catch {
            outputCtx.closePDF()
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }
}
