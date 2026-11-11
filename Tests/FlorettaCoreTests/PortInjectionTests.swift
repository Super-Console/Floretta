import XCTest
import Foundation
import FlorettaCore

final class PortInjectionTests: XCTestCase {
    func testPortsAreInjectedWithoutPlatformBranches() throws {
        let clock: any ClockPort = FixedClock(instant: Date(timeIntervalSince1970: 42))
        let files: any FileAccessPort = MemoryFileAccess()
        let pasteboard = MemoryPasteboard()
        let device: any DeviceInfoPort = FixedDevice(deviceName: "测试机", modelIdentifier: "test")
        let fonts: any FontMetricsPort = FixedFonts()

        XCTAssertEqual(clock.now(), Date(timeIntervalSince1970: 42))
        let map = MindMapDocument.newMap(title: "固定时间", clock: clock)
        XCTAssertEqual(map.createdAt, Date(timeIntervalSince1970: 42))
        XCTAssertEqual(map.modifiedAt, Date(timeIntervalSince1970: 42))
        let nodeID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAA5")!
        var ai = FlorettaAISession(
            document: MindMapDocument(
                title: "AI",
                createdAt: Date(timeIntervalSince1970: 1),
                modifiedAt: Date(timeIntervalSince1970: 1),
                roots: [MindMapNode(id: nodeID, text: "old")]
            ),
            mode: .floretta,
            container: .florettaZip,
            clock: clock
        )
        _ = try ai.set(.text, at: nodeID.uuidString, value: "new")
        XCTAssertEqual(ai.document.modifiedAt, Date(timeIntervalSince1970: 42))
        XCTAssertEqual(try files.read(from: URL(fileURLWithPath: "/missing")), Data())
        XCTAssertNil(pasteboard.readText())
        pasteboard.writeText("主题")
        XCTAssertEqual(pasteboard.readText(), "主题")
        pasteboard.image = (Data([1, 2, 3]), "png")
        XCTAssertEqual(pasteboard.readImageData()?.data, Data([1, 2, 3]))
        XCTAssertEqual(device.deviceName, "测试机")
        XCTAssertEqual(device.modelIdentifier, "test")
        XCTAssertFalse(device.isPhone)
        let metrics = fonts.measure(text: "中", fontName: "serif", fontSize: 16, maxWidth: nil)
        XCTAssertEqual(metrics.width, 16)
        let measured = TextMeasurementCache(metrics: fonts).size(text: "中", fontSize: 16, maxWidth: 100)
        XCTAssertEqual(measured.width, 72)
        let cache = TextMeasurementCache(metrics: fonts)
        XCTAssertEqual(cache.size(text: "中", fontSize: 16, maxWidth: 200).height, 32)
        XCTAssertEqual(cache.missCount, 1)
    }

    func testCodecErrorDescriptionCrossesTheModuleBoundary() {
        let error: Error = FlorettaCodecError.corrupt("nope")
        XCTAssertEqual((error as? LocalizedError)?.errorDescription, "nope")
    }
}

private struct FixedClock: ClockPort {
    var instant: Date
    func now() -> Date { instant }
}

private struct MemoryFileAccess: FileAccessPort {
    func read(from url: URL) throws -> Data { Data() }
    func write(_ data: Data, to url: URL) throws {}
    func fileExists(at url: URL) -> Bool { false }
    func remove(at url: URL) throws {}
    func createDirectory(at url: URL) throws { XCTFail("Fake port expected") }
    func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey], skipsHiddenFiles: Bool) throws -> [URL] { XCTFail("Fake port expected"); return [] }
    func temporaryDirectory() -> URL { URL(fileURLWithPath: "/fake-temp") }
    func searchPathDirectory(_ directory: FileManager.SearchPathDirectory, create: Bool) throws -> URL? { nil }
    func ubiquityDocumentsDirectory() -> URL? { nil }
}

private final class MemoryPasteboard: PasteboardPort {
    private var text: String?
    var image: (data: Data, fileExtension: String)?
    func readText() -> String? { text }
    func writeText(_ text: String) { self.text = text }
    func readImageFileURL() -> URL? { nil }
    func readImageData() -> (data: Data, fileExtension: String)? { image }
}

private struct FixedDevice: DeviceInfoPort {
    var deviceName: String
    var modelIdentifier: String
    var isPhone: Bool { false }
}

private struct FixedFonts: FontMetricsPort {
    func measure(text: String, fontName: String, fontSize: Double, maxWidth: Double?) -> FontMetrics {
        FontMetrics(width: fontSize, height: fontSize, ascent: fontSize)
    }
}
