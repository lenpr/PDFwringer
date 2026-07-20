import Darwin
import Foundation
import OSLog

/// Publishes a staged batch without replacing existing filesystem entries.
/// If any publication fails or the task is cancelled, files already published
/// by this batch are removed when their filesystem identity is unchanged.
enum ExclusiveFilePublisher {
    struct StagedFile {
        let url: URL
        let preferredStem: String
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
        var publishedOutputs: [PublishedOutput] = []
        publishedOutputs.reserveCapacity(stagedFiles.count)

        do {
            for stagedFile in stagedFiles {
                try Task.checkCancellation()
                guard let identity = fileIdentity(at: stagedFile.url) else {
                    throw PDFwringerError.cannotWriteOutput
                }
                let outputURL = try publish(
                    stagedFile,
                    to: outputDirectory,
                    resolvedOutputDirectory: resolvedOutputDirectory
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
        resolvedOutputDirectory: URL
    ) throws -> URL {
        var suffix = 0

        while true {
            let stem = suffix == 0
                ? stagedFile.preferredStem
                : "\(stagedFile.preferredStem)_\(suffix)"
            let candidate = outputDirectory
                .appending(component: stem)
                .appendingPathExtension(stagedFile.pathExtension)
            let resolvedParent = candidate.deletingLastPathComponent()
                .standardizedFileURL
                .resolvingSymlinksInPath()
            guard resolvedParent == resolvedOutputDirectory else {
                throw PDFwringerError.accessDenied
            }

            if try renameExclusively(from: stagedFile.url, to: candidate) {
                return candidate
            }
            suffix += 1
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

    private struct FileIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
    }

    private struct PublishedOutput {
        let url: URL
        let identity: FileIdentity
    }

    private static func fileIdentity(at url: URL) -> FileIdentity? {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return nil }
            var information = stat()
            guard lstat(path, &information) == 0 else { return nil }
            return FileIdentity(
                device: UInt64(information.st_dev),
                inode: UInt64(information.st_ino)
            )
        }
    }

    private static func rollback(_ outputs: [PublishedOutput]) {
        for output in outputs.reversed() {
            guard fileIdentity(at: output.url) == output.identity else {
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
