import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Durable file replace: write a sibling temp, `fsync`, then `rename` over the destination.
///
/// `FileManager.replaceItemAt` on swift-corelibs deletes the destination and then throws,
/// so a crash in that window removes the user's file. `rename(2)` in the same directory
/// swaps the directory entry in one step. The temp name is stable
/// (`.filename.partial`) so a killed process can be recognised on the next open.
public enum AtomicFileBytes {
    public static func partialURL(for url: URL) -> URL {
        let name = url.lastPathComponent
        return url.deletingLastPathComponent().appendingPathComponent(".\(name).partial", isDirectory: false)
    }

    /// Writes `data` to a temp file beside `url`, fsyncs it, then renames it over `url`.
    /// A failure before rename leaves `url` as it was. The temp file is removed on failure.
    public static func write(_ data: Data, to url: URL) throws {
        let partial = partialURL(for: url)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let fd = POSIXDurable.openWrite(partial.path)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        var open = true
        do {
            try writeAll(fd, data)
            if POSIXDurable.fsync(fd) != 0 { throw CocoaError(.fileWriteUnknown) }
            if POSIXDurable.close(fd) != 0 { throw CocoaError(.fileWriteUnknown) }
            open = false
            try commit(temporary: partial, replacing: url)
        } catch {
            if open { _ = POSIXDurable.close(fd) }
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
    }

    /// fsyncs `temporary`, then renames it onto `destination`. Does not delete `destination` first.
    public static func commit(temporary: URL, replacing destination: URL) throws {
        let fd = POSIXDurable.openRead(temporary.path)
        guard fd >= 0 else { throw CocoaError(.fileReadNoSuchFile) }
        let synced = POSIXDurable.fsync(fd)
        _ = POSIXDurable.close(fd)
        if synced != 0 { throw CocoaError(.fileWriteUnknown) }
        if POSIXDurable.rename(temporary.path, destination.path) != 0 {
            throw CocoaError(.fileWriteUnknown)
        }
        // The bytes are already durable. A directory fsync publishes the directory entry.
        // Some file systems reject fsync on a directory; the rename has already committed.
        let directory = destination.deletingLastPathComponent()
        let dir = POSIXDurable.openRead(directory.path)
        if dir >= 0 {
            _ = POSIXDurable.fsync(dir)
            _ = POSIXDurable.close(dir)
        }
    }

    private static func writeAll(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress, raw.count > 0 else { return }
            var written = 0
            while written < raw.count {
                let count = POSIXDurable.write(fd, base.advanced(by: written), raw.count - written)
                if count < 0 { throw CocoaError(.fileWriteUnknown) }
                written += count
            }
        }
    }
}

enum POSIXDurable {
    static func openRead(_ path: String) -> Int32 {
        #if canImport(Darwin)
        Darwin.open(path, O_RDONLY)
        #elseif canImport(Glibc)
        Glibc.open(path, O_RDONLY)
        #elseif canImport(Musl)
        Musl.open(path, O_RDONLY)
        #else
        -1
        #endif
    }

    static func openWrite(_ path: String) -> Int32 {
        #if canImport(Darwin)
        Darwin.open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        #elseif canImport(Glibc)
        Glibc.open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        #elseif canImport(Musl)
        Musl.open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        #else
        -1
        #endif
    }

    static func write(_ fd: Int32, _ buffer: UnsafeRawPointer, _ count: Int) -> Int {
        #if canImport(Darwin)
        Darwin.write(fd, buffer, count)
        #elseif canImport(Glibc)
        Glibc.write(fd, buffer, count)
        #elseif canImport(Musl)
        Musl.write(fd, buffer, count)
        #else
        -1
        #endif
    }

    static func close(_ fd: Int32) -> Int32 {
        #if canImport(Darwin)
        Darwin.close(fd)
        #elseif canImport(Glibc)
        Glibc.close(fd)
        #elseif canImport(Musl)
        Musl.close(fd)
        #else
        -1
        #endif
    }

    static func fsync(_ fd: Int32) -> Int32 {
        #if canImport(Darwin)
        durableSync(fd, Darwin.fsync)
        #elseif canImport(Glibc)
        durableSync(fd, Glibc.fsync)
        #elseif canImport(Musl)
        durableSync(fd, Musl.fsync)
        #else
        -1
        #endif
    }

    #if canImport(Darwin) || canImport(Glibc) || canImport(Musl)
    private static func durableSync(_ fd: Int32, _ sync: (Int32) -> Int32) -> Int32 {
        while true {
            let result = sync(fd)
            if result == 0 { return 0 }
            if errno != EINTR { return result }
        }
    }
    #endif

    static func rename(_ from: String, _ to: String) -> Int32 {
        #if canImport(Darwin)
        Darwin.rename(from, to)
        #elseif canImport(Glibc)
        Glibc.rename(from, to)
        #elseif canImport(Musl)
        Musl.rename(from, to)
        #else
        -1
        #endif
    }
}
