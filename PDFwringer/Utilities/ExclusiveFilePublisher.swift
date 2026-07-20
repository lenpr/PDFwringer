import Darwin
import Foundation
import OSLog

/// Publishes a staged batch without replacing existing filesystem entries.
/// If any publication fails or the task is cancelled, files already published
/// by this batch are removed when their filesystem identity is unchanged.
enum ExclusiveFilePublisher {
    struct StagedFile {
        let url: URL
        let baseStem: String
        let generatedSuffix: String
        let pathExtension: String
    }

    static func publish(_ stagedFiles: [StagedFile], to outputDirectory: URL) throws -> [URL] {
        let fileManager = FileManager.default
        var outputDirectoryIsDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: outputDirectory.path(percentEncoded: false),
            isDirectory: &outputDirectoryIsDirectory
        ), outputDirectoryIsDirectory.boolValue else {
            throw PDFwringerError.cannotWriteOutput
        }

        let resolvedOutputDirectory = outputDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let componentNameLimit = nameLimit(in: outputDirectory)
        var publishedOutputs: [PublishedOutput] = []
        publishedOutputs.reserveCapacity(stagedFiles.count)

        do {
            for stagedFile in stagedFiles {
                try Task.checkCancellation()
                guard let identity = FileSystemIdentity.entryIdentity(at: stagedFile.url) else {
                    throw PDFwringerError.cannotWriteOutput
                }
                let outputURL = try publish(
                    stagedFile,
                    to: outputDirectory,
                    resolvedOutputDirectory: resolvedOutputDirectory,
                    componentNameLimit: componentNameLimit
                )
                publishedOutputs.append(PublishedOutput(url: outputURL, identity: identity))
            }
            return publishedOutputs.map(\.url)
        } catch {
            rollback(publishedOutputs)
            throw error
        }
    }

    private static func publish(
        _ stagedFile: StagedFile,
        to outputDirectory: URL,
        resolvedOutputDirectory: URL,
        componentNameLimit: Int
    ) throws -> URL {
        var suffix = 0

        while true {
            let collisionSuffix = suffix == 0 ? "" : "_\(suffix)"
            let extensionSuffix = stagedFile.pathExtension.isEmpty
                ? ""
                : ".\(stagedFile.pathExtension)"
            let candidate = try fittedCandidate(
                outputDirectory: outputDirectory,
                baseStem: stagedFile.baseStem,
                protectedSuffix: stagedFile.generatedSuffix + collisionSuffix + extensionSuffix,
                componentNameLimit: componentNameLimit
            )
            let resolvedParent = candidate.deletingLastPathComponent()
                .standardizedFileURL
                .resolvingSymlinksInPath()
            guard resolvedParent == resolvedOutputDirectory else {
                throw PDFwringerError.accessDenied
            }

            if try renameExclusively(from: stagedFile.url, to: candidate) {
                return candidate
            }
            guard suffix < Int.max else { throw PDFwringerError.cannotWriteOutput }
            suffix += 1
        }
    }

    /// Preserve generated page/chunk and collision suffixes while shortening only
    /// the caller-derived source stem at a Character boundary.
    private static func fittedCandidate(
        outputDirectory: URL,
        baseStem: String,
        protectedSuffix: String,
        componentNameLimit: Int
    ) throws -> URL {
        var fittedBase = baseStem
        while true {
            let candidate = outputDirectory.appending(component: fittedBase + protectedSuffix)
            if try fileSystemComponentLength(of: candidate) <= componentNameLimit {
                return candidate
            }
            guard !fittedBase.isEmpty else {
                throw PDFwringerError.cannotWriteOutput
            }
            fittedBase.removeLast()
        }
    }

    private static func nameLimit(in directory: URL) -> Int {
        let limit = directory.withUnsafeFileSystemRepresentation { path -> Int in
            guard let path else { return -1 }
            return Int(pathconf(path, _PC_NAME_MAX))
        }
        return limit > 0 ? limit : 255
    }

    private static func fileSystemComponentLength(of url: URL) throws -> Int {
        try url.withUnsafeFileSystemRepresentation { path -> Int in
            guard let path else { throw PDFwringerError.cannotWriteOutput }
            var componentStart = path
            var cursor = path
            while cursor.pointee != 0 {
                if cursor.pointee == 47 {
                    componentStart = cursor.advanced(by: 1)
                }
                cursor = cursor.advanced(by: 1)
            }
            return Int(strlen(componentStart))
        }
    }

    /// `FileManager.moveItem` may overwrite in a check-then-move race. Darwin's
    /// exclusive rename makes the no-clobber guarantee a single filesystem step.
    private static func renameExclusively(from source: URL, to destination: URL) throws -> Bool {
        let result: Int32 = try source.withUnsafeFileSystemRepresentation { sourcePath in
            guard let sourcePath else { throw PDFwringerError.cannotWriteOutput }
            return try destination.withUnsafeFileSystemRepresentation { destinationPath in
                guard let destinationPath else { throw PDFwringerError.cannotWriteOutput }
                return renameatx_np(
                    AT_FDCWD,
                    sourcePath,
                    AT_FDCWD,
                    destinationPath,
                    UInt32(RENAME_EXCL)
                )
            }
        }

        if result == 0 { return true }
        let errorCode = errno
        if errorCode == EEXIST { return false }
        Log.fileIO.error("Exclusive output rename failed with errno \(errorCode)")
        throw PDFwringerError.cannotWriteOutput
    }

    private struct PublishedOutput {
        let url: URL
        let identity: FileSystemIdentity.Identity
    }

    private static func rollback(_ outputs: [PublishedOutput]) {
        for output in outputs.reversed() {
            guard FileSystemIdentity.entryIdentity(at: output.url) == output.identity else {
                Log.fileIO.error(
                    "Skipped rollback of changed output: \(output.url.lastPathComponent, privacy: .private)"
                )
                continue
            }
            do {
                try FileManager.default.removeItem(at: output.url)
            } catch {
                Log.fileIO.error(
                    "Failed to roll back output: \(output.url.lastPathComponent, privacy: .private)"
                )
            }
        }
    }
}
