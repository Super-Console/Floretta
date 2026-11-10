import Foundation

public enum FlorettaTextBundleError: Error, Equatable, Sendable {
    case unsafePath(String)
}

extension FlorettaTextBundleError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsafePath(let path):
            return "TextBundle 路径不安全：\(path)"
        }
    }
}

/// One file inside a TextBundle. `path` is relative to the bundle root and uses `/`.
public struct TextBundleFile: Equatable, Sendable {
    public var path: String
    public var data: Data

    public init(path: String, data: Data) {
        self.path = path
        self.data = data
    }
}

/// A TextBundle package: `info.json`, `text.md`, and any `assets/` files.
/// `.textpack` is the same files in a zip, plus an `assets/` directory entry.
public struct TextBundlePackage: Equatable, Sendable {
    public var files: [TextBundleFile]

    public init(files: [TextBundleFile]) {
        self.files = files
    }

    public func data(at path: String) -> Data? {
        files.first { $0.path == path }?.data
    }

    public var textMarkdown: String {
        guard let data = data(at: FlorettaTextBundleCodec.textFileName) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Zip of the bundle files. Names sort the same way as `ZipArchive.write`.
    /// An empty `assets/` directory is still an entry, so the pack matches the spec's folder.
    public func textpack() -> Data {
        var entries = files.map { ZipEntry(name: $0.path, data: $0.data) }
        if !entries.contains(where: { $0.name == "assets/" }) {
            entries.append(ZipEntry(name: "assets/", data: Data()))
        }
        return ZipArchive.write(entries)
    }

    /// Writes a `.textbundle` directory. `root` is the bundle itself (`Something.textbundle`).
    /// Always creates `assets/`, including when no file was referenced.
    public func writeDirectory(to root: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: root.appendingPathComponent("assets", isDirectory: true),
            withIntermediateDirectories: true
        )
        for file in files {
            let parts = file.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard !parts.isEmpty, parts.allSatisfy(Self.isSafeComponent) else {
                throw FlorettaTextBundleError.unsafePath(file.path)
            }
            var destination = root
            for (index, part) in parts.enumerated() {
                let isDirectory = index < parts.count - 1
                destination = destination.appendingPathComponent(part, isDirectory: isDirectory)
                if isDirectory {
                    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                }
            }
            try file.data.write(to: destination, options: .atomic)
        }
    }

    private static func isSafeComponent(_ part: String) -> Bool {
        !part.isEmpty && part != "." && part != ".." && !part.contains("/") && !part.contains("\\")
    }
}

/// Export a map as a TextBundle. Import is not implemented.
///
/// `text.md` is `FlorettaMarkdownDocumentCodec.save` — the map's Markdown document
/// (nested lists, optional H1 sections, notes, one link, front matter). The heading-depth
/// `FlorettaMarkdown` preset is a separate 「导出为…」 path and is not used here.
/// That codec does not write attachments. This exporter leaves its text in place and,
/// after each node's note lines, inserts a Markdown image or link for every attachment
/// whose bytes were provided. The link target is `assets/<file>`, per the TextBundle spec.
public enum FlorettaTextBundleCodec {
    public static let bundleExtension = "textbundle"
    public static let packExtension = "textpack"
    public static let textFileName = "text.md"
    public static let infoFileName = "info.json"
    public static let markdownUTI = "net.daringfireball.markdown"
    /// Bundle id of the macOS and iOS apps.
    public static let creatorIdentifier = "net.timhuang.floretta"
    public static let creatorURL = "https://github.com/Super-Console/Floretta"
    public static let formatVersion = 2

    /// Pretty JSON, stable key order, trailing newline. `sourceURL` is omitted.
    public static let infoJSON = """
    {
      "version": 2,
      "type": "net.daringfireball.markdown",
      "transient": false,
      "creatorURL": "https://github.com/Super-Console/Floretta",
      "creatorIdentifier": "net.timhuang.floretta"
    }
    """

    public static func export(_ package: FlorettaPackage) -> TextBundlePackage {
        export(package.document, assets: package.assets)
    }

    /// `assets` are keyed by sha256. The first payload for a hash wins.
    /// Bytes no tree node on the first sheet references are left out.
    public static func export(_ document: MindMapDocument, assets: [FlorettaAsset] = []) -> TextBundlePackage {
        let plan = planAssets(document: document, assets: assets)
        let markdown = markdownText(document: document, references: plan.references)
        var files = [
            TextBundleFile(path: infoFileName, data: Data((infoJSON + "\n").utf8)),
            TextBundleFile(path: textFileName, data: Data(markdown.utf8)),
        ]
        for path in plan.files.keys.sorted() {
            files.append(TextBundleFile(path: path, data: plan.files[path] ?? Data()))
        }
        files.sort { $0.path < $1.path }
        return TextBundlePackage(files: files)
    }

    private struct AssetPlan {
        var references: [UUID: [String]]
        var files: [String: Data]
    }

    private static func planAssets(document: MindMapDocument, assets: [FlorettaAsset]) -> AssetPlan {
        var bytes: [String: Data] = [:]
        for asset in assets where bytes[asset.sha256] == nil {
            bytes[asset.sha256] = asset.data
        }
        var usedLeaf: [String: String] = [:]
        var leafByHash: [String: String] = [:]
        var references: [UUID: [String]] = [:]
        var files: [String: Data] = [:]

        func walk(_ nodes: [MindMapNode]) {
            for node in nodes {
                var lines: [String] = []
                for attachment in node.attachments {
                    guard let data = bytes[attachment.sha256] else { continue }
                    let stored = uniqueLeaf(for: attachment, usedLeaf: &usedLeaf, leafByHash: &leafByHash)
                    let label = markdownLabel(displayLeaf(attachment))
                    let destination = markdownDestination(stored)
                    let line = AttachmentKind.isImageExtension(attachment.fileExtension)
                        ? "![\(label)](\(destination))"
                        : "[\(label)](\(destination))"
                    lines.append(line)
                    let path = "assets/\(stored)"
                    if files[path] == nil {
                        files[path] = data
                    }
                }
                if !lines.isEmpty {
                    var existing = references[node.id] ?? []
                    existing.append(contentsOf: lines)
                    references[node.id] = existing
                }
                walk(node.children)
            }
        }
        walk(document.roots)
        return AssetPlan(references: references, files: files)
    }

    /// Codec output, plus asset lines after each node's note block.
    /// List-item assets are indented one level past the marker so they stay in that item.
    /// A section heading's assets stay at column 0, between the heading notes and its list.
    private static func markdownText(document: MindMapDocument, references: [UUID: [String]]) -> String {
        var withoutFrontMatter = document
        withoutFrontMatter.markdownFrontMatter = nil
        let body = FlorettaMarkdownDocumentCodec.save(withoutFrontMatter)
        let prefix = frontMatterPrefix(document.markdownFrontMatter)
        guard !references.isEmpty else {
            if prefix.isEmpty { return body }
            return prefix + body
        }
        let spliced = splice(body, roots: document.roots, references: references)
        return prefix + spliced
    }

    /// Same newline cleanup as `FlorettaMarkdownDocumentCodec.save`'s front matter.
    /// Kept here so asset splicing does not have to re-parse the codec string.
    private static func frontMatterPrefix(_ raw: String?) -> String {
        guard var text = raw else { return "" }
        text = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        while text.hasSuffix("\n") {
            text.removeLast()
        }
        if text.isEmpty { return "" }
        return text + "\n\n"
    }

    private static func splice(_ body: String, roots: [MindMapNode], references: [UUID: [String]]) -> String {
        if body.isEmpty { return body }
        var lines = splitLines(body)
        var cursor = 0
        var output: [String] = []

        func take(_ count: Int) {
            guard count > 0, cursor < lines.count else { return }
            let end = min(lines.count, cursor + count)
            output.append(contentsOf: lines[cursor..<end])
            cursor = end
        }

        func walk(_ nodes: [MindMapNode], level: Int, allowHeading: Bool) {
            for node in nodes {
                let heading = allowHeading && node.isMarkdownSectionHeading
                take(1)
                take(noteLineCount(node.note))
                let pad = heading ? "" : String(repeating: " ", count: (level + 1) * 2)
                for line in references[node.id] ?? [] {
                    output.append(pad + line)
                }
                walk(node.children, level: heading ? 0 : level + 1, allowHeading: false)
            }
        }

        walk(roots, level: 0, allowHeading: true)
        if cursor < lines.count {
            output.append(contentsOf: lines[cursor...])
        }
        if output.isEmpty { return body }
        return output.joined(separator: "\n") + "\n"
    }

    private static func noteLineCount(_ note: String) -> Int {
        if note.isEmpty { return 0 }
        let normalized = note
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalized.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    private static func splitLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if text.hasSuffix("\n"), lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return lines
    }

    private static func displayLeaf(_ attachment: NodeAttachment) -> String {
        let original = originalLeaf(attachment.filename)
        if !original.isEmpty { return original }
        return "\(attachment.sha256).\(AttachmentNames.normalizeExtension(attachment.fileExtension))"
    }

    private static func uniqueLeaf(
        for attachment: NodeAttachment,
        usedLeaf: inout [String: String],
        leafByHash: inout [String: String]
    ) -> String {
        if let existing = leafByHash[attachment.sha256] {
            return existing
        }
        let preferred = asciiLeaf(attachment)
        var leaf = preferred
        if let owner = usedLeaf[leaf], owner != attachment.sha256 {
            let ext = fileExtension(of: leaf)
            let stem = ext.isEmpty ? leaf : String(leaf.dropLast(ext.count + 1))
            let short = String(attachment.sha256.prefix(8))
            let tagged = ext.isEmpty ? "\(stem)-\(short)" : "\(stem)-\(short).\(ext)"
            if usedLeaf[tagged] == nil {
                leaf = tagged
            } else {
                let hashExt = AttachmentNames.normalizeExtension(attachment.fileExtension)
                leaf = "\(attachment.sha256).\(hashExt)"
                var suffix = 2
                while let owner = usedLeaf[leaf], owner != attachment.sha256 {
                    leaf = "\(attachment.sha256)-\(suffix).\(hashExt)"
                    suffix += 1
                }
            }
        }
        usedLeaf[leaf] = attachment.sha256
        leafByHash[attachment.sha256] = leaf
        return leaf
    }

    /// Last path component, control characters removed. Empty when the name is `.` or `..`.
    private static func originalLeaf(_ filename: String) -> String {
        var name = filename.replacingOccurrences(of: "\\", with: "/")
        if let slash = name.lastIndex(of: "/") {
            name = String(name[name.index(after: slash)...])
        }
        let filtered = String(name.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F })
        let trimmed = filtered.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "." || trimmed == ".." { return "" }
        return trimmed
    }

    /// ASCII file name safe for `ZipArchive` (`..`, `\`, and a leading `/` are rejected there).
    /// Spaces become `-`. Characters outside `[A-Za-z0-9._-]` are dropped.
    /// Anything left that still contains `..`, or an empty result, becomes `<sha256>.<ext>`.
    private static func asciiLeaf(_ attachment: NodeAttachment) -> String {
        let ext = AttachmentNames.normalizeExtension(attachment.fileExtension)
        let fallback = "\(attachment.sha256).\(ext)"
        let original = originalLeaf(attachment.filename)
        if original.isEmpty { return fallback }
        var folded = ""
        for scalar in original.unicodeScalars {
            guard scalar.isASCII else { continue }
            let character = Character(scalar)
            if character == " " {
                folded.append("-")
            } else if character.isLetter || character.isNumber || character == "." || character == "-" || character == "_" {
                folded.append(character)
            }
        }
        if folded.isEmpty || folded == "." || folded == ".." || folded.contains("..") || folded.hasPrefix(".") {
            return fallback
        }
        if !folded.contains("."), ext != "bin" {
            folded += ".\(ext)"
        }
        if folded.contains("..") { return fallback }
        return folded
    }

    private static func fileExtension(of leaf: String) -> String {
        guard let dot = leaf.lastIndex(of: "."), dot != leaf.startIndex else { return "" }
        return String(leaf[leaf.index(after: dot)...])
    }

    private static func markdownLabel(_ leaf: String) -> String {
        var output = ""
        for character in leaf {
            if character == "\\" || character == "[" || character == "]" {
                output.append("\\")
            }
            if character == "\n" || character == "\r" {
                output.append(" ")
            } else {
                output.append(character)
            }
        }
        return output
    }

    private static func markdownDestination(_ leaf: String) -> String {
        var encoded = ""
        for character in leaf {
            guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1, scalar.isASCII else {
                encoded.append(character)
                continue
            }
            let value = scalar.value
            let unreserved = (value >= 0x30 && value <= 0x39)
                || (value >= 0x41 && value <= 0x5A)
                || (value >= 0x61 && value <= 0x7A)
                || value == 0x2D || value == 0x2E || value == 0x5F || value == 0x7E
            if unreserved {
                encoded.append(character)
            } else {
                for byte in String(character).utf8 {
                    encoded += String(format: "%%%02X", byte)
                }
            }
        }
        return "assets/\(encoded)"
    }
}
