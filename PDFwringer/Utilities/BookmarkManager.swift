import Foundation

/// Manages security-scoped bookmarks for recent documents.
/// In a sandboxed app, file URLs lose their access grant after restart.
/// Bookmarks persist the access right so "Open Recent" works across launches.
@MainActor
enum BookmarkManager {

    private static let bookmarksKey = "com.pdfwringer.recentBookmarks"
    private static let maxBookmarks = 10

    // MARK: - Save

    /// Save one intake batch, resolving existing entries only once.
    static func saveBookmarks(for urls: [URL]) {
        var bookmarks = loadBookmarkData().compactMap { entry -> (URL, BookmarkEntry)? in
            guard let resolved = resolveBookmark(entry.data) else { return nil }
            return (resolved.url.standardizedFileURL, entry)
        }
        for url in urls {
            guard let data = try? url.bookmarkData(options: .withSecurityScope,
                includingResourceValuesForKeys: nil, relativeTo: nil) else { continue }
            let standardized = url.standardizedFileURL
            bookmarks.removeAll { $0.0 == standardized }
            bookmarks.insert((standardized, BookmarkEntry(data: data)), at: 0)
            bookmarks = Array(bookmarks.prefix(maxBookmarks))
        }
        saveBookmarkData(bookmarks.map { $0.1 })
    }

    // MARK: - Resolve

    /// Resolution can involve unavailable volumes. Keep it off the interface
    /// thread and never overwrite a newer Open Recent change or Clear Menu.
    static func resolveBookmarksAsync() async -> [URL]? {
        let snapshot = UserDefaults.standard.data(forKey: bookmarksKey)
        let entries = loadBookmarkData()
        let worker = Task.detached(priority: .utility) { resolveEntries(entries) }
        let result = await withTaskCancellationHandler {
            await worker.value
        } onCancel: { worker.cancel() }
        guard !Task.isCancelled,
              UserDefaults.standard.data(forKey: bookmarksKey) == snapshot else { return nil }
        saveBookmarkData(result.entries)
        return result.urls
    }

    private nonisolated static func resolveEntries(_ bookmarks: [BookmarkEntry])
        -> (urls: [URL], entries: [BookmarkEntry]) {
        var resolved: [URL] = []
        var retained: [BookmarkEntry] = []

        for entry in bookmarks {
            if Task.isCancelled { break }
            guard let bookmark = resolveBookmark(entry.data) else { continue }
            var data = entry.data

            if bookmark.isStale {
                guard bookmark.url.startAccessingSecurityScopedResource() else { continue }
                defer { bookmark.url.stopAccessingSecurityScopedResource() }
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

        return (resolved, retained)
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

    private struct BookmarkEntry: Codable, Sendable {
        let data: Data
    }

    private nonisolated static func resolveBookmark(_ data: Data) -> (url: URL, isStale: Bool)? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI, .withoutMounting],
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
