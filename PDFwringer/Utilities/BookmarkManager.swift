import Foundation

/// Manages security-scoped bookmarks for recent documents.
/// In a sandboxed app, file URLs lose their access grant after restart.
/// Bookmarks persist the access right so "Open Recent" works across launches.
@MainActor
enum BookmarkManager {

    private static let bookmarksKey = "com.pdfwringer.recentBookmarks"
    private static let maxBookmarks = 10

    // MARK: - Save

    /// Saves a security-scoped bookmark for the given URL.
    /// Call this when a user opens/selects a file.
    static func saveBookmark(for url: URL) {
        var bookmarks = loadBookmarkData()

        guard let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }

        // Resolve only for de-duplication; do not persist plaintext file paths.
        let standardized = url.standardizedFileURL.path(percentEncoded: false)
        bookmarks.removeAll { entry in
            guard let resolved = resolveBookmark(entry.data) else { return true }
            return resolved.url.standardizedFileURL.path(percentEncoded: false) == standardized
        }

        // Add new entry at the front
        bookmarks.insert(BookmarkEntry(data: data), at: 0)

        // Trim to max
        if bookmarks.count > maxBookmarks {
            bookmarks = Array(bookmarks.prefix(maxBookmarks))
        }

        saveBookmarkData(bookmarks)
    }

    // MARK: - Resolve

    /// Resolves all saved bookmarks into accessible URLs.
    /// Returns only URLs that are still valid and accessible.
    static func resolveBookmarks() -> [URL] {
        let bookmarks = loadBookmarkData()
        var resolved: [URL] = []
        var retained: [BookmarkEntry] = []

        for entry in bookmarks {
            guard let bookmark = resolveBookmark(entry.data) else { continue }
            var data = entry.data

            if bookmark.isStale {
                guard startAccessing(bookmark.url) else { continue }
                defer { stopAccessing(bookmark.url) }
                guard let refreshed = try? bookmark.url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) else { continue }
                data = refreshed
            }

            resolved.append(bookmark.url)
            retained.append(BookmarkEntry(data: data))
        }

        // Always rewrite so installations with the legacy plaintext `path`
        // field are migrated even when every bookmark is otherwise unchanged.
        saveBookmarkData(retained)

        return resolved
    }

    /// Starts access to a resolved bookmark URL. Every successful call must be
    /// balanced by exactly one `stopAccessing` call.
    static func startAccessing(_ resolvedURL: URL) -> Bool {
        resolvedURL.startAccessingSecurityScopedResource()
    }

    static func stopAccessing(_ resolvedURL: URL) {
        resolvedURL.stopAccessingSecurityScopedResource()
    }

    // MARK: - Clear

    /// Removes all saved bookmarks.
    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: bookmarksKey)
    }

    // MARK: - Storage

    private struct BookmarkEntry: Codable {
        let data: Data
    }

    private static func resolveBookmark(_ data: Data) -> (url: URL, isStale: Bool)? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        return (url, isStale)
    }

    private static func loadBookmarkData() -> [BookmarkEntry] {
        guard let data = UserDefaults.standard.data(forKey: bookmarksKey),
              let entries = try? JSONDecoder().decode([BookmarkEntry].self, from: data)
        else { return [] }
        return entries
    }

    private static func saveBookmarkData(_ entries: [BookmarkEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: bookmarksKey)
    }
}
