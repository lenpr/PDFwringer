import Testing

@main struct TestRunner {
    static func main() async {
        AtomicFileWriter.cleanupLegacyTempFiles()
        await Testing.__swiftPMEntryPoint() as Never
    }
}
