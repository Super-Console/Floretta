import FlorettaCore
import AppKit
import PDFKit
import XCTest

@MainActor
final class MapExportTests: XCTestCase {
    func testPNGScaleAndWhiteBackgroundAreNotBlank() throws {
        let document = sampleMap()
        for scale in [MapExportScale.two, MapExportScale.three] {
            let result = MapExporter.png(
                document: document,
                options: MapExportOptions(scale: scale, background: .white, maxPixelDimension: 8192)
            )
            XCTAssertFalse(result.truncated)
            XCTAssertNil(result.notice)
            let rep = try bitmap(try XCTUnwrap(result.png))
            XCTAssertGreaterThan(rep.pixelsWide, 0)
            XCTAssertGreaterThan(rep.pixelsHigh, 0)
            XCTAssertEqual(Double(rep.pixelsWide), result.pointSize.width * scale.rawValue, accuracy: 4)
            XCTAssertEqual(Double(rep.pixelsHigh), result.pointSize.height * scale.rawValue, accuracy: 4)
            XCTAssertTrue(hasPixel(in: rep) { color in
                guard let s = color.usingColorSpace(.sRGB) else { return false }
                let away = abs(s.redComponent - 1) + abs(s.greenComponent - 1) + abs(s.blueComponent - 1)
                return s.alphaComponent > 0.9 && away > 0.2
            }, "scale \(scale.rawValue) should include a node stroke or fill, not only white")
        }
    }

    func testTransparentPNGHasClearPaddingAndOpaqueInk() throws {
        let result = MapExporter.png(
            document: sampleMap(),
            options: MapExportOptions(scale: .two, background: .transparent)
        )
        let rep = try bitmap(try XCTUnwrap(result.png))
        XCTAssertGreaterThan(rep.pixelsWide, 0)
        XCTAssertTrue(hasPixel(in: rep) { ($0.usingColorSpace(.sRGB)?.alphaComponent ?? 1) < 0.05 })
        XCTAssertTrue(hasPixel(in: rep) { ($0.usingColorSpace(.sRGB)?.alphaComponent ?? 0) > 0.5 })
    }

    func testPDFPageAndMediaBox() throws {
        let result = MapExporter.pdf(
            document: sampleMap(),
            options: MapExportOptions(scale: .two, background: .white)
        )
        XCTAssertFalse(result.truncated)
        let document = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(result.pdf)))
        XCTAssertEqual(document.pageCount, 1)
        let box = try XCTUnwrap(document.page(at: 0)?.bounds(for: .mediaBox))
        XCTAssertGreaterThan(box.width, 0)
        XCTAssertGreaterThan(box.height, 0)
        XCTAssertEqual(box.width, result.pointSize.width, accuracy: 1)
        XCTAssertEqual(box.height, result.pointSize.height, accuracy: 1)
        XCTAssertEqual(box, result.mediaBox)
    }

    func testCollapsedChildrenAreOmitted() {
        let hidden = UUID()
        let child = UUID()
        let root = UUID()
        let document = MindMapDocument(
            title: "fold",
            roots: [
                MindMapNode(
                    id: root,
                    text: "根",
                    children: [
                        MindMapNode(
                            id: child,
                            text: "子",
                            isCollapsed: true,
                            children: [MindMapNode(id: hidden, text: "藏")]
                        ),
                    ]
                ),
            ]
        )
        let ids = MapExporter.visibleFrames(in: document).map(\.id)
        XCTAssertEqual(ids, [root, child])
        XCTAssertFalse(ids.contains(hidden))
    }

    func testThousandNodeExportHitsThePixelCap() {
        var branches: [MindMapNode] = []
        for index in 0..<40 {
            let leaves = index == 39 ? 23 : 24
            branches.append(
                MindMapNode(
                    text: "支\(index)",
                    children: (0..<leaves).map { MindMapNode(text: "叶\(index)-\($0)") }
                )
            )
        }
        let document = MindMapDocument(title: "big", roots: [MindMapNode(text: "根", children: branches)])
        XCTAssertEqual(MapExporter.visibleFrames(in: document).count, 1000)
        let result = MapExporter.png(
            document: document,
            options: MapExportOptions(scale: .three, background: .white, maxPixelDimension: 64)
        )
        XCTAssertTrue(result.truncated)
        XCTAssertEqual(result.notice, MapExporter.clippingNotice)
        XCTAssertLessThanOrEqual(result.pixelSize.width, 64)
        XCTAssertLessThanOrEqual(result.pixelSize.height, 64)
        XCTAssertGreaterThan(result.png?.count ?? 0, 0)
    }

    private func sampleMap() -> MindMapDocument {
        MindMapDocument(
            title: "export",
            roots: [
                MindMapNode(text: "根", children: [MindMapNode(text: "子")]),
            ]
        )
    }

    private func bitmap(_ data: Data) throws -> NSBitmapImageRep {
        let image = try XCTUnwrap(NSImage(data: data))
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
        var proposed = CGRect(origin: .zero, size: image.size)
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: &proposed, context: nil, hints: nil))
        return try XCTUnwrap(NSBitmapImageRep(cgImage: cg))
    }

    private func hasPixel(in rep: NSBitmapImageRep, where match: (NSColor) -> Bool) -> Bool {
        let stepX = max(rep.pixelsWide / 24, 1)
        let stepY = max(rep.pixelsHigh / 24, 1)
        var y = 0
        while y < rep.pixelsHigh {
            var x = 0
            while x < rep.pixelsWide {
                if let color = rep.colorAt(x: x, y: y), match(color) {
                    return true
                }
                x += stepX
            }
            y += stepY
        }
        return false
    }
}
