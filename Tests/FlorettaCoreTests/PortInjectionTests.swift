import XCTest
import FlorettaCore

final class PortInjectionTests: XCTestCase {
    func testPortsAreInjectedWithoutPlatformBranches() throws {
        let clock: any ClockPort = FixedClock(instant: Date(timeIntervalSince1970: 42))
        let files: any FileAccessPort = MemoryFileAccess()
        let pasteboard: any PasteboardPort = MemoryPasteboard()
        let device: any DeviceInfoPort = FixedDevice(deviceName: "测试机", modelIdentifier: "test")
        let fonts: any FontMetricsPort = FixedFonts()

        XCTAssertEqual(clock.now(), Date(timeIntervalSince1970: 42))
        XCTAssertEqual(try files.read(from: URL(fileURLWithPath: "/missing")), Data())
        XCTAssertNil(pasteboard.readText())
        pasteboard.writeText("主题")
        XCTAssertEqual(pasteboard.readText(), "主题")
        XCTAssertEqual(device.deviceName, "测试机")
        XCTAssertEqual(device.modelIdentifier, "test")
        let metrics = fonts.measure(text: "中", fontName: "serif", fontSize: 16, maxWidth: nil)
        XCTAssertEqual(metrics.width, 16)
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
}

private final class MemoryPasteboard: PasteboardPort {
    private var text: String?
    func readText() -> String? { text }
    func writeText(_ text: String) { self.text = text }
}

private struct FixedDevice: DeviceInfoPort {
    var deviceName: String
    var modelIdentifier: String
}

private struct FixedFonts: FontMetricsPort {
    func measure(text: String, fontName: String, fontSize: Double, maxWidth: Double?) -> FontMetrics {
        FontMetrics(width: fontSize, height: fontSize, ascent: fontSize)
    }
}
