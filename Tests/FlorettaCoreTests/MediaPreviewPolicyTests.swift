import FlorettaCore
import XCTest

final class MediaPreviewPolicyTests: XCTestCase {
    func testDurationFormattingAndInvalidValues() {
        XCTAssertEqual(MediaPreviewPolicy.durationLabel(seconds: 0), "0:00")
        XCTAssertEqual(MediaPreviewPolicy.durationLabel(seconds: 125.9), "2:05")
        XCTAssertEqual(MediaPreviewPolicy.durationLabel(seconds: .infinity), "--:--")
        XCTAssertEqual(MediaPreviewPolicy.durationLabel(seconds: nil), "--:--")
    }

    func testWaveformSampleCountIsBounded() {
        let output = MediaPreviewPolicy.boundedSamples((0..<20_000).map { Float($0 % 100) / 100 })
        XCTAssertEqual(output.count, MediaPreviewPolicy.maximumWaveformSamples)
        XCTAssertTrue(output.allSatisfy { $0 >= 0 && $0 <= 1 })
        XCTAssertEqual(MediaPreviewPolicy.boundedSamples([0.2, 0.4], limit: 4).count, 2)
    }

    func testMediaLoaderCacheHitEvictionAndMissingFileFallback() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = ThumbnailFileCache(directory: directory.appendingPathComponent("cache"), maxBytes: 5)
        let first = String(repeating: "a", count: 64)
        let second = String(repeating: "b", count: 64)
        let source = directory.appendingPathComponent("audio.m4a")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("source".utf8).write(to: source)
        let fake = FakeMediaPreviewGenerator()
        let loader = MediaPreviewLoader(cache: cache, generator: fake)

        let generated = await loader.load(file: source, key: first, kind: .audio)
        XCTAssertEqual(generated?.imageData, Data([1, 2, 3]))
        _ = await loader.load(file: source, key: first, kind: .audio)
        let generationCalls = await fake.calls
        XCTAssertEqual(generationCalls, 1)
        try cache.store(Data(repeating: 4, count: 4), for: second)
        XCTAssertFalse(cache.contains(first))
        XCTAssertTrue(cache.contains(second))

        let missing = directory.appendingPathComponent("missing.m4a")
        let missingResult = await loader.load(file: missing, key: second, kind: .audio)
        XCTAssertNil(missingResult)
    }
}

private actor FakeMediaPreviewGenerator: MediaPreviewGenerating {
    private(set) var calls = 0

    func generate(from file: URL, kind: NodeMediaKind) async -> MediaPreviewArtifact? {
        calls += 1
        return MediaPreviewArtifact(imageData: Data([1, 2, 3]), duration: 4)
    }
}
