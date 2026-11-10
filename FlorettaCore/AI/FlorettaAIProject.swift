import Foundation

/// Opens and saves one project.
///
/// `.md` / `.markdown` go only through `FlorettaMarkdownDocumentCodec`.
/// `.floretta` ZIP goes through `FlorettaStreamingDocument`. Plain JSON uses `FlorettaCodec`
/// and stays read-only on save, which is the existing container rule.
/// Heading-preset Markdown (`FlorettaMarkdown`) is not used here.
public enum FlorettaAIProjectFile {
    public static func open(
        _ url: URL,
        files: FileHandleStreamingFiles = FileHandleStreamingFiles()
    ) throws -> FlorettaAISession {
        guard files.fileExists(at: url) else {
            throw FlorettaAIError.message("找不到文件 \(url.path)。")
        }
        switch kind(of: url) {
        case .markdown:
            let opened = try FlorettaMarkdownDocumentCodec.open(try files.read(from: url))
            return FlorettaAISession(
                document: opened.document,
                mode: .markdown,
                container: .markdown,
                markdownWarnings: opened.warnings
            )
        case .floretta:
            if try files.isZip(at: url) {
                let reader = try files.openReader(at: url)
                do {
                    let opened = try FlorettaStreamingDocument.open(reader)
                    try reader.close()
                    return FlorettaAISession(
                        document: opened.document,
                        mode: .floretta,
                        container: .florettaZip
                    )
                } catch {
                    try? reader.close()
                    throw error
                }
            }
            let loaded = try FlorettaDocumentFile.read(data: try files.read(from: url))
            return FlorettaAISession(
                document: loaded.package.document,
                mode: .floretta,
                container: .florettaLegacy
            )
        case nil:
            throw FlorettaAIError.message("不支持的文件类型 \(url.pathExtension)。请使用 .md、.markdown 或 .floretta。")
        }
    }

    public static func save(
        _ session: FlorettaAISession,
        to url: URL,
        files: FileHandleStreamingFiles = FileHandleStreamingFiles()
    ) throws {
        switch session.container {
        case .markdown:
            let text = FlorettaMarkdownDocumentCodec.save(session.document)
            try files.write(Data(text.utf8), to: url)
        case .florettaZip:
            try FlorettaStreamingDocument.save(document: session.document, to: url, files: files)
        case .florettaLegacy:
            try FlorettaStreamingDocument.save(document: session.document, to: url, files: files)
        }
    }

    private enum Kind {
        case markdown
        case floretta
    }

    private static func kind(of url: URL) -> Kind? {
        switch url.pathExtension.lowercased() {
        case "md", "markdown":
            return .markdown
        case "floretta":
            return .floretta
        default:
            return nil
        }
    }
}
