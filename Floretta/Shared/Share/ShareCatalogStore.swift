import FlorettaCore
import Foundation

/// Recent `.floretta` files the share extension can open.
/// The list lives in the app group. Without the group, publishing does nothing
/// and the extension asks the user to pick a file.
enum ShareCatalogStore {
    static let appGroupID = "group.net.timhuang.floretta"

    static func publish(url: URL, document: MindMapDocument) {
        guard let destination = catalogURL() else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        guard let bookmark = try? bookmarkData(for: url) else { return }
        let entry = ShareDocumentEntry(
            id: url.standardizedFileURL.path,
            filename: url.lastPathComponent,
            bookmark: bookmark,
            topicCount: ShareIngress.topics(in: document).count
        )
        let catalog = load().upsert(entry)
        write(catalog, to: destination)
    }

    static func load() -> ShareDocumentCatalog {
        guard let url = catalogURL(), let data = try? Data(contentsOf: url) else {
            return ShareDocumentCatalog()
        }
        return (try? JSONDecoder().decode(ShareDocumentCatalog.self, from: data)) ?? ShareDocumentCatalog()
    }

    static func resolve(_ entry: ShareDocumentEntry) -> URL? {
        var stale = false
        #if os(macOS)
        if let url = try? URL(
            resolvingBookmarkData: entry.bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) {
            return url
        }
        #endif
        stale = false
        return try? URL(
            resolvingBookmarkData: entry.bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }

    private static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    private static func catalogURL() -> URL? {
        containerURL()?.appendingPathComponent("share-catalog.json", isDirectory: false)
    }

    private static func write(_ catalog: ShareDocumentCatalog, to url: URL) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(catalog) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func bookmarkData(for url: URL) throws -> Data {
        #if os(macOS)
        if let data = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            return data
        }
        #endif
        return try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
}
