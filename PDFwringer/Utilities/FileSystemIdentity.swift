import Darwin
import Foundation

/// Compares filesystem entries by identity instead of relying on path spelling.
/// This catches hard links, symbolic links, and case aliases on case-insensitive volumes.
enum FileSystemIdentity {
    struct Identity: Equatable {
        let device: UInt64
        let inode: UInt64
    }

    static func representsSameFile(_ first: URL, _ second: URL) -> Bool {
        let firstPath = first.standardizedFileURL
        let secondPath = second.standardizedFileURL
        if firstPath == secondPath { return true }

        let firstResolved = firstPath.resolvingSymlinksInPath()
        let secondResolved = secondPath.resolvingSymlinksInPath()
        if firstResolved == secondResolved { return true }

        guard let firstIdentity = targetIdentity(at: firstPath),
              let secondIdentity = targetIdentity(at: secondPath) else {
            return false
        }
        return firstIdentity == secondIdentity
    }

    static func requireDistinct(_ source: URL, _ destination: URL) throws {
        if representsSameFile(source, destination) {
            throw PDFwringerError.sourceEqualsDestination
        }
    }

    /// Identity of the object reached after following symbolic links.
    static func targetIdentity(at url: URL) -> Identity? {
        identity(at: url, followSymbolicLinks: true)
    }

    /// Identity of the directory entry itself, used to avoid deleting a replacement
    /// that another process installed while rolling back a published batch.
    static func entryIdentity(at url: URL) -> Identity? {
        identity(at: url, followSymbolicLinks: false)
    }

    private static func identity(at url: URL, followSymbolicLinks: Bool) -> Identity? {
        guard url.isFileURL else { return nil }
        return url.withUnsafeFileSystemRepresentation { path -> Identity? in
            guard let path else { return nil }
            var information = stat()
            let flags: Int32 = followSymbolicLinks ? 0 : AT_SYMLINK_NOFOLLOW
            let result = fstatat(AT_FDCWD, path, &information, flags)
            guard result == 0 else { return nil }
            return Identity(
                device: UInt64(information.st_dev),
                inode: UInt64(information.st_ino)
            )
        }
    }
}
