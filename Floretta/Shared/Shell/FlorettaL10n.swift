import FlorettaCore
import Foundation

/// Chrome strings for the in-app language setting.
///
/// Keys are the Simplified Chinese source strings. `Localizable.xcstrings` is the
/// catalog that ships in both app bundles. Lookup uses that catalog when the
/// bundle has the compiled `.lproj`, and the table below otherwise. The table is
/// the same list, so a language change applies on the next view refresh without
/// restarting the process.
///
/// Document titles, node text, sticky text, relationship labels, and the default
/// map title「未命名」 are not keys. Callers must not pass user document strings through `string`.
enum FlorettaL10n {
    /// English is first so `Bundle.preferredLocalizations` treats it as the
    /// development language, matching the Xcode project.
    static let availableLocalizations = ["en", "zh-Hans"]

    static let english: [String: String] = [
        "最近": "Recent",
        "新建导图": "New Map",
        "本地导图": "On This Device",
        "从文件应用打开": "Open from the Files App",
        "从iCloud云盘打开": "Open from iCloud Drive",
        "从 iCloud 云盘打开": "Open from iCloud Drive",
        "我的 iPhone": "My iPhone",
        "我的 iPad": "My iPad",
        "我的 Mac": "My Mac",
        "首页": "Home",
        "设置": "Settings",
        "语言": "Language",
        "跟随系统": "Follow System",
        "简体中文": "Simplified Chinese",
        "外观": "Appearance",
        "浅色": "Light",
        "深色": "Dark",
        "新建时默认视图": "Default View for New Maps",
        "地图模式": "Map",
        "聚焦模式": "Focus",
        "PNG 导出倍率": "PNG Export Scale",
        "PNG 背景": "PNG Background",
        "白色": "White",
        "透明": "Transparent",
        "导出包含便签": "Include Stickies in Export",
        "PNG 和 PDF 可以带上便签。关掉后便签还在导图里，只是不画进图片。": "PNG and PDF can include stickies. Turning this off leaves them in the map and omits them from the picture.",
        "关于": "About",
        "版本": "Version",
        "版本 %@": "Version %@",
        "NOTICE 开源致谢": "NOTICE Acknowledgments",
        "搜索": "Search",
        "模板库": "Templates",
        "打开": "Open",
        "这里还没有导图。": "No maps here yet.",
        "现在是创建一个好的时机。": "This is a good time to make one.",
        "新建": "New",
        "关闭": "Close",
        "返回": "Back",
        "iCloud 云盘不可用。": "iCloud Drive isn't available.",
        "iCloud云盘": "iCloud Drive",
        "提示": "Notice",
        "好": "OK",
        "确定": "OK",
        "取消": "Cancel",
        "恢复上一版": "Restore Previous",
        "丢弃未完成的写入": "Discard Incomplete Write",
        "恢复": "Recover",
        "丢弃": "Discard",
        "要恢复未保存的导图吗？": "Recover unsaved mind map?",
        "发现了一份未保存的导图。": "An unsaved mind map was found.",
        "要恢复「%@」吗？": "Recover \"%@\"?",
        "无法恢复自动保存": "Couldn't Recover Autosave",
        "自动保存读不出来。": "The autosave could not be read.",
        "重新命名": "Rename",
        "名称": "Name",
        "为这份导图重新命名": "Rename this map",
        "返回导图列表": "Back to maps",
        "无法导出": "Couldn't Export",
        "无法打开": "Couldn't Open",
        "无法保存": "Couldn't Save",
        "无法恢复": "Couldn't Restore",
        "无法预览": "Couldn't Preview",
        "保存未完成": "Save Didn't Finish",
        "放入附件？": "Add Attachment?",
        "放入": "Add",
        "查找": "Find",
        "文字": "Text",
        "没有找到。": "No matches.",
        "大纲": "Outline",
        "子节点": "Child",
        "同级": "Sibling",
        "语音输入": "Dictation",
        "用系统听写新建子节点。正在编辑或选中自由节点时，听写写进当前文字。": "Dictate a new child with system dictation. While editing, or when a free topic is selected, dictation goes into the current text.",
        "自由节点": "Free Topic",
        "便签": "Sticky Note",
        "连到": "Link To",
        "图片": "Image",
        "附件": "Attachment",
        "从文件导入": "Import from File",
        "插入": "Insert",
        "适应窗口": "Fit Window",
        "分享": "Share",
        "存入节点": "Save to Topic",
        "链接": "Link",
        "文件": "File",
        "把链接、文字或图片存进指定主题。": "Save a link, text, or picture onto a chosen topic.",
        "更多": "More",
        "样式": "Style",
        "查看模式": "View Mode",
        "新建画布": "New Canvas",
        "粘贴": "Paste",
        "打印": "Print",
        "全屏沉浸": "Zen",
        "撤销": "Undo",
        "重做": "Redo",
        "删除": "Delete",
        "剪切": "Cut",
        "拷贝": "Copy",
        "全选": "Select All",
        "拷贝样式": "Copy Style",
        "完成": "Done",
        "排序": "Reorder",
        "检查器": "Inspector",
        "演说": "Presentation",
        "导图": "Map",
        "尚未实现": "Not Available Yet",
        "附件合计": "Attachments",
        "文档大小": "Document Size",
        "引用": "References",
        "节点": "Topics",
        "关系": "Relationships",
        "主题": "Topic",
        "形状": "Shape",
        "矩形": "Rectangle",
        "圆角": "Rounded",
        "胶囊": "Capsule",
        "无边框": "No Border",
        "填充样式": "Fill",
        "实心": "Solid",
        "无": "None",
        "填充颜色": "Fill Color",
        "长度": "Length",
        "边框": "Border",
        "实线": "Solid Line",
        "宽度": "Width",
        "颜色": "Color",
        "文本": "Text",
        "字体": "Font",
        "系统": "System",
        "衬线": "Serif",
        "圆体": "Rounded",
        "等宽": "Monospaced",
        "大小": "Size",
        "选择一个主题": "Select a Topic",
        "样式会写进导图文件。": "Styles are saved in the map file.",
        "还没有连到其他节点。": "Not linked to another topic yet.",
        "没有其他节点": "No other topics",
        "黄色": "Yellow",
        "粉色": "Pink",
        "绿色": "Green",
        "蓝色": "Blue",
        "橙色": "Orange",
        "缺失的节点": "Missing Topic",
        "保存为 Floretta": "Save as Floretta",
        "进入全屏沉浸模式，暂时只留下导图": "Enter zen mode and leave only the map",
        "退出沉浸模式，恢复工具栏": "Exit zen mode and restore the toolbar",
        "撤销上一步编辑": "Undo the last edit",
        "恢复刚刚撤销的编辑": "Redo the edit that was just undone",
        "删除选中的节点、便签、关系、概要或边界": "Delete the selected topic, sticky, relationship, summary, or boundary",
        "在选中的节点下新建一个子节点": "Add a child under the selected topic",
        "在选中的节点旁新建一个同级节点": "Add a sibling beside the selected topic",
        "在画布上放一个不进层级的节点，位置会保存": "Place a topic on the canvas outside the hierarchy. Its position is saved.",
        "在画布上放一张便签。最多五种颜色，不计入节点，可以拖动，大小有上限": "Place a sticky on the canvas. Up to five colors. It is not a topic, it can be dragged, and its size is limited.",
        "把选中的节点连到另一个节点，画布上会画出这条线。": "Link the selected topic to another topic. The canvas draws the line.",
        "编辑这条关系的标签": "Edit the label on this relationship",
        "标签": "Label",
        "从文件选择一张图片放进选中的节点": "Choose an image file to put in the selected topic",
        "把一个文件原样放进选中的节点": "Put a file into the selected topic as-is",
        "从文件打开另一份导图": "Open another map from a file",
        "插入子节点、同级、语音输入、自由节点、便签、概要、边界、图片、附件，或从文件导入": "Insert a child, sibling, dictation, free topic, sticky, summary, boundary, image, or attachment, or import from a file",
        "概要": "Summary",
        "边界": "Boundary",
        "为选中的节点生成概要，并画出括住它的括号": "Add a summary for the selected topic and draw a bracket around it",
        "用边界圈住选中的节点": "Draw a boundary around the selected topic",
        "编辑概要文字": "Edit the summary text",
        "编辑边界标题": "Edit the boundary title",
        "标题": "Title",
        "把画布缩放到 %lld%%": "Zoom the canvas to %lld%%",
        "让整张导图缩进窗口里": "Fit the whole map in the window",
        "选择缩放比例，或让导图适应窗口": "Choose a zoom level, or fit the map in the window",
        "把这份导图导出为 PDF": "Export this map as PDF",
        "把这份导图导出为 PNG 图片": "Export this map as a PNG image",
        "把这份导图导出为 Markdown": "Export this map as Markdown",
        "把这份导图保存为 Floretta 文件": "Save this map as a Floretta file",
        "把这份导图导出为 FreeMind .mm": "Export this map as FreeMind .mm",
        "把这份导图导出为 OPML": "Export this map as OPML",
        "导出为 XMind，自由节点写成浮动主题": "Export as XMind. Free topics become floating topics.",
        "打印这份导图": "Print this map",
        "把导图导出为 PDF、PNG、Markdown，或保存为已支持的文件": "Export the map as PDF, PNG, or Markdown, or save it as a supported file",
        "打开或关闭左侧大纲": "Show or hide the outline",
        "打开样式检查器，修改选中节点的外观": "Open the style inspector and change the selected topic",
        "用整张地图查看导图": "Show the whole map",
        "只看当前选中的这一支": "Show only the selected branch",
        "在地图模式和聚焦模式之间切换": "Switch between map and focus",
        "在这份导图里再加一个中心主题": "Add another central topic to this map",
        "按文字或标签查找节点": "Find a topic by its text or label",
        "把剪贴板里的图片放进节点；没有图片时粘贴文字": "Put a clipboard image into a topic. If there is no image, paste text.",
        "查看版本号和开源致谢": "Show the version and open-source notices",
        "大纲、样式、配色、标签筛选、版本历史和关于": "Outline, style, colors, tag filter, version history, and about",
        "版本历史": "Version History",
        "查看已保存的历史版本，回滚或对比两份内容。": "See saved versions, roll back, or compare two of them.",
        "Markdown 文件不保留版本快照。": "Markdown files don't keep version snapshots.",
        "当前": "Current",
        "历史版本": "Earlier Versions",
        "第 %lld 版": "Version %lld",
        "%lld 个主题": "%lld topics",
        "回滚": "Roll Back",
        "回滚到第 %lld 版？": "Roll back to version %lld?",
        "回滚到这一版": "Roll back to this version",
        "当前这份会先写入历史，再换成所选版本。工具栏的撤销不能退回这次替换。要回到刚才的内容，再从历史里选那一版。": "The current map is saved into history first, then replaced by the version you picked. Undo in the toolbar does not reverse this. To get the current map back, pick that version from history.",
        "对比": "Compare",
        "和当前这份比较": "Compare with the current map",
        "左边": "Left",
        "右边": "Right",
        "这两份的文字和结构没有差别。": "These two have the same text and structure.",
        "还没有历史版本。再保存一次之后，上一版会出现在这里。": "No earlier versions yet. After the next save, the previous one shows up here.",
        "每一行的对比是和当前比较。进入对比后可以改选任意两版。": "Compare on a row is against the current map. Inside Compare you can pick any two versions.",
        "新增 %lld，删去 %lld，修改 %lld": "Added %lld, removed %lld, changed %lld",
        "新增": "Added",
        "删去": "Removed",
        "修改": "Changed",
        "无法读取历史版本": "Couldn't Read Version History",
        "无法回滚": "Couldn't Roll Back",
        "找不到这一版。": "That version isn't there.",
        "备注": "Note",
        "子节点顺序": "Child order",
        "位置": "Place",
        "标签筛选": "Filter by Tag",
        "给选中的主题加上优先级、进度、旗帜或标签，并按标签高亮": "Add priority, progress, a flag, or a label to the selected topic, and highlight by tag",
        "标记": "Markers",
        "优先级": "Priority",
        "进度": "Progress",
        "旗帜": "Flag",
        "优先级 %lld": "Priority %lld",
        "未开始": "Not Started",
        "1/8": "1/8",
        "1/4": "1/4",
        "3/8": "3/8",
        "1/2": "1/2",
        "5/8": "5/8",
        "3/4": "3/4",
        "7/8": "7/8",
        "红旗": "Red Flag",
        "橙旗": "Orange Flag",
        "黄旗": "Yellow Flag",
        "绿旗": "Green Flag",
        "蓝旗": "Blue Flag",
        "紫旗": "Purple Flag",
        "灰旗": "Gray Flag",
        "添加标签": "Add Label",
        "移除标签": "Remove Label",
        "筛选": "Filter",
        "搜索标签": "Search Tags",
        "清除筛选": "Clear Filter",
        "这张导图还没有标签。": "This map has no tags yet.",
        "匹配的主题会高亮，其余变淡。": "Matching topics stay bright. The rest fade.",
        "正在筛选「%@」": "Filtering “%@”",
        "配色": "Colors",
        "为各分支自动配色，浅色和深色各用一套": "Colors each branch automatically. Light and dark each have a set.",
        "墨色": "Ink",
        "海色": "Sea",
        "林色": "Grove",
        "焰色": "Ember",
        "暮色": "Dusk",
        "陶色": "Clay",
        "花色": "Bloom",
        "岩色": "Slate",
        "让大纲占满或恢复原来的宽度": "Make the outline fill the window, or restore its width",
        "关闭大纲": "Close the outline",
        "剪下选中节点的文字": "Cut the selected topic's text",
        "复制选中节点的文字": "Copy the selected topic's text",
        "选中当前节点里的全部文字": "Select all text in the current topic",
        "复制选中节点的填充颜色": "Copy the selected topic's fill color",
        "不能放入文件夹。": "Folders can't be added.",
        "没有可以放入的文件。": "There is no file to add.",
        "先把导图存成文件。": "Save the map as a file first.",
        "没有可以放入附件的节点。": "There is no topic that can hold an attachment.",
        "没有导出图片。": "No image was exported.",
        "没有导出 PDF。": "No PDF was exported.",
        "没有可打印的内容。": "There is nothing to print.",
        "无法打开最近文件。": "The recent file couldn't be opened.",
        "不支持的文件类型 %@。": "Unsupported file type %@.",
        "这份还是旧的 JSON 文件，不能直接覆盖。请用「保存为 Floretta」另存。": "This is still an old JSON file and can't be overwritten. Use Save as Floretta.",
        "导出已按最大尺寸裁切，超出的内容没有画进文件。": "The export was clipped to the maximum size. Content past that edge is not in the file.",
        "没有可导出的节点。": "There are no topics to export.",
        "这个文件已经不在，预览已关闭。": "This file is gone, so the preview was closed.",
        "无法打开预览。": "The preview couldn't be opened.",
        "上次写入中断了，没有替换已经保存的导图。恢复上一版会丢掉未完成的半截文件，留下上一个完整版本。": "The last write was interrupted and did not replace the saved map. Restoring the previous version discards the incomplete file and keeps the last complete one.",
        "上次写入中断了，当前文件打不开。可以恢复快照里的上一版。只存在于损坏文件里的附件，打开时会按文件名指出。": "The last write was interrupted and the current file won't open. You can restore the previous snapshot. Attachments that exist only in the damaged file are named when it opens.",
        "上次写入中断了，没有可恢复的上一版。未完成的半截文件会被丢掉。": "The last write was interrupted and there is no previous version to restore. The incomplete file will be discarded.",
        "附件已损坏": "Attachment Damaged",
        "有 1 个附件和 sha256 清单不一致。这不是整份导图读失败。": "1 attachment does not match the sha256 inventory. The map itself was read.",
        "有 %lld 个附件和 sha256 清单不一致。这不是整份导图读失败。": "%lld attachments do not match the sha256 inventory. The map itself was read.",
        "内容与 sha256 不符（实际 %@）。": "The contents do not match sha256 (actual %@).",
        "包内没有这个附件。": "This attachment is not in the package.",
        "读取中断，没能算完 sha256。": "The read was interrupted before sha256 finished.",
        "被压缩了，不能按原字节核对 sha256。": "It is compressed, so sha256 can't be checked against the original bytes.",
        "条目名不是 assets/<sha256>.<ext>。": "The entry name is not assets/<sha256>.<ext>.",
        "内容和包内声明的校验不符。": "The contents do not match the checksum declared in the package.",
        "文件大小：%@": "File size: %@",
        "放入后文档大约：%@": "Document size after adding: %@",
        "字节原样放进当前项目，不压缩、不转码。": "The bytes are stored as-is. Nothing is compressed or transcoded.",
        "超过 10GB 软上限。": "This is over the 10GB soft limit.",
        "结构": "Structure",
        "分析": "Analysis",
        "记录": "Notes",
        "左右思维导图": "Mind Map",
        "逻辑分解": "Logic Tree",
        "括号图": "Brace Map",
        "组织架构": "Org Chart",
        "里程碑": "Timeline",
        "鱼骨图": "Fishbone",
        "优劣势四象限": "SWOT",
        "方案对照": "Comparison",
        "目标树": "OKR Tree",
        "七何分析": "Seven Questions",
        "会议记录": "Meeting Notes",
        "读书笔记": "Reading Notes",
        "保存": "Save",
        "Markdown 模式": "Markdown Mode",
        "本文件只保存层级与文字；不含附件、颜色、关系线、自由位置与折叠态。": "This file only saves hierarchy and text. It does not include attachments, colors, relationships, free positions, or collapse state.",
        "Markdown 模式无法保存附件": "Markdown Mode can't save attachments",
        "Markdown 模式无法保存颜色": "Markdown Mode can't save colors",
        "Markdown 模式无法保存关系线": "Markdown Mode can't save relationships",
        "Markdown 模式无法保存自由位置": "Markdown Mode can't save free positions",
        "Markdown 模式无法保存折叠态": "Markdown Mode can't save collapse state",
        "Markdown 模式无法保存便签": "Markdown Mode can't save sticky notes",
        "Markdown 模式无法保存概要": "Markdown Mode can't save summaries",
        "Markdown 模式无法保存边界": "Markdown Mode can't save boundaries",
        "Markdown 模式无法保存标签": "Markdown Mode can't save tags",
        "升级为完整工程": "Upgrade to full project",
        "把当前导图另存为 Floretta 工程。原来的 Markdown 文件不会被改掉。": "Save this map as a Floretta project. The Markdown file is left as it is.",
        "要打开新的 Floretta 文件吗？": "Open the new Floretta file?",
        "保持当前 Markdown": "Keep this Markdown file",
        "打开新的 Floretta 文件": "Open the new Floretta file",
        "升级后的文件已保存。当前 Markdown 仍打开着。": "The upgraded file is saved. This Markdown file stays open.",
        "关闭提示": "Dismiss notice",
        "不能覆盖原来的 Markdown 文件。": "The original Markdown file can't be overwritten.",
        "已将 *、+ 或有序列表标记规范为无序列表（- ）。": "Markers *, +, and ordered lists were read as unordered lists (- ).",
        "已将 Tab 缩进按 1 个 Tab = 2 个空格规范化。": "Tab indents were read as two spaces per tab.",
    ]

    private final class BundleToken {}
    static let bundle = Bundle(for: BundleToken.self)

    static func localizationIdentifier(
        for language: AppLanguage,
        preferences: [String] = Locale.preferredLanguages
    ) -> String {
        switch language {
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        case .system:
            return Bundle.preferredLocalizations(
                from: availableLocalizations,
                forPreferences: preferences
            ).first ?? "en"
        }
    }

    static func catalogID(
        for locale: Locale,
        preferences: [String] = Locale.preferredLanguages
    ) -> String {
        let code = locale.language.languageCode?.identifier ?? ""
        if code == "en" { return "en" }
        if code == "zh" {
            if locale.language.script?.identifier == "Hant" {
                let prefs = [locale.identifier] + preferences
                return Bundle.preferredLocalizations(
                    from: availableLocalizations,
                    forPreferences: prefs
                ).first ?? "zh-Hans"
            }
            return "zh-Hans"
        }
        return Bundle.preferredLocalizations(
            from: availableLocalizations,
            forPreferences: preferences
        ).first ?? "en"
    }

    static func string(
        _ key: String,
        language: AppLanguage,
        preferences: [String] = Locale.preferredLanguages,
        bundle: Bundle = FlorettaL10n.bundle
    ) -> String {
        resolve(
            key,
            localization: localizationIdentifier(for: language, preferences: preferences),
            bundle: bundle
        )
    }

    static func string(
        _ key: String,
        locale: Locale,
        preferences: [String] = Locale.preferredLanguages,
        bundle: Bundle = FlorettaL10n.bundle
    ) -> String {
        resolve(
            key,
            localization: catalogID(for: locale, preferences: preferences),
            bundle: bundle
        )
    }

    static func format(
        _ key: String,
        language: AppLanguage,
        preferences: [String] = Locale.preferredLanguages,
        arguments: [CVarArg]
    ) -> String {
        let id = localizationIdentifier(for: language, preferences: preferences)
        let template = resolve(key, localization: id, bundle: bundle)
        return String(format: template, locale: Locale(identifier: id), arguments: arguments)
    }

    static func format(
        _ key: String,
        locale: Locale,
        preferences: [String] = Locale.preferredLanguages,
        arguments: [CVarArg]
    ) -> String {
        let id = catalogID(for: locale, preferences: preferences)
        let template = resolve(key, localization: id, bundle: bundle)
        return String(format: template, locale: Locale(identifier: id), arguments: arguments)
    }

    /// Translates a stored alert when it is a catalog key. User filenames inside
    /// the unsupported-type sentence stay as they were. Unknown text is returned
    /// unchanged so a system error or a document title is not rewritten.
    static func present(_ message: String, locale: Locale) -> String {
        if message.isEmpty { return "" }
        let prefix = "不支持的文件类型 "
        let suffix = "。"
        if message.hasPrefix(prefix), message.hasSuffix(suffix), message.count > prefix.count + suffix.count {
            let name = String(message.dropFirst(prefix.count).dropLast(suffix.count))
            return format("不支持的文件类型 %@。", locale: locale, arguments: [name])
        }
        if message.contains("\n") {
            return message.split(separator: "\n", omittingEmptySubsequences: false).map { line in
                string(String(line), locale: locale)
            }.joined(separator: "\n")
        }
        return string(message, locale: locale)
    }

    static func attachmentConfirmation(_ proposal: AttachmentInsertProposal, locale: Locale) -> String {
        var lines = [
            format("文件大小：%@", locale: locale, arguments: [AttachmentByteFormat.label(proposal.fileByteCount)]),
            format("放入后文档大约：%@", locale: locale, arguments: [AttachmentByteFormat.label(proposal.projectedDocumentByteCount)]),
            string("字节原样放进当前项目，不压缩、不转码。", locale: locale),
        ]
        if proposal.exceedsSoftCap {
            lines.append(string("超过 10GB 软上限。", locale: locale))
        }
        return lines.joined(separator: "\n")
    }

    static func inventoryMessage(_ error: AssetInventoryError, locale: Locale) -> String {
        let header: String
        if error.failures.count == 1 {
            header = string("有 1 个附件和 sha256 清单不一致。这不是整份导图读失败。", locale: locale)
        } else {
            header = format(
                "有 %lld 个附件和 sha256 清单不一致。这不是整份导图读失败。",
                locale: locale,
                arguments: [Int64(error.failures.count)]
            )
        }
        let lines = error.failures.map { failure in
            "· \(failure.filename)（\(failure.entryName)）\(reasonText(failure, locale: locale))"
        }
        return ([header] + lines).joined(separator: "\n")
    }

    static func reasonText(_ failure: AssetCorruption, locale: Locale) -> String {
        switch failure.reason {
        case .hashMismatch(let actual):
            return format("内容与 sha256 不符（实际 %@）。", locale: locale, arguments: [actual])
        case .missingFromPackage:
            return string("包内没有这个附件。", locale: locale)
        case .unreadable:
            return string("读取中断，没能算完 sha256。", locale: locale)
        case .compressed:
            return string("被压缩了，不能按原字节核对 sha256。", locale: locale)
        case .malformedName:
            return string("条目名不是 assets/<sha256>.<ext>。", locale: locale)
        case .declaredChecksumMismatch:
            return string("内容和包内声明的校验不符。", locale: locale)
        }
    }

    static func recoveryMessage(title: String?, locale: Locale) -> String {
        if let title, !title.isEmpty {
            return format("要恢复「%@」吗？", locale: locale, arguments: [title])
        }
        return string("发现了一份未保存的导图。", locale: locale)
    }

    private static func resolve(_ key: String, localization: String, bundle: Bundle) -> String {
        if let bundled = bundledString(key, localization: localization, bundle: bundle) {
            return bundled
        }
        if localization == "en", let translated = english[key] {
            return translated
        }
        return key
    }

    /// Same table `String(localized:locale:)` reads from the compiled catalog.
    /// A missing English entry falls through to the in-memory copy so the setting still applies.
    private static func bundledString(_ key: String, localization: String, bundle: Bundle) -> String? {
        guard let path = bundle.path(forResource: localization, ofType: "lproj"),
              let table = Bundle(path: path) else { return nil }
        let missing = "\u{0}"
        let value = table.localizedString(forKey: key, value: missing, table: "Localizable")
        if value == missing { return nil }
        if localization == "en", value == key, let translated = english[key], translated != key {
            return nil
        }
        return value
    }
}
