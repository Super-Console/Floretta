import CoreGraphics
import FlorettaCore
import Foundation
import ImageIO
import XCTest

@MainActor
final class QuickLookThumbnailTests: XCTestCase {
    func testPixelEdgeCapsFinderRequests() {
        XCTAssertEqual(
            FlorettaQuickLookRenderer.pixelEdge(points: CGSize(width: 256, height: 128), scale: 2),
            512
        )
        XCTAssertEqual(
            FlorettaQuickLookRenderer.pixelEdge(points: CGSize(width: 2000, height: 2000), scale: 2),
            FlorettaQuickLookRenderer.maximumPixelEdge
        )
        XCTAssertEqual(
            FlorettaQuickLookRenderer.pixelEdge(points: CGSize(width: 1, height: 1), scale: 1),
            16
        )
        XCTAssertEqual(
            FlorettaQuickLookRenderer.stagedAttachmentByteCeiling,
            Int64(StreamingBudget.writePeakBytes)
        )
    }

    func testFallbackCaptionUsesTheStringCatalog() {
        let english = Locale(identifier: "en")
        let chinese = Locale(identifier: "zh-Hans")
        XCTAssertEqual(
            FlorettaL10n.string(FlorettaQuickLookRenderer.fallbackKey, locale: english),
            "Couldn't make a thumbnail."
        )
        XCTAssertEqual(
            FlorettaL10n.string(FlorettaQuickLookRenderer.fallbackKey, locale: chinese),
            "无法生成缩略图。"
        )
    }

    func testZipThumbnailFitsTheMapAndDoesNotReadSkippedAttachments() throws {
        let root = MindMapNode(text: "根")
        let far = MindMapNode(text: "远", position: MindMapPoint(x: 4000, y: 80))
        let png = tinyPNG()
        let blob = Data(repeating: 0xAB, count: 4096)
        let rooted = MindMapDocument(
            title: "缩略图",
            roots: [MindMapNode(
                id: root.id,
                text: "根",
                attachments: [
                    NodeAttachment(
                        sha256: sha256Hex(png),
                        fileExtension: "png",
                        byteCount: Int64(png.count),
                        filename: "dot.png"
                    ),
                    NodeAttachment(
                        sha256: sha256Hex(blob),
                        fileExtension: "dmg",
                        byteCount: Int64(blob.count),
                        filename: "disk.dmg"
                    ),
                ]
            )],
            freeNodes: [far]
        )
        let url = try writeZip(document: rooted, assets: [(png, "png"), (blob, "dmg")])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let ranges = try payloadRanges(at: url)
        let files = WatchingFiles(archive: url)
        let picture = FlorettaQuickLookRenderer.picture(
            at: url,
            longestPixelEdge: 128,
            files: files,
            locale: Locale(identifier: "en"),
            stagedAttachmentByteCeiling: 10
        )
        XCTAssertNil(picture.caption)
        XCTAssertFalse(picture.truncated)
        XCTAssertTrue(picture.visibleNodeIDs.contains(root.id))
        XCTAssertTrue(picture.visibleNodeIDs.contains(far.id))
        let longestPixel = max(picture.pixelSize.width, picture.pixelSize.height)
        let longestPoint = max(picture.pointSize.width, picture.pointSize.height)
        XCTAssertLessThanOrEqual(longestPixel, 129)
        XCTAssertGreaterThan(longestPoint, longestPixel)
        try assertColored(picture.png)
        XCTAssertFalse(files.flag.touched(ranges.png))
        XCTAssertFalse(files.flag.touched(ranges.dmg))
        let preview = FlorettaQuickLookRenderer.preview(from: picture)
        XCTAssertEqual(preview.data, picture.png)
        XCTAssertEqual(preview.contentSize, picture.pixelSize)
        XCTAssertEqual(preview.contentTypeIdentifier, "public.png")
        let written = try FlorettaQuickLookRenderer.writePNG(picture, in: url.deletingLastPathComponent())
        XCTAssertEqual(try Data(contentsOf: written).prefix(8), Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
    }

    func testSmallImageThumbnailReadsTheAssetAndSkipsTheOtherFile() throws {
        let png = tinyPNG()
        let blob = Data(repeating: 0xCD, count: 2048)
        let root = MindMapNode(
            text: "图",
            attachments: [
                NodeAttachment(
                    sha256: sha256Hex(png),
                    fileExtension: "png",
                    byteCount: Int64(png.count),
                    filename: "dot.png"
                ),
                NodeAttachment(
                    sha256: sha256Hex(blob),
                    fileExtension: "dmg",
                    byteCount: Int64(blob.count),
                    filename: "disk.dmg"
                ),
            ]
        )
        let document = MindMapDocument(title: "图", roots: [root])
        let url = try writeZip(document: document, assets: [(png, "png"), (blob, "dmg")])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let ranges = try payloadRanges(at: url)
        let files = WatchingFiles(archive: url)
        let picture = FlorettaQuickLookRenderer.picture(at: url, longestPixelEdge: 256, files: files)
        XCTAssertNil(picture.caption)
        XCTAssertTrue(picture.visibleNodeIDs.contains(root.id))
        try assertColored(picture.png)
        XCTAssertTrue(files.flag.touched(ranges.png))
        XCTAssertFalse(files.flag.touched(ranges.dmg))
    }

    func testLegacyJSONUsesTheSamePicture() throws {
        let root = MindMapNode(text: "旧稿")
        let document = MindMapDocument(title: "旧", roots: [root])
        let directory = temporaryDirectory()
        let url = directory.appendingPathComponent("legacy.floretta")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FlorettaCodec.encode(document).write(to: url)
        let picture = FlorettaQuickLookRenderer.picture(at: url, longestPixelEdge: 256)
        XCTAssertNil(picture.caption)
        XCTAssertFalse(picture.truncated)
        XCTAssertTrue(picture.visibleNodeIDs.contains(root.id))
        try assertColored(picture.png)
    }

    func testUnreadableFileDrawsTheLocalizedFallback() throws {
        let directory = temporaryDirectory()
        let url = directory.appendingPathComponent("broken.floretta")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not a map".utf8).write(to: url)
        let picture = FlorettaQuickLookRenderer.picture(
            at: url,
            longestPixelEdge: 64,
            locale: Locale(identifier: "en")
        )
        XCTAssertEqual(picture.caption, "Couldn't make a thumbnail.")
        XCTAssertTrue(picture.visibleNodeIDs.isEmpty)
        XCTAssertFalse(picture.png.isEmpty)
        XCTAssertLessThanOrEqual(max(picture.pixelSize.width, picture.pixelSize.height), 64)
        let chinese = FlorettaQuickLookRenderer.picture(
            at: url,
            longestPixelEdge: 64,
            locale: Locale(identifier: "zh-Hans")
        )
        XCTAssertEqual(chinese.caption, "无法生成缩略图。")
    }

    private func writeZip(document: MindMapDocument, assets: [(Data, String)]) throws -> URL {
        var package = FlorettaPackage(document: document)
        for asset in assets {
            package.addAsset(data: asset.0, fileExtension: asset.1)
        }
        let directory = temporaryDirectory()
        let url = directory.appendingPathComponent("map.floretta")
        try ZipContainer().write(package).write(to: url)
        return url
    }

    private func payloadRanges(at url: URL) throws -> (png: Range<Int64>, dmg: Range<Int64>) {
        let files = FoundationStreamingFiles()
        let reader = try files.openReader(at: url)
        defer { try? reader.close() }
        let opened = try FlorettaStreamingDocument.open(reader)
        func range(_ suffix: String) throws -> Range<Int64> {
            let entry = try XCTUnwrap(opened.directory.attachments.first { $0.name.hasSuffix(suffix) })
            let start = Int64(entry.dataOffset)
            return start..<(start + Int64(entry.byteCount))
        }
        return (try range(".png"), try range(".dmg"))
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("floretta-ql-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func tinyPNG() -> Data {
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        return Data(base64Encoded: base64) ?? Data()
    }

    private func assertColored(_ data: Data) throws {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let width = image.width
        let height = image.height
        XCTAssertGreaterThan(width, 1)
        XCTAssertGreaterThan(height, 1)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let colored = stride(from: 0, to: pixels.count, by: 4).contains { index in
            let red = Int(pixels[index])
            let green = Int(pixels[index + 1])
            let blue = Int(pixels[index + 2])
            let alpha = Int(pixels[index + 3])
            return alpha > 200 && abs(red - 255) + abs(green - 255) + abs(blue - 255) > 40
        }
        XCTAssertTrue(colored)
    }
}

private final class QuickLookTouchFlag: @unchecked Sendable {
    var ranges: [Range<Int64>] = []

    func touched(_ forbidden: Range<Int64>) -> Bool {
        ranges.contains { $0.overlaps(forbidden) }
    }
}

private final class WatchingReader: RandomAccessReader {
    let inner: RandomAccessReader
    let flag: QuickLookTouchFlag
    var count: Int64 { inner.count }

    init(inner: RandomAccessReader, flag: QuickLookTouchFlag) {
        self.inner = inner
        self.flag = flag
    }

    func read(at offset: Int64, into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        let count = try inner.read(at: offset, into: buffer)
        if count > 0 {
            flag.ranges.append(offset..<(offset + Int64(count)))
        }
        return count
    }

    func close() throws { try inner.close() }
}

private final class WatchingFiles: StreamingFilePort {
    let inner = FoundationStreamingFiles()
    let archive: URL
    let flag = QuickLookTouchFlag()

    init(archive: URL) {
        self.archive = archive
    }

    func byteCount(at url: URL) throws -> Int64 { try inner.byteCount(at: url) }
    func fileExists(at url: URL) -> Bool { inner.fileExists(at: url) }
    func isZip(at url: URL) throws -> Bool { try inner.isZip(at: url) }

    func openReader(at url: URL) throws -> RandomAccessReader {
        let reader = try inner.openReader(at: url)
        guard url.standardizedFileURL == archive.standardizedFileURL else { return reader }
        return WatchingReader(inner: reader, flag: flag)
    }

    func openWriter(at url: URL) throws -> SequentialByteWriter { try inner.openWriter(at: url) }
    func makeTemporary(nextTo url: URL) throws -> URL { try inner.makeTemporary(nextTo: url) }
    func replace(destination: URL, with temporary: URL) throws { try inner.replace(destination: destination, with: temporary) }
    func remove(at url: URL) throws { try inner.remove(at: url) }
}
