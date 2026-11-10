import FlorettaCore
import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers
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

    func testStickiesAreOptionalInPNGAndPDF() throws {
        let stickyID = UUID(uuidString: "ABABABAB-ABAB-ABAB-ABAB-ABABABABABAB")!
        var document = MindMapDocument(title: "卡", roots: [MindMapNode(text: "根")])
        document.addSticky(text: "便签", color: .yellow, at: MindMapPoint(x: 900, y: 700), id: stickyID)
        let included = MapExportOptions(scale: .one, background: .white, includeStickies: true)
        let excluded = MapExportOptions(scale: .one, background: .white, includeStickies: false)
        let withSticky = MapExporter.png(document: document, options: included)
        let nodesOnly = MapExporter.png(document: document, options: excluded)
        XCTAssertNil(withSticky.notice)
        XCTAssertGreaterThan(withSticky.pointSize.width, nodesOnly.pointSize.width + 40)
        XCTAssertGreaterThan(withSticky.pointSize.height, nodesOnly.pointSize.height + 40)
        XCTAssertFalse(withSticky.visibleNodeIDs.contains(stickyID))
        XCTAssertFalse(nodesOnly.visibleNodeIDs.contains(stickyID))
        XCTAssertEqual(nodesOnly.pointSize.width, MapExporter.png(
            document: MindMapDocument(title: "卡", roots: [MindMapNode(text: "根")]),
            options: included
        ).pointSize.width, accuracy: 1)

        let pdf = MapExporter.pdf(document: document, options: included)
        let pdfBare = MapExporter.pdf(document: document, options: excluded)
        XCTAssertGreaterThan(pdf.pointSize.width, pdfBare.pointSize.width + 40)
        XCTAssertFalse(pdf.visibleNodeIDs.contains(stickyID))
        XCTAssertNotNil(pdf.pdf)
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

    func testPNGAndPDFIncludeTheImageAspectFit() throws {
        let hash = String(repeating: "d", count: 64)
        let document = MindMapDocument(
            title: "img",
            roots: [MindMapNode(
                text: "图",
                attachments: [NodeAttachment(sha256: hash, fileExtension: "png", byteCount: 8, filename: "wide.png")]
            )]
        )
        let source = try solid(width: 80, height: 40, red: 0, green: 1, blue: 1)
        let images = [hash: source]
        let png = MapExporter.png(
            document: document,
            options: MapExportOptions(scale: .two, background: .white),
            images: images
        )
        let pngBox = try cyanBounds(try bitmap(try XCTUnwrap(png.png)))
        assertWideCyan(pngBox, document: document, scale: 2)

        let pdf = MapExporter.pdf(
            document: document,
            options: MapExportOptions(scale: .two, background: .white),
            images: images
        )
        let page = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(pdf.pdf))?.page(at: 0))
        let media = page.bounds(for: .mediaBox)
        let thumb = page.thumbnail(of: CGSize(width: media.width * 2, height: media.height * 2), for: .mediaBox)
        let pdfBox = try cyanBounds(try bitmap(thumb))
        assertWideCyan(pdfBox, document: document, scale: 2)
    }

    func testExportLoaderUsesPageResolutionNotTheThumbnailEdge() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlorettaExportImage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sourceURL = directory.appendingPathComponent("wide.png")
        let source = try solid(width: 400, height: 200, red: 0, green: 1, blue: 1)
        try writePNG(source, to: sourceURL)
        let files = FoundationStreamingFiles()
        let reader = try files.openReader(at: sourceURL)
        let hashed = try FlorettaStreamingDocument.hashSource(reader, filename: "wide.png")
        try reader.close()
        let document = MindMapDocument(
            title: "e",
            roots: [MindMapNode(text: "图", attachments: [try hashed.nodeAttachment()])]
        )
        let archive = directory.appendingPathComponent("map.floretta")
        let saved = try FlorettaStreamingDocument.save(
            document: document,
            to: archive,
            files: files,
            appending: (sourceURL, hashed)
        )
        let spill = directory.appendingPathComponent("spill", isDirectory: true)
        let loaded = ImageExportLoader.images(
            document: document,
            archive: archive,
            entries: saved.attachments,
            spillDirectory: spill,
            scale: 2
        )
        let image = try XCTUnwrap(loaded[hashed.sha256])
        let frame = try XCTUnwrap(LayoutEngine().layout(document).first)
        let slot = ImageSlot.slot(nodeWidth: Double(frame.size.width))
        let edge = ImageExportResolution.longestEdge(
            source: ImagePixelSize(width: 400, height: 200),
            slot: slot,
            scale: 2
        )
        XCTAssertGreaterThan(edge, StreamingBudget.thumbnailLongestEdge)
        XCTAssertGreaterThanOrEqual(max(image.width, image.height), edge - 2)
        XCTAssertLessThanOrEqual(max(image.width, image.height), 400)
        XCTAssertEqual(Double(image.width) / Double(image.height), 2, accuracy: 0.08)
        XCTAssertFalse(FileManager.default.fileExists(atPath: spill.appendingPathComponent(hashed.sha256).path))
        let plan = ImageDecodePlanKind.export(
            hash: hashed.sha256,
            source: ImagePixelSize(width: 400, height: 200),
            slot: slot,
            scale: 2
        )
        XCTAssertFalse(plan.storesInThumbnailCache)
    }

    func testPNGAndPDFIncludeTheRelationshipLine() throws {
        let left = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let right = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let link = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let bare = MindMapDocument(
            title: "关系",
            roots: [MindMapNode(text: "根", children: [
                MindMapNode(id: left, text: "左支"),
                MindMapNode(id: right, text: "右支"),
            ])]
        )
        var linked = bare
        _ = linked.linkTopics(from: left, to: right, title: "对照", id: link)
        let frames = MapExporter.visibleFrames(in: linked)
        let line = try XCTUnwrap(RelationshipGeometry.lines(in: linked, frames: frames).first)
        XCTAssertEqual(line.id, link)
        XCTAssertEqual(line.title, "对照")
        XCTAssertFalse(frames.contains { $0.id == link })

        XCTAssertTrue(bare.relationships.isEmpty)
        XCTAssertTrue(RelationshipGeometry.lines(in: bare, frames: MapExporter.visibleFrames(in: bare)).isEmpty)

        let options = MapExportOptions(scale: .two, background: .white)
        let without = MapExporter.png(document: bare, options: options)
        let png = MapExporter.png(document: linked, options: options)
        XCTAssertNil(png.notice)
        XCTAssertFalse(png.visibleNodeIDs.contains(link))
        XCTAssertEqual(relationshipInkCount(try bitmap(try XCTUnwrap(without.png))), 0)
        XCTAssertGreaterThan(relationshipInkCount(try bitmap(try XCTUnwrap(png.png))), 0)
        assertInside(line, result: png)

        let pdf = MapExporter.pdf(document: linked, options: options)
        XCTAssertNotNil(pdf.pdf)
        XCTAssertFalse(pdf.visibleNodeIDs.contains(link))
        assertInside(line, result: pdf)
        let page = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(pdf.pdf))?.page(at: 0))
        let media = page.bounds(for: .mediaBox)
        let thumb = page.thumbnail(of: CGSize(width: media.width * 2, height: media.height * 2), for: .mediaBox)
        XCTAssertGreaterThan(relationshipInkCount(try bitmap(thumb)), 0)
    }

    private func assertInside(_ line: RelationshipLine, result: MapExportResult, file: StaticString = #filePath, lineNumber: UInt = #line) {
        for point in [line.curve.start, line.curve.end, line.curveLabel] {
            let x = point.x - result.renderBounds.minX
            let y = point.y - result.renderBounds.minY
            XCTAssertGreaterThanOrEqual(x, -0.5, file: file, line: lineNumber)
            XCTAssertGreaterThanOrEqual(y, -0.5, file: file, line: lineNumber)
            XCTAssertLessThanOrEqual(x, result.pointSize.width + 0.5, file: file, line: lineNumber)
            XCTAssertLessThanOrEqual(y, result.pointSize.height + 0.5, file: file, line: lineNumber)
        }
    }

    /// Pixels of `RelationshipGeometry.ink` (0.11, 0.46, 0.50). Green and blue stay
    /// close and both sit above red, including a moderate blend toward white.
    /// Branch blue is (0.18, 0.52, 0.82): blended with the center node's black
    /// stroke or the white page, blue stays well above green, so a bare map
    /// does not match.
    private func relationshipInkCount(_ rep: NSBitmapImageRep) -> Int {
        var count = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                guard color.alphaComponent > 0.55 else { continue }
                let red = color.redComponent
                let green = color.greenComponent
                let blue = color.blueComponent
                let matches = abs(blue - green) < 0.10
                    && green > red + 0.18
                    && blue > red + 0.18
                    && green > 0.28 && green < 0.80
                    && blue > 0.28 && blue < 0.82
                    && red < 0.50
                if matches { count += 1 }
            }
        }
        return count
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

    private func solid(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) throws -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        let image = try XCTUnwrap(context)
        image.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        image.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(image.makeImage())
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            XCTFail("png destination")
            return
        }
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func bitmap(_ image: NSImage) throws -> NSBitmapImageRep {
        var proposed = CGRect(origin: .zero, size: image.size)
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: &proposed, context: nil, hints: nil))
        return try XCTUnwrap(NSBitmapImageRep(cgImage: cg))
    }

    private func cyanBounds(_ rep: NSBitmapImageRep) throws -> CGRect {
        var minX = rep.pixelsWide
        var minY = rep.pixelsHigh
        var maxX = 0
        var maxY = 0
        var found = false
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                guard color.redComponent < 0.25, color.greenComponent > 0.75, color.blueComponent > 0.75 else { continue }
                found = true
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        XCTAssertTrue(found, "exported image should contain the cyan picture")
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private func assertWideCyan(_ box: CGRect, document: MindMapDocument, scale: CGFloat) {
        XCTAssertGreaterThan(box.width, box.height)
        XCTAssertEqual(box.width / box.height, 2, accuracy: 0.35)
        let frame = MapExporter.visibleFrames(in: document)[0]
        let slot = ImageSlot.slot(nodeWidth: Double(frame.size.width))
        let fitted = ImageAspectFit.fit(pixels: ImagePixelSize(width: 80, height: 40), in: slot)
        XCTAssertGreaterThanOrEqual(box.width, fitted.width * Double(scale) - 8)
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
