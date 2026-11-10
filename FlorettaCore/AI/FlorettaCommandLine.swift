import Foundation

/// Result of one CLI invocation. `servesMCP` is the stdio server; the library call does not block on stdin.
public struct FlorettaCommandResult: Equatable, Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    public var servesMCP: Bool

    public init(exitCode: Int32, stdout: String = "", stderr: String = "", servesMCP: Bool = false) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.servesMCP = servesMCP
    }
}

/// `floretta tree`, `floretta node add`, `floretta export`, and the matching read/write commands.
/// The process entry point and the MCP server both call this. It does not open a socket.
public enum FlorettaCommandLine {
    public static let help = """
    floretta tree <file> [--depth N]
    floretta node add <file> (--parent <addr> | --after <addr>) [--text T] [--note N] [--link URL]
    floretta node get <file> <addr> --field text|note|link
    floretta node set <file> <addr> --field <field> --value <text>
    floretta node delete <file> <addr>
    floretta node move <file> --from <addr> --to <parent> [--index N]
    floretta export <file> [--format markdown|document] [--output <path>]
    floretta mcp

    .md 用路径 root/3/1（0 起）。插入、删除、移动后路径失效，要按当前树重算。临时 UUID 不是地址。
    .floretta 用稳定 UUID。root 只表示森林，用来追加根或把节点移成根。
    export 的 markdown 是标题预设（分享/导出）。document 才是打开/保存 .md 的嵌套列表。
    mcp 从标准输入读 MCP，往标准输出写，不监听网络，标准输入关闭后退出。

    """

    public static func run(_ arguments: [String]) -> FlorettaCommandResult {
        let args = Array(arguments.dropFirst())
        guard let command = args.first else {
            return FlorettaCommandResult(exitCode: 0, stdout: help)
        }
        do {
            switch command {
            case "help", "--help", "-h":
                return FlorettaCommandResult(exitCode: 0, stdout: help)
            case "mcp":
                return FlorettaCommandResult(exitCode: 0, servesMCP: true)
            case "tree":
                return try tree(parse(Array(args.dropFirst())))
            case "export":
                return try export(parse(Array(args.dropFirst())))
            case "node":
                return try node(Array(args.dropFirst()))
            default:
                return failure("未知命令 \(command)。\n" + help)
            }
        } catch {
            return failure(describe(error))
        }
    }

    private static func node(_ args: [String]) throws -> FlorettaCommandResult {
        guard let sub = args.first else {
            return failure("node 后面要接 add、get、set、delete 或 move。\n" + help)
        }
        let parsed = try parse(Array(args.dropFirst()))
        switch sub {
        case "add":
            return try nodeAdd(parsed)
        case "get":
            return try nodeGet(parsed)
        case "set":
            return try nodeSet(parsed)
        case "delete":
            return try nodeDelete(parsed)
        case "move":
            return try nodeMove(parsed)
        default:
            return failure("未知的 node 子命令 \(sub)。\n" + help)
        }
    }

    private static func tree(_ options: Options) throws -> FlorettaCommandResult {
        guard let file = options.positional.first else { return failure("tree 需要文件路径。\n" + help) }
        let session = try FlorettaAIProjectFile.open(URL(fileURLWithPath: file))
        let depth = try options.int("depth")
        if let depth, depth < 1 { return failure("depth 从 1 起。") }
        return success(session.tree(depth: depth), warnings: session.markdownWarnings)
    }

    private static func export(_ options: Options) throws -> FlorettaCommandResult {
        guard let file = options.positional.first else { return failure("export 需要文件路径。\n" + help) }
        let session = try FlorettaAIProjectFile.open(URL(fileURLWithPath: file))
        let format = options.value("format") ?? "markdown"
        let text: String
        switch format {
        case "markdown":
            text = session.exportHeadingMarkdown()
        case "document":
            text = session.exportDocumentMarkdown()
        default:
            return failure("未知导出格式 \(format)。用 markdown 或 document。")
        }
        if let output = options.value("output") {
            try FileHandleStreamingFiles().write(Data(text.utf8), to: URL(fileURLWithPath: output))
            return success("", warnings: session.markdownWarnings)
        }
        return success(text, warnings: session.markdownWarnings)
    }

    private static func nodeAdd(_ options: Options) throws -> FlorettaCommandResult {
        guard let file = options.positional.first else { return failure("node add 需要文件路径。\n" + help) }
        let parent = options.value("parent")
        let after = options.value("after")
        if (parent == nil) == (after == nil) {
            return failure("node add 要带 --parent 或 --after，只能选一个。")
        }
        var session = try FlorettaAIProjectFile.open(URL(fileURLWithPath: file))
        let text = options.value("text") ?? ""
        let note = options.value("note") ?? ""
        let link = options.value("link")
        let address: String
        if let parent {
            address = try session.insertChild(under: parent, text: text, note: note, link: link)
        } else if let after {
            address = try session.insertSibling(after: after, text: text, note: note, link: link)
        } else {
            return failure("node add 要带 --parent 或 --after，只能选一个。")
        }
        try FlorettaAIProjectFile.save(session, to: URL(fileURLWithPath: file))
        return success(address + "\n", warnings: session.markdownWarnings)
    }

    private static func nodeGet(_ options: Options) throws -> FlorettaCommandResult {
        guard options.positional.count >= 2 else { return failure("node get 需要文件路径和地址。\n" + help) }
        guard let fieldName = options.value("field"), let field = FlorettaAIField.parse(fieldName) else {
            return failure("node get 需要 --field text、note 或 link。")
        }
        let session = try FlorettaAIProjectFile.open(URL(fileURLWithPath: options.positional[0]))
        let value = try session.get(field, at: options.positional[1])
        return success(value + "\n", warnings: session.markdownWarnings)
    }

    private static func nodeSet(_ options: Options) throws -> FlorettaCommandResult {
        guard options.positional.count >= 2 else { return failure("node set 需要文件路径和地址。\n" + help) }
        guard let fieldName = options.value("field"), let field = FlorettaAIField.parse(fieldName) else {
            return failure("node set 需要 --field。")
        }
        guard let value = options.value("value") else { return failure("node set 需要 --value。") }
        let url = URL(fileURLWithPath: options.positional[0])
        var session = try FlorettaAIProjectFile.open(url)
        let address = try session.set(field, at: options.positional[1], value: value)
        try FlorettaAIProjectFile.save(session, to: url)
        return success(address + "\n", warnings: session.markdownWarnings)
    }

    private static func nodeDelete(_ options: Options) throws -> FlorettaCommandResult {
        guard options.positional.count >= 2 else { return failure("node delete 需要文件路径和地址。\n" + help) }
        let url = URL(fileURLWithPath: options.positional[0])
        var session = try FlorettaAIProjectFile.open(url)
        try session.delete(at: options.positional[1])
        try FlorettaAIProjectFile.save(session, to: url)
        return success("", warnings: session.markdownWarnings)
    }

    private static func nodeMove(_ options: Options) throws -> FlorettaCommandResult {
        guard let file = options.positional.first else { return failure("node move 需要文件路径。\n" + help) }
        guard let from = options.value("from"), let to = options.value("to") else {
            return failure("node move 需要 --from 和 --to。")
        }
        let index = try options.int("index")
        let url = URL(fileURLWithPath: file)
        var session = try FlorettaAIProjectFile.open(url)
        let address = try session.move(from: from, to: to, index: index)
        try FlorettaAIProjectFile.save(session, to: url)
        return success(address + "\n", warnings: session.markdownWarnings)
    }

    private struct Options {
        var positional: [String]
        var values: [String: String]

        func value(_ name: String) -> String? { values[name] }

        func int(_ name: String) throws -> Int? {
            guard let raw = values[name] else { return nil }
            guard let number = Int(raw) else {
                throw FlorettaAIError.message("\(name) 要是整数。")
            }
            return number
        }
    }

    private static func parse(_ args: [String]) throws -> Options {
        var positional: [String] = []
        var values: [String: String] = [:]
        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg == "--" {
                positional.append(contentsOf: args[(index + 1)...])
                break
            }
            if arg.hasPrefix("--") {
                let body = String(arg.dropFirst(2))
                if body.isEmpty { throw FlorettaAIError.message("空的选项。") }
                if let eq = body.firstIndex(of: "=") {
                    let name = String(body[..<eq])
                    values[name] = String(body[body.index(after: eq)...])
                } else if index + 1 < args.count, !args[index + 1].hasPrefix("--") {
                    values[body] = args[index + 1]
                    index += 1
                } else {
                    throw FlorettaAIError.message("选项 --\(body) 缺少值。")
                }
            } else {
                positional.append(arg)
            }
            index += 1
        }
        return Options(positional: positional, values: values)
    }

    private static func success(
        _ stdout: String,
        warnings: [FlorettaMarkdownDocumentWarning]
    ) -> FlorettaCommandResult {
        let notice = warnings.map(\.message).joined(separator: "\n")
        let stderr = notice.isEmpty ? "" : notice + "\n"
        return FlorettaCommandResult(exitCode: 0, stdout: stdout, stderr: stderr)
    }

    private static func failure(_ message: String) -> FlorettaCommandResult {
        let text = message.hasSuffix("\n") ? message : message + "\n"
        return FlorettaCommandResult(exitCode: 1, stderr: text)
    }

    private static func describe(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let text = localized.errorDescription {
            return text
        }
        return error.localizedDescription
    }
}
