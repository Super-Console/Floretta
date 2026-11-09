import FlorettaCore
import UniformTypeIdentifiers
import XCTest

@MainActor
final class FileTypeIconTests: XCTestCase {
    func testPDFDMGAndPSDAreRecognized() {
        let pdf = AppleFileTypes.recognize(filename: "Notes.PDF", declaredTypeIdentifier: nil)
        XCTAssertEqual(pdf.typeIdentifier, UTType.pdf.identifier)
        XCTAssertEqual(pdf.fileExtension, "pdf")
        XCTAssertTrue(pdf.systemIconAvailable)
        XCTAssertEqual(FileIconPolicy.resolution(for: pdf), .system(typeIdentifier: UTType.pdf.identifier))

        let dmg = AppleFileTypes.recognize(filename: "Floretta.dmg", declaredTypeIdentifier: nil)
        XCTAssertEqual(dmg.fileExtension, "dmg")
        XCTAssertEqual(dmg.typeIdentifier, UTType(filenameExtension: "dmg")?.identifier)
        assertResolution(dmg)

        let psd = AppleFileTypes.recognize(filename: "Poster.psd", declaredTypeIdentifier: nil)
        XCTAssertEqual(psd.fileExtension, "psd")
        XCTAssertEqual(psd.typeIdentifier, UTType(filenameExtension: "psd")?.identifier)
        assertResolution(psd)
        if psd.systemIconAvailable == false {
            XCTAssertEqual(FileIconPolicy.resolution(for: psd), .generic(typeIdentifier: psd.typeIdentifier))
        }
    }

    func testUnknownExtensionUsesTheGenericFileIcon() {
        let fact = AppleFileTypes.recognize(filename: "blob.qzxfloretta", declaredTypeIdentifier: nil)
        XCTAssertFalse(fact.systemIconAvailable)
        XCTAssertEqual(FileIconPolicy.resolution(for: fact), .generic(typeIdentifier: fact.typeIdentifier))
        _ = AppleFileIcon.image(for: FileIconPolicy.resolution(for: fact))
        _ = AppleFileIcon.image(for: .system(typeIdentifier: UTType.pdf.identifier))
    }

    func testDeclaredUTISuppliesTheExtension() {
        let fact = AppleFileTypes.recognize(filename: "download", declaredTypeIdentifier: UTType.pdf.identifier)
        XCTAssertEqual(fact.typeIdentifier, UTType.pdf.identifier)
        XCTAssertEqual(fact.fileExtension, "pdf")
        XCTAssertEqual(
            FileAttachmentName.storedFilename(original: "download", recognizedExtension: fact.fileExtension),
            "download.pdf"
        )
    }

    func testPickerAcceptsAnyTypeIncludingPSDPDFAndDMG() {
        let types = AppleFileTypes.importableContentTypes
        XCTAssertTrue(types.contains(.item))
        XCTAssertTrue(types.contains(.data))
        XCTAssertTrue(types.contains(.pdf))
        if let psd = UTType(filenameExtension: "psd") {
            XCTAssertTrue(types.contains(psd))
        }
        if let dmg = UTType(filenameExtension: "dmg") {
            XCTAssertTrue(types.contains(dmg))
        }
    }

    func testDeletingThePreviewFileDoesNotTrap() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        try Data("%PDF-1.4".utf8).write(to: url)
        let item = PreviewFileItem(url: url, title: "notes.pdf")
        XCTAssertEqual(PreviewFileProbe.urlIfPresent(url), url)
        XCTAssertTrue(item.isReadable)
        XCTAssertEqual(item.previewItemURL, url)
        try FileManager.default.removeItem(at: url)
        XCTAssertNil(PreviewFileProbe.urlIfPresent(url))
        XCTAssertFalse(item.isReadable)
        XCTAssertNotNil(item.previewItemURL)
        let ticket = FilePreviewTicket(
            nodeID: UUID(),
            sha256: String(repeating: "a", count: 64),
            filename: "notes.pdf",
            previewPath: url.path
        )
        XCTAssertEqual(
            FilePreviewSession.fileDisappeared(.presenting(ticket)).alertMessage,
            FilePreviewSession.missingMessage
        )
    }

    private func assertResolution(_ fact: FileTypeFact) {
        let resolution = FileIconPolicy.resolution(for: fact)
        if fact.systemIconAvailable, let identifier = fact.typeIdentifier, !identifier.hasPrefix("dyn.") {
            XCTAssertEqual(resolution, .system(typeIdentifier: identifier))
        } else {
            XCTAssertEqual(resolution, .generic(typeIdentifier: fact.typeIdentifier))
        }
    }
}
