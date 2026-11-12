import Foundation

/// Deterministic maps for canvas performance runs.
/// The tree is filled breadth first: the central topic has six branches and every other topic up to four children.
/// One free topic sits beside the tree; perf runs drag it, because a free topic keeps the tree laid out while it moves.
/// The same node count always gives the same ids, titles, and dates, so saved fixtures and in-app runs match.
public enum CanvasPerfFixture {
    public static let nodeCounts = [50, 200, 500]
    public static let rootFanOut = 6
    public static let branchFanOut = 4
    public static let createdAt = Date(timeIntervalSince1970: 1_793_000_000)

    public static func title(nodeCount: Int) -> String {
        "性能基线 \(nodeCount) 节点"
    }

    public static func filename(nodeCount: Int) -> String {
        "canvas-perf-\(nodeCount).floretta"
    }

    /// `nodeCount` includes the central topic. Values below 1 give a map with only the central topic.
    public static func document(nodeCount: Int) -> MindMapDocument {
        let total = max(1, nodeCount)
        // The free topic counts toward `nodeCount` when there is room for it.
        let treeCount = total > 1 ? total - 1 : total
        var titles: [String] = []
        var childIndices: [[Int]] = [[]]
        titles.append("中心主题")
        var queue = [0]
        var head = 0
        while titles.count < treeCount, head < queue.count {
            let parent = queue[head]
            head += 1
            let fanOut = parent == 0 ? rootFanOut : branchFanOut
            for _ in 0..<fanOut where titles.count < treeCount {
                let index = titles.count
                titles.append(topicTitle(index))
                childIndices.append([])
                childIndices[parent].append(index)
                queue.append(index)
            }
        }
        func build(_ index: Int) -> MindMapNode {
            MindMapNode(
                id: nodeID(index),
                text: titles[index],
                children: childIndices[index].map(build)
            )
        }
        var document = MindMapDocument.newMap(
            title: title(nodeCount: total),
            createdAt: createdAt,
            modifiedAt: createdAt,
            roots: [build(0)]
        )
        if total > 1 {
            document.freeNodes = [
                MindMapNode(id: freeNodeID, text: "自由主题", position: MindMapPoint(x: -120, y: -260)),
            ]
        }
        return document
    }

    public static let freeNodeID = UUID(uuidString: "00000000-0000-4000-9000-000000000001")!

    public static func nodeID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index))!
    }

    /// Short and longer titles mixed, so text measurement sees more than one line length.
    static func topicTitle(_ index: Int) -> String {
        switch index % 5 {
        case 0: return "较长的主题标题，用来测量换行 \(index)"
        case 1: return "主题 \(index)"
        case 2: return "Topic \(index) planning"
        case 3: return "分支要点 \(index)"
        default: return "想法 \(index)"
        }
    }
}
