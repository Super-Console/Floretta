import Foundation
import FlorettaCore
#if os(macOS)
import AppKit
#endif

struct RecentMapEntry: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var filename: String
    var modifiedAt: Date
    var bookmark: Data
}

/// Recent files stored as security-scoped bookmarks in UserDefaults.
/// Loading the list decodes that array. It does not enumerate the disk.
@MainActor
struct RecentMapsStore {
    var defaults: UserDefaults
    var key: String

    init(defaults: UserDefaults, key: String = "floretta.recentMaps") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [RecentMapEntry] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([RecentMapEntry].self, from: data)) ?? []
    }

    mutating func remember(_ url: URL, clock: any ClockPort) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        let bookmark = try Self.bookmarkData(for: url)
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? clock.now()
        let path = url.standardizedFileURL.path
        var entries = load()
        entries.removeAll { entry in
            guard let resolved = resolve(entry.bookmark) else { return false }
            return resolved.standardizedFileURL.path == path
        }
        entries.insert(
            RecentMapEntry(
                id: UUID().uuidString,
                filename: url.lastPathComponent,
                modifiedAt: modified,
                bookmark: bookmark
            ),
            at: 0
        )
        if entries.count > 40 {
            entries = Array(entries.prefix(40))
        }
        try save(entries)
        #if os(macOS)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        #endif
    }

    mutating func remove(id: String) {
        var entries = load()
        entries.removeAll { $0.id == id }
        try? save(entries)
    }

    func resolve(_ entry: RecentMapEntry) -> URL? {
        resolve(entry.bookmark)
    }

    func resolve(_ data: Data) -> URL? {
        var stale = false
        #if os(macOS)
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) {
            return url
        }
        #endif
        stale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }

    private func save(_ entries: [RecentMapEntry]) throws {
        let data = try JSONEncoder().encode(entries)
        defaults.set(data, forKey: key)
    }

    private static func bookmarkData(for url: URL) throws -> Data {
        #if os(macOS)
        if let data = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: [.contentModificationDateKey],
            relativeTo: nil
        ) {
            return data
        }
        #endif
        return try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: [.contentModificationDateKey],
            relativeTo: nil
        )
    }
}
