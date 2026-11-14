import FlorettaCore
import XCTest

final class ContainerTests: XCTestCase {
    private let stamped = Date(timeIntervalSince1970: 1_762_646_400)

    func testOpensExistingFlorettaFixtureWithDefaultTextFields() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixture = repository.appendingPathComponent("docs/reviews/theme-modes/glyph-sample.floretta")
        let opened = try FlorettaDocumentFile.read(from: fixture, fileAccess: FoundationFileAccess())
        XCTAssertFalse(opened.package.document.roots.isEmpty)
        opened.package.document.walkTopics { node in
            XCTAssertEqual(node.textAlignment, .center)
            XCTAssertEqual(node.subtitle, "")
        }
    }

    func testLegacyJSONIsReadableAndNotOverwritten() throws {
        let document = sampleDocument(title: "旧文件")
        let legacy = try FlorettaCodec.encode(document)
        let directory = try makeDirectory()
        let original = directory.appendingPathComponent("original.floretta")
        try legacy.write(to: original)
        let before = try Data(contentsOf: original)

        let loaded = try FlorettaDocumentFile.read(from: original, fileAccess: FoundationFileAccess())
        XCTAssertEqual(loaded.kind, .legacyJSON)
        XCTAssertEqual(loaded.package.document, document)
        XCTAssertTrue(loaded.package.assets.isEmpty)
        XCTAssertEqual(try Data(contentsOf: original), before)

        XCTAssertThrowsError(try LegacyJSONContainer().write(loaded.package)) { error in
            XCTAssertEqual(error as? DocumentContainerError, .readOnlyLegacy)
        }
        XCTAssertThrowsError(try FlorettaDocumentFile.save(loaded.package, to: original, fileAccess: FoundationFileAccess())) { error in
            XCTAssertEqual(error as? DocumentContainerError, .refusesToOverwriteLegacy)
        }
        XCTAssertEqual(try Data(contentsOf: original), before)

        let saved = directory.appendingPathComponent("copy.floretta")
        try FlorettaDocumentFile.save(loaded.package, to: saved, fileAccess: FoundationFileAccess())
        let written = try Data(contentsOf: saved)
        XCTAssertTrue(FlorettaDocumentFile.isZip(written))
        let again = try FlorettaDocumentFile.read(from: saved, fileAccess: FoundationFileAccess())
        XCTAssertEqual(again.kind, .zip)
        XCTAssertEqual(again.package.document, document)
        XCTAssertEqual(try Data(contentsOf: original), before)
    }

    func testZipRoundTripIsIdenticalAndOrderIsStable() throws {
        var package = FlorettaPackage(document: sampleDocument(title: "往返"))
        let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4])
        let jpg = Data([0xFF, 0xD8, 0xFF, 9, 8, 7])
        _ = package.addAsset(data: png, fileExtension: "png")
        _ = package.addAsset(data: jpg, fileExtension: "jpg")
        let container = ZipContainer()
        let data = try container.write(package)
        let names = try ZipArchive.read(data, limits: .standard).map(\.name)
        XCTAssertEqual(names, names.sorted())
        let loaded = try container.read(data: data)
        XCTAssertEqual(loaded, package)
    }

    func testAttachmentDedupKeepsOneCopy() throws {
        var package = FlorettaPackage(document: sampleDocument(title: "图"))
        let png = Data([0x89, 0x50, 0x4E, 0x47, 5, 5, 5])
        let first = package.addAsset(data: png, fileExtension: "png")
        let second = package.addAsset(data: png, fileExtension: "PNG")
        XCTAssertEqual(first, second)
        XCTAssertEqual(package.assets.count, 1)
        let loaded = try ZipContainer().read(data: try ZipContainer().write(package))
        XCTAssertEqual(loaded.assets.count, 1)
        XCTAssertEqual(loaded.assets[0].data, png)
        let assetNames = try ZipArchive.read(try ZipContainer().write(package), limits: .standard)
            .map(\.name)
            .filter { $0.hasPrefix("assets/") }
        XCTAssertEqual(assetNames.count, 1)
    }

    func testMissingDocumentJSONThrows() throws {
        let metadata = FlorettaMetadata(document: sampleDocument(title: "x"))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(metadata)
        let zip = ZipArchive.write([ZipEntry(name: "metadata.json", data: bytes)])
        XCTAssertThrowsError(try ZipContainer().read(data: zip)) { error in
            XCTAssertEqual(error as? DocumentContainerError, .missingEntry("document.json"))
        }
    }

    func testCorruptZipDoesNotCrash() {
        var junk = Data([0x50, 0x4B, 0x03, 0x04])
        junk.append(contentsOf: [0, 1, 2, 3, 4])
        XCTAssertThrowsError(try ZipContainer().read(data: junk)) { error in
            guard case .corrupt = error as? DocumentContainerError else {
                return XCTFail("expected corrupt, got \(error)")
            }
        }
    }

    func testOverLimitIsRejected() throws {
        let limits = ZipLimits(maxEntries: 2, maxDecompressedBytes: 64, maxNodes: 2, maxAssetBytes: 8)
        let tooMany = ZipArchive.write([
            ZipEntry(name: "a.txt", data: Data("a".utf8)),
            ZipEntry(name: "b.txt", data: Data("b".utf8)),
            ZipEntry(name: "c.txt", data: Data("c".utf8)),
        ])
        XCTAssertThrowsError(try ZipContainer(limits: limits).read(data: tooMany)) { error in
            guard case .overLimit = error as? DocumentContainerError else {
                return XCTFail("expected overLimit, got \(error)")
            }
        }

        let fat = ZipArchive.write([
            ZipEntry(name: "document.json", data: Data(repeating: 1, count: 80)),
        ])
        XCTAssertThrowsError(try ZipContainer(limits: limits).read(data: fat)) { error in
            guard case .overLimit = error as? DocumentContainerError else {
                return XCTFail("expected overLimit, got \(error)")
            }
        }

        let wide = MindMapDocument(
            title: "wide",
            createdAt: stamped,
            modifiedAt: stamped,
            roots: [
                MindMapNode(text: "a"),
                MindMapNode(text: "b"),
                MindMapNode(text: "c"),
            ]
        )
        XCTAssertThrowsError(try ZipContainer(limits: limits).write(FlorettaPackage(document: wide))) { error in
            guard case .overLimit = error as? DocumentContainerError else {
                return XCTFail("expected overLimit, got \(error)")
            }
        }
    }

    func testInflateStoredAndFixedBlocks() throws {
        let stored = Data([0x01, 0x02, 0x00, 0xFD, 0xFF, 0x48, 0x69])
        XCTAssertEqual(try RawInflate.inflate(stored, maxOutput: 16), Data("Hi".utf8))
        let fixed = Data([0x73, 0x04, 0x00])
        XCTAssertEqual(try RawInflate.inflate(fixed, maxOutput: 16), Data("A".utf8))
        XCTAssertThrowsError(try RawInflate.inflate(stored, maxOutput: 1)) { error in
            XCTAssertTrue(error is InflateError)
        }
    }

    func testCRC32KnownVector() {
        XCTAssertEqual(zipCRC32(Data("123456789".utf8)), 0xCBF4_3926)
    }

    func testSHA256MatchesTheStandardVectors() {
        XCTAssertEqual(
            sha256Hex(Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        XCTAssertEqual(
            sha256Hex(Data()),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    private func sampleDocument(title: String) -> MindMapDocument {
        MindMapDocument(
            title: title,
            createdAt: stamped,
            modifiedAt: stamped,
            roots: [MindMapNode(text: "根")]
        )
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlorettaContainerTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
