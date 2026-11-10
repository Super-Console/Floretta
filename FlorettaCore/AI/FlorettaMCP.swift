import CoreFoundation
import Foundation

/// MCP over stdio. One process, started by the client, exits when stdin closes.
/// Framing is `Content-Length`, or one JSON object. There is no socket and no resident helper.
public enum FlorettaMCP {
    public static let protocolVersion = "2024-11-05"
    public static let serverName = "floretta"

    /// Handles every complete message in `input` and returns the framed responses.
    /// An incomplete trailing message is ignored, the same as stdin closing mid-frame.
    public static func exchange(_ input: Data) -> Data {
        var buffer = input
        var output = Data()
        while let message = nextMessage(&buffer) {
            if let response = respond(to: message) {
                output.append(frame(response))
            }
        }
        return output
    }

    /// Reads MCP frames until `input` reaches EOF, then returns. Does not listen on a port.
    public static func serve(input: FileHandle, output: FileHandle) throws {
        var buffer = Data()
        while let chunk = try input.read(upToCount: 65_536), !chunk.isEmpty {
            buffer.append(chunk)
            while let message = nextMessage(&buffer) {
                if let response = respond(to: message) {
                    try output.write(contentsOf: frame(response))
                }
            }
        }
        while let message = nextMessage(&buffer) {
            if let response = respond(to: message) {
                try output.write(contentsOf: frame(response))
            }
        }
    }

    public static func respond(to message: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: message) as? [String: Any] else {
            return encode(error(id: nil, code: -32700, message: "Parse error"))
        }
        let id = object["id"]
        guard let method = object["method"] as? String else {
            if id == nil { return nil }
            return encode(error(id: id, code: -32600, message: "Invalid Request"))
        }
        let params = object["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String
            let version = (requested?.isEmpty == false) ? requested! : protocolVersion
            return encode(result(id: id, [
                "protocolVersion": version,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": serverName, "version": "1"],
            ]))
        case "ping":
            return encode(result(id: id, [:]))
        case "tools/list":
            return encode(result(id: id, ["tools": toolList()]))
        case "tools/call":
            return encode(call(id: id, params: params))
        case "notifications/initialized", "notifications/cancelled":
            return nil
        default:
            if id == nil { return nil }
            return encode(error(id: id, code: -32601, message: "Method not found"))
        }
    }

    static func frame(_ json: Data) -> Data {
        var data = Data("Content-Length: \(json.count)\r\n\r\n".utf8)
        data.append(json)
        return data
    }

    static func nextMessage(_ buffer: inout Data) -> Data? {
        while !buffer.isEmpty {
            trimLeadingSpace(&buffer)
            if buffer.isEmpty { return nil }
            switch headerMatch(buffer) {
            case .partial:
                return nil
            case .header:
                if let message = extractFramed(&buffer) { return message }
                return nil
            case .object:
                return extractObject(&buffer)
            case .junk:
                if let newline = buffer.firstIndex(of: 0x0A) {
                    buffer.removeSubrange(buffer.startIndex...newline)
                } else if buffer.count > 1024 {
                    buffer.removeAll()
                    return nil
                } else {
                    buffer.removeFirst()
                }
            }
        }
        return nil
    }

    private static func call(id: Any?, params: [String: Any]) -> [String: Any] {
        guard let name = params["name"] as? String else {
            return toolResult(id: id, text: "tools/call 缺少 name。", isError: true)
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        let result = FlorettaCommandLine.run(argumentsFor(tool: name, arguments: arguments))
        if result.servesMCP {
            return toolResult(id: id, text: "mcp 不能从工具里再启动。", isError: true)
        }
        if result.exitCode != 0 {
            let text = result.stderr.isEmpty ? "命令失败。" : result.stderr
            return toolResult(id: id, text: text, isError: true)
        }
        let text = result.stdout.isEmpty ? result.stderr : result.stdout + result.stderr
        return toolResult(id: id, text: text, isError: false)
    }

    private static func argumentsFor(tool: String, arguments: [String: Any]) -> [String] {
        let path = jsonString(arguments["path"]) ?? ""
        switch tool {
        case "tree":
            var argv = ["floretta", "tree", path]
            if let depth = jsonString(arguments["depth"]) { argv += ["--depth", depth] }
            return argv
        case "export":
            var argv = ["floretta", "export", path]
            if let format = jsonString(arguments["format"]) { argv += ["--format", format] }
            return argv
        case "node_get":
            return [
                "floretta", "node", "get", path,
                jsonString(arguments["address"]) ?? "",
                "--field", jsonString(arguments["field"]) ?? "",
            ]
        case "node_set":
            return [
                "floretta", "node", "set", path,
                jsonString(arguments["address"]) ?? "",
                "--field", jsonString(arguments["field"]) ?? "",
                "--value", jsonString(arguments["value"]) ?? "",
            ]
        case "node_add":
            var argv = ["floretta", "node", "add", path]
            if let parent = jsonString(arguments["parent"]) { argv += ["--parent", parent] }
            if let after = jsonString(arguments["after"]) { argv += ["--after", after] }
            if let text = jsonString(arguments["text"]) { argv += ["--text", text] }
            if let note = jsonString(arguments["note"]) { argv += ["--note", note] }
            if let link = jsonString(arguments["link"]) { argv += ["--link", link] }
            return argv
        case "node_delete":
            return ["floretta", "node", "delete", path, jsonString(arguments["address"]) ?? ""]
        case "node_move":
            var argv = [
                "floretta", "node", "move", path,
                "--from", jsonString(arguments["from"]) ?? "",
                "--to", jsonString(arguments["to"]) ?? "",
            ]
            if let index = jsonString(arguments["index"]) { argv += ["--index", index] }
            return argv
        default:
            return ["floretta", tool]
        }
    }

    private static func toolList() -> [[String: Any]] {
        [
            tool("tree", "列出树。Markdown 每行是 root/3/1 路径；.floretta 每行是 UUID。depth 从 1 起。", [
                "path": stringProp("文件路径"),
                "depth": ["type": "integer", "description": "列出的层数。根算 1 层。"],
            ], required: ["path"]),
            tool("node_get", "读取 text、note 或 link。Markdown 用路径，.floretta 用 UUID。", [
                "path": stringProp("文件路径"),
                "address": stringProp("root/3/1 或 UUID"),
                "field": stringProp("text、note 或 link"),
            ], required: ["path", "address", "field"]),
            tool("node_set", "写入一个字段并保存。Markdown 拒绝颜色、样式、附件、关系线、位置、左右侧和折叠态。", [
                "path": stringProp("文件路径"),
                "address": stringProp("root/3/1 或 UUID"),
                "field": stringProp("字段名"),
                "value": stringProp("新的值"),
            ], required: ["path", "address", "field", "value"]),
            tool("node_add", "插入子节点（parent）或同级（after）并保存。parent 为 root 时在森林末尾追加根。返回新地址。旧路径随之失效。", [
                "path": stringProp("文件路径"),
                "parent": stringProp("父路径、父 UUID，或 root"),
                "after": stringProp("插在这个节点后面"),
                "text": stringProp("节点文字"),
                "note": stringProp("备注"),
                "link": stringProp("链接"),
            ], required: ["path"]),
            tool("node_delete", "删除节点子树并保存。", [
                "path": stringProp("文件路径"),
                "address": stringProp("root/3/1 或 UUID"),
            ], required: ["path", "address"]),
            tool("node_move", "把 from 移到 to 下面。to 为 root 时变成根。index 是移动之后的兄弟下标，省略则追加。Markdown 返回新路径。", [
                "path": stringProp("文件路径"),
                "from": stringProp("要移动的节点"),
                "to": stringProp("新的父节点，或 root"),
                "index": ["type": "integer", "description": "兄弟下标"],
            ], required: ["path", "from", "to"]),
            tool("export", "导出文本，不改源文件。format=markdown 是标题预设；format=document 是嵌套列表文档。", [
                "path": stringProp("文件路径"),
                "format": stringProp("markdown 或 document"),
            ], required: ["path"]),
        ]
    }

    private static func tool(
        _ name: String,
        _ description: String,
        _ properties: [String: Any],
        required: [String]
    ) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": [
                "type": "object",
                "properties": properties,
                "required": required,
            ],
        ]
    }

    private static func stringProp(_ description: String) -> [String: Any] {
        ["type": "string", "description": description]
    }

    private static func toolResult(id: Any?, text: String, isError: Bool) -> [String: Any] {
        result(id: id, [
            "content": [["type": "text", "text": text]],
            "isError": isError,
        ])
    }

    private static func result(id: Any?, _ value: [String: Any]) -> [String: Any] {
        var object: [String: Any] = ["jsonrpc": "2.0", "result": value]
        if let id { object["id"] = id }
        return object
    }

    private static func error(id: Any?, code: Int, message: String) -> [String: Any] {
        var object: [String: Any] = [
            "jsonrpc": "2.0",
            "error": ["code": code, "message": message],
        ]
        if let id { object["id"] = id } else { object["id"] = NSNull() }
        return object
    }

    private static func encode(_ object: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func jsonString(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        if let text = value as? String { return text }
        guard let number = value as? NSNumber else { return nil }
        if CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() {
            return number.boolValue ? "true" : "false"
        }
        if number.doubleValue.rounded() == number.doubleValue, number.doubleValue.isFinite {
            return String(number.intValue)
        }
        return number.stringValue
    }

    private static func trimLeadingSpace(_ buffer: inout Data) {
        var index = buffer.startIndex
        while index < buffer.endIndex, buffer[index] == 0x20 || buffer[index] == 0x09
            || buffer[index] == 0x0A || buffer[index] == 0x0D {
            index = buffer.index(after: index)
        }
        if index > buffer.startIndex {
            buffer.removeSubrange(buffer.startIndex..<index)
        }
    }

    private enum HeaderMatch {
        case partial
        case header
        case object
        case junk
    }

    private static let headerName = Array("content-length:".utf8)

    private static func headerMatch(_ buffer: Data) -> HeaderMatch {
        if buffer.first == 0x7B { return .object }
        let count = min(buffer.count, headerName.count)
        for offset in 0..<count {
            let byte = buffer[buffer.index(buffer.startIndex, offsetBy: offset)]
            let folded = (byte >= 65 && byte <= 90) ? byte + 32 : byte
            if folded != headerName[offset] { return .junk }
        }
        return buffer.count < headerName.count ? .partial : .header
    }

    private static func extractFramed(_ buffer: inout Data) -> Data? {
        let crlf = Data("\r\n\r\n".utf8)
        let lf = Data("\n\n".utf8)
        let separator: Range<Data.Index>
        if let found = buffer.range(of: crlf) {
            separator = found
        } else if let found = buffer.range(of: lf) {
            separator = found
        } else {
            return nil
        }
        let header = buffer[..<separator.lowerBound]
        guard let headerText = String(data: Data(header), encoding: .utf8) else { return nil }
        var length: Int?
        for line in headerText.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0].lowercased() == "content-length", let value = Int(parts[1]), value >= 0 {
                length = value
            }
        }
        guard let length else {
            buffer.removeSubrange(buffer.startIndex..<separator.upperBound)
            return nil
        }
        let bodyStart = separator.upperBound
        guard buffer.distance(from: bodyStart, to: buffer.endIndex) >= length else { return nil }
        let bodyEnd = buffer.index(bodyStart, offsetBy: length)
        let body = Data(buffer[bodyStart..<bodyEnd])
        buffer.removeSubrange(buffer.startIndex..<bodyEnd)
        return body
    }

    private static func extractObject(_ buffer: inout Data) -> Data? {
        var depth = 0
        var inString = false
        var escaped = false
        var index = buffer.startIndex
        while index < buffer.endIndex {
            let byte = buffer[index]
            if inString {
                if escaped {
                    escaped = false
                } else if byte == 0x5C {
                    escaped = true
                } else if byte == 0x22 {
                    inString = false
                }
            } else if byte == 0x22 {
                inString = true
            } else if byte == 0x7B {
                depth += 1
            } else if byte == 0x7D {
                depth -= 1
                if depth == 0 {
                    let end = buffer.index(after: index)
                    let object = Data(buffer[buffer.startIndex..<end])
                    buffer.removeSubrange(buffer.startIndex..<end)
                    return object
                }
            }
            index = buffer.index(after: index)
        }
        return nil
    }
}
