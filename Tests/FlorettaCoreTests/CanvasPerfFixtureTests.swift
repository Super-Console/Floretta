import Foundation
import XCTest
@testable import FlorettaCore

final class CanvasPerfFixtureTests: XCTestCase {
    func testNodeCountsMatchRequest() {
        for count in CanvasPerfFixture.nodeCounts {
            let document = CanvasPerfFixture.document(nodeCount: count)
            XCTAssertEqual(document.roots.count, 1)
            XCTAssertEqual(document.freeNodes.map(\.id), [CanvasPerfFixture.freeNodeID])
            XCTAssertEqual(Self.count(document.roots) + document.freeNodes.count, count)
        }
    }

    func testFixtureIsDeterministic() {
        XCTAssertEqual(CanvasPerfFixture.document(nodeCount: 200), CanvasPerfFixture.document(nodeCount: 200))
    }

    func testHierarchyIsLayered() {
        let document = CanvasPerfFixture.document(nodeCount: 500)
        XCTAssertEqual(document.roots[0].children.count, CanvasPerfFixture.rootFanOut)
        XCTAssertGreaterThanOrEqual(Self.depth(document.roots[0]), 4)
    }

    /// Writes the three fixtures into `docs/reviews/perf-fixtures` when `FLORETTA_WRITE_PERF_FIXTURES=1`.
    func testWritesFixturesWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["FLORETTA_WRITE_PERF_FIXTURES"] == "1" else {
            throw XCTSkip("Set FLORETTA_WRITE_PERF_FIXTURES=1 to refresh docs/reviews/perf-fixtures")
        }
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folder = repo.appendingPathComponent("docs/reviews/perf-fixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for count in CanvasPerfFixture.nodeCounts {
            let url = folder.appendingPathComponent(CanvasPerfFixture.filename(nodeCount: count))
            let package = FlorettaPackage(document: CanvasPerfFixture.document(nodeCount: count))
            try FlorettaDocumentFile.save(package, to: url, fileAccess: FoundationFileAccess())
            let loaded = try FlorettaDocumentFile.read(from: url, fileAccess: FoundationFileAccess())
            let reopened = loaded.package.document
            XCTAssertEqual(Self.count(reopened.roots) + reopened.freeNodes.count, count)
        }
    }

    private static func count(_ nodes: [MindMapNode]) -> Int {
        nodes.reduce(0) { $0 + 1 + count($1.children) }
    }

    private static func depth(_ node: MindMapNode) -> Int {
        1 + (node.children.map(depth).max() ?? 0)
    }
}
