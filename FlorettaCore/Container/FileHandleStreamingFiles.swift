import Foundation

/// Streaming file adapter for the CLI and for tests.
/// Reads and writes go through `FileHandle` in caller-sized chunks.
/// The app keeps its own Darwin adapter; this one does not replace that type.
public struct FileHandleStreamingFiles: StreamingFilePort, FileAccessPort {
    public init() {}

    public func read(from url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func write(_ data: Data, to url: URL) throws {
        try AtomicFileBytes.write(data, to: url)
    }

    public func byteCount(at url: URL) throws -> Int64 {
        let reader = try HandleReader(url: url)
        defer { try? reader.close() }
        return reader.count
    }

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func isZip(at url: URL) throws -> Bool {
        let reader = try HandleReader(url: url)
        defer { try? reader.close() }
        guard reader.count >= 2 else { return false }
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: 2, alignment: 1)
        defer { pointer.deallocate() }
        let buffer = UnsafeMutableRawBufferPointer(start: pointer, count: 2)
        let count = try reader.read(at: 0, into: buffer)
        return count == 2 && buffer[0] == 0x50 && buffer[1] == 0x4B
    }

    public func openReader(at url: URL) throws -> RandomAccessReader {
        try HandleReader(url: url)
    }

    public func openWriter(at url: URL) throws -> SequentialByteWriter {
        try HandleWriter(url: url)
    }

    public func makeTemporary(nextTo url: URL) throws -> URL {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return AtomicFileBytes.partialURL(for: url)
    }

    public func replace(destination: URL, with temporary: URL) throws {
        try AtomicFileBytes.commit(temporary: temporary, replacing: destination)
    }

    public func remove(at url: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}

private final class HandleReader: RandomAccessReader {
    let count: Int64
    private let handle: FileHandle
    private var closed = false

    init(url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        let end = try handle.seekToEnd()
        count = end > UInt64(Int64.max) ? Int64.max : Int64(end)
    }

    func read(at offset: Int64, into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        guard offset >= 0 else { throw CocoaError(.fileReadUnknown) }
        guard let base = buffer.baseAddress, buffer.count > 0 else { return 0 }
        try handle.seek(toOffset: UInt64(offset))
        guard let data = try handle.read(upToCount: buffer.count), !data.isEmpty else { return 0 }
        data.withUnsafeBytes { raw in
            guard let source = raw.baseAddress else { return }
            let destination = UnsafeMutableRawBufferPointer(rebasing: buffer.prefix(data.count))
            destination.copyMemory(from: UnsafeRawBufferPointer(start: source, count: data.count))
        }
        return data.count
    }

    func close() throws {
        guard !closed else { return }
        closed = true
        try handle.close()
    }

    deinit {
        if !closed { try? handle.close() }
    }
}

private final class HandleWriter: SequentialByteWriter {
    private let handle: FileHandle
    private var closed = false

    init(url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
    }

    func write(_ buffer: UnsafeRawBufferPointer) throws {
        guard buffer.count > 0 else { return }
        try handle.write(contentsOf: Data(bytes: buffer))
    }

    func synchronize() throws {
        try handle.synchronize()
    }

    func close() throws {
        guard !closed else { return }
        closed = true
        try handle.close()
    }

    deinit {
        if !closed { try? handle.close() }
    }
}
