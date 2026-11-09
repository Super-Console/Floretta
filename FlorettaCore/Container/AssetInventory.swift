import Foundation

/// One attachment that failed the sha256 inventory. The name is the file the user
/// attached, not a generic "the document is corrupt".
public struct AssetCorruption: Equatable, Sendable {
    public var filename: String
    public var sha256: String
    public var entryName: String
    public var reason: AssetCorruptionReason

    public init(filename: String, sha256: String, entryName: String, reason: AssetCorruptionReason) {
        self.filename = filename
        self.sha256 = sha256
        self.entryName = entryName
        self.reason = reason
    }

    public var reasonText: String {
        switch reason {
        case .hashMismatch(let actual):
            return "内容与 sha256 不符（实际 \(actual)）。"
        case .missingFromPackage:
            return "包内没有这个附件。"
        case .unreadable:
            return "读取中断，没能算完 sha256。"
        case .compressed:
            return "被压缩了，不能按原字节核对 sha256。"
        case .malformedName:
            return "条目名不是 assets/<sha256>.<ext>。"
        case .declaredChecksumMismatch:
            return "内容和包内声明的校验不符。"
        }
    }
}

public enum AssetCorruptionReason: Equatable, Sendable {
    case hashMismatch(actual: String)
    case missingFromPackage
    case unreadable
    case compressed
    case malformedName
    case declaredChecksumMismatch
}

/// Open-time inventory failure. Lists each bad attachment. It is not a failure to read `document.json`.
public struct AssetInventoryError: Error, Equatable, Sendable, LocalizedError {
    public var failures: [AssetCorruption]

    public init(failures: [AssetCorruption]) {
        self.failures = failures
    }

    public var promptTitle: String { "附件已损坏" }

    public var promptMessage: String {
        let header = failures.count == 1
            ? "有 1 个附件和 sha256 清单不一致。这不是整份导图读失败。"
            : "有 \(failures.count) 个附件和 sha256 清单不一致。这不是整份导图读失败。"
        let lines = failures.map { failure in
            "· \(failure.filename)（\(failure.entryName)）\(failure.reasonText)"
        }
        return ([header] + lines).joined(separator: "\n")
    }

    public var errorDescription: String? { promptMessage }
}

enum AssetInventory {
    static func error(from failures: [AssetCorruption]) -> AssetInventoryError? {
        failures.isEmpty ? nil : AssetInventoryError(failures: failures)
    }

    static func filenames(for sha256: String, in document: MindMapDocument) -> String {
        var names: [String] = []
        document.walkTopics { node in
            for attachment in node.attachments where attachment.sha256 == sha256 {
                if !names.contains(attachment.filename) {
                    names.append(attachment.filename)
                }
            }
        }
        if names.isEmpty { return "未命名附件" }
        return names.joined(separator: "、")
    }

    static func missingReferences(in document: MindMapDocument, stored: Set<String>) -> [AssetCorruption] {
        var failures: [AssetCorruption] = []
        var reported: Set<String> = []
        document.walkTopics { node in
            for attachment in node.attachments {
                guard stored.contains(attachment.sha256) == false else { continue }
                guard reported.insert(attachment.sha256).inserted else { continue }
                let entry = AttachmentNames.assetName(sha256: attachment.sha256, fileExtension: attachment.fileExtension)
                failures.append(AssetCorruption(
                    filename: attachment.filename,
                    sha256: attachment.sha256,
                    entryName: entry,
                    reason: .missingFromPackage
                ))
            }
        }
        return failures
    }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
