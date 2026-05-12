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

        // Remove existing entry for same path (avoid duplicates)
        let standardized = url.standardizedFileURL.path(percentEncoded: false)
        bookmarks.removeAll { entry in
            entry.path == standardized
        }

        // Add new entry at the front
        bookmarks.insert(BookmarkEntry(path: standardized, data: data), at: 0)

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

        for entry in bookmarks {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: entry.data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { continue }

            if isStale {
                // Bookmark is stale — try to recreate it
                if url.startAccessingSecurityScopedResource() {
                    saveBookmark(for: url)
                    url.stopAccessingSecurityScopedResource()
                }
            }

            resolved.append(url)
        }

        return resolved
    }

    /// Resolves a single bookmark URL and starts security-scoped access.
    /// Caller must call `url.stopAccessingSecurityScopedResource()` when done.
    static func accessURL(from resolvedURL: URL) -> Bool {
        resolvedURL.startAccessingSecurityScopedResource()
    }

    // MARK: - Clear

    /// Removes all saved bookmarks.
    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: bookmarksKey)
    }

    // MARK: - Storage

    private struct BookmarkEntry: Codable {
        let path: String
        let data: Data
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
