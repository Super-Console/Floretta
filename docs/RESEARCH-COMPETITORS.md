# Floretta 竞品调研：思维导图工具的附件能力与功能边界

- 调研日期：2026-11-09
- 调研对象：XMind（macOS/iPadOS/iOS）、幕布、MindNode、MindManager、iThoughts、SimpleMind、FreeMind、Freeplane、markmap、mind-elixir、markmind
- 判断标准：功能是否直接服务于「把想法画成思维导图」。凡不服务于该动作的扩展，一律归入「不做」。
- 方法：只采信官方帮助文档、官方定价页、官方仓库与作者公告；第三方页面仅用于补充官方页未渲染的数字，并明确标注。查不到的写「未确认」。

---

## 0. 结论摘要

1. **「插入任意文件」在桌面端是老功能，不是新功能**：XMind、MindManager、iThoughts 都把文件副本嵌进文档容器，点击后交给系统默认程序打开；没有任何一家在**节点上**做应用内文件渲染（XMind 官方原文如此，幕布的内嵌预览是文档级）。Floretta 的 `assets/<sha256>.<ext>` 与之同构，属于已经被验证的容器设计。
2. **「插入已录好的音频」几乎是空白**：XMind 只有「Audio Note」录音（仅桌面端），官方文档没有任何导入已有音频的入口；幕布能上传 MP3 并在线播放，但附件是**文档级**而非节点级。Floretta 把音频作为节点附件并内嵌播放，是真实差异点。
3. **预览能力比「能不能存」更能区分产品**：幕布做到了 pdf/docx/pptx/xlsx/csv/md/txt/mp3/mp4 的双栏在线预览，XMind 只做「导出到本地 → 系统程序打开」。附件体验的竞争点在预览层，不在存储层。
4. **自包含 vs 外置目录是两条路线**：XMind/MMAP/ITMZ 都是「单文件 ZIP 内含附件」，Freeplane 是「.mm + 同级 `_files/` 目录」。后者被自家社区明确批评为「移动地图要连目录一起搬」。Floretta 的单文件 ZIP 路线正确。
5. **格式互操作的通用货币是 OPML / FreeMind .mm / Markdown**，不是 .xmind。.xmind 没有可访问的官方规范页（XMind GitHub wiki 链接已 404），但官方提供了 MIT 许可的 Swift/JS SDK，第三方解析器大量存在，事实上可读写。
6. **iThoughts 已于 2024-01-30 停止运营**，FreeMind 停在 2014 年的 1.0.1。这两家只剩「格式遗产」价值，不应作为功能标杆。

---

## 1. 产品概览表

| 产品 | 平台 | 价格模式 | 核心交互特点 | 独有能力 | 文件格式与互操作 |
|---|---|---|---|---|---|
| **XMind** | 桌面 Windows/macOS/Linux；移动 iOS/iPadOS/Android；Web | 订阅：Free（限 10 张在线地图）/ Pro US$4.92/月起（年付）/ Premium US$8.25/月起；App Store 年付 Pro US$59 | 大纲与导图同构、结构模板多、主题精美；附件/编号等属 Pro | 多结构布局（逻辑图/时间轴/鱼骨等）、Pitch 演示、AI、实时协作 | 原生 `.xmind`（ZIP：content.json + metadata.json + manifest.json + Thumbnails + resources）；导入 EdrawMind/MindManager/FreeMind/MindNode/DOCX/Markdown/OPML；导出 PNG/SVG/PDF/Excel/Word/OPML/TextBundle/PPT/Markdown |
| **幕布** | Windows/macOS/Android/iOS/Web | 免费 + 高级会员 ¥12/月、¥108/年（App Store 内购价）；超级会员 ¥199–299/年 | 大纲优先，一键切导图；Tab/Shift+Tab 缩进 | 文档级附件 + 双栏在线预览（含 MP3/MP4）；全平台同步免费 | 导入 XMind/FreeMind/OPML/Markdown；导出大纲 Word/PDF/Markdown/图片/HTML/OPML，导图 PDF/图片/FreeMind |
| **MindNode** | Mac/iPhone/iPad/Vision Pro/Watch（Apple 独占） | 免费 + Plus US$2.99/月、US$24.99/年 | 极简视觉、节点像卡片、手势操作 | 与 Apple 生态深度整合（Image Playground、去背景、Watch） | 原生 Next/Classic；导入 MindNode/纯文本/RTF/DOCX(mac)/Markdown/TextBundle/FreeMind/iThoughts/OPML/XMind；导出 PDF/SVG/PNG/Markdown/Text/FreeMind/OPML |
| **MindManager** | 桌面 Windows/macOS；Web；Teams；移动端仅 Go 查看器 | Essentials（Web）US$99/年；Professional 约 US$169–179/年（第三方价格页）；另有买断版 | 企业级信息图、任务/资源视图 | 附件嵌入、任务与项目视图、SharePoint/Teams 集成、协同编辑 | 原生 `.mmap`（ZIP + Document.xml + attachments/ + images/）；可导入 Word/OPML 等，`.xmind` 由 XMind 单向导入（反向未确认） |
| **iThoughts** | iOS/iPadOS、macOS、Windows（**2024-01-30 停止运营**） | 原为买断制（已无法购买/续期） | 信息密度高、格式支持最广 | 格式转换近乎万能（30+ 导入导出组合） | 原生 `.itmz`（ZIP + XML + 附件）；导入/导出 XMind8、MindManager、FreeMind、OPML、Markdown、DOCX、PPTX、PDF、PNG 等 |
| **SimpleMind** | Mac/Windows/iPad/iPhone/Android | 免费版（移动端）+ Pro 买断：Mac US$29.99、iOS US$9.99 | 自由布局 + 自动布局，轻量 | 结构极简、跨平台买断、无账号 | 原生 `.smmx`；导入 ITMZ/OPML/TXT/FreeMind；导出 PDF/PNG/HTML/TXT/FreeMind/OPML |
| **FreeMind** | Windows/macOS/Linux（Java） | 免费开源 | 键盘驱动、节点折叠 | 历史格式 `.mm` 的源头 | 原生 `.mm`（XML）；导出 HTML/PDF/PNG（其他格式未逐项核实） |
| **Freeplane** | Windows/macOS/Linux（Java，FreeMind 分支） | 免费开源 | 节点属性/脚本/公式，可编程性强 | Groovy 脚本、条件样式、外部对象 | 原生 `.mm`（XML 扩展）+ 同级 `_files/` 目录；导入 FreeMind/OPML/Text/Markdown |
| **markmap** | 浏览器 / VS Code / CLI（库） | 免费开源（MIT） | Markdown 即导图，标题与列表变分支 | 一个 HTML 文件离线可用；SVG/Canvas 双渲染器 | 输入 Markdown；输出交互 HTML、SVG、PNG；无自有文档格式 |
| **mind-elixir** | 浏览器（JS 库） | 免费开源（MIT） | 面向开发者的可嵌入导图组件 | 数据即 JSON、插件化、可深度定制 | 输入/输出 JSON；无文件容器概念 |
| **markmind** | Obsidian 插件（依赖 Obsidian 桌面/移动端） | 免费版 + 付费版 | 导图/大纲/PDF 标注三合一 | 把 PDF 标注与节点双向关联 | 数据存 Markdown + JSON；导出 HTML/PDF；无附件容器 |

补充说明：

- XMind 平台矩阵来自官方用户指南（桌面三平台）与移动端页面：<https://xmind.com/user-guide/intro-new>、<https://xmind.app/mobile/ios>；价格来自 <https://xmind.com/pricing>（页面按年/月切换，Pro 年付折算 US$4.92/月；App Store 年付 US$59 见 <https://apps.apple.com/us/app/id1327661892>）。
- 幕布平台与价格：<https://mubu.com/about-pro>（「低至 ¥5.5/月起」为长周期折算）、App Store 内购价 <https://apps.apple.com/cn/app/id6736676944>。
- MindNode Plus 价格与「图片/贴纸属于 Plus」：<https://www.mindnode.com/pricing>。
- MindManager 平台矩阵（Desktop Windows & Mac / Web / Teams / Go 移动查看）：<https://www.mindmanager.com/en/pricing/>；Go 仅查看：<https://kb.mindmanager.com/en/125550>。官方定价页数字未渲染，US$169 来自 G2 <https://www.g2.com/products/mindmanager/pricing>，US$179 来自 <https://pricingsaas.com/companies/mindmanager>，均为第三方，属「未由官网确认」。
- iThoughts 停运公告（作者本人，2024-01-30）：「toketaWare has ceased trading」<https://www.toketaware.com/>。
- SimpleMind Pro Mac US$29.99：<https://simplemind.eu/download/full-edition>；iOS US$9.99 来自 App Store 页面摘要，未逐项核对地区价。
- FreeMind 最后正式版 1.0.1（2014-04-12）：<https://freemind.sourceforge.io/wiki/index.php/Download>；后续仅 1.1.0 Beta2（2016）。
- markmap 特性（富内容含图片、SVG/Canvas、导出 SVG/PNG）：<https://github.com/markmap/markmap>。

---

## 2. 附件与媒体专题（重点）

### 2.1 能力总表

| 产品 | 图片 | 任意文件 | 视频 | 音频（插入已有文件） | 存储方式 | 应用内预览 | 导出/分享时附件去向 |
|---|---|---|---|---|---|---|---|
| XMind | ✅ 内嵌渲染 | ✅ Attachment | ⚠️ 仅作为附件，无内嵌播放 | ❌ 只有录音 Audio Note | 嵌入 `.xmind` 的 resources | ❌ 导出到本地后用系统默认程序打开 | PDF/PNG/SVG 只渲染图片；附件不随这些格式输出 |
| 幕布 | ✅（有大小/画质分级） | ✅ **文档级**，非节点级 | ✅ MP4 在线播放 | ✅ MP3 在线播放 | 云端对象存储 | ✅ 双栏/全屏，支持 9 种格式 | 附件不随导出的 Word/PDF 走（帮助页未提供附件导出） |
| MindNode | ✅（Plus） | ❌ | ❌ | ❌ | 嵌入文档包 | ✅ 图片直接渲染 | Markdown 导出可选 TextBundle 带图 |
| MindManager | ✅ | ✅ Attach Files | ⚠️ 仅附件 | ⚠️ 仅附件 | 嵌入 `.mmap` 的 attachments/ | 未确认（推测为外部打开） | PDF 只含可见内容；`.mmap` 保留 |
| iThoughts | ✅ | ✅ 副本嵌入 ITMZ | ⚠️ 仅附件 | ⚠️ 仅附件 | 嵌入 `.itmz` | ✅ 应用内可查看文档 | 转其他格式会丢失附件（官方称转换有损） |
| SimpleMind | ✅ 嵌入 `.smmx` | ❌ 只能链接 | ❌ | ❌ | 嵌入 `.smmx` | ✅ 图片渲染 | 导出 `.mm`/`.opml` 明确丢弃图片 |
| Freeplane | ✅ | ✅ 外部对象 | ⚠️ 外部对象 | ⚠️ 外部对象 | **同级 `_files/` 目录** | ✅ 节点内显示，双击外部编辑 | 拷走 `.mm` 不带目录就会丢 |
| FreeMind | ⚠️ 外链引用 | ❌ | ❌ | ❌ | 仅路径引用 | ✅ 若路径有效 | 换机器即断图 |
| markmap | ⚠️ Markdown 图片语法（URL） | ❌ | ❌ | ❌ | 无（HTML 内引用） | ✅ 浏览器渲染 | 导出的 HTML 依赖外部图片地址 |
| mind-elixir | ✅ `image.url` | ❌ | ❌ | ❌ | 数据内 URL / data URL | ✅ 由宿主渲染 | 取决于宿主实现 |
| markmind | ⚠️ Markdown 语法 | ❌ | ❌ | ❌ | Obsidian 附件目录 | ✅ Obsidian 渲染 | 依赖 vault 内相对路径 |

图例：✅ 原生支持；⚠️ 只能变通；❌ 不支持。

### 2.2 逐家事实与出处

**XMind**

- 附件定义与交互：官方原文「Attachments enable you to insert another mind map or a variety of file formats. Once inserted, the attachment becomes a new topic that can be previewed by simply clicking on it.」——插入后**变成一个子主题**，不是挂在节点上的角标。查看时「Xmind, with your permission, will save the attachment locally and open it through the system's default application」。<https://xmind.com/user-guide/attachment-new>
- 也就是说：XMind 不做应用内附件渲染，PDF/PSD/视频全部交给系统程序。这对 Floretta 是明确的差异化空间。
- 音频：只有 Audio Note，且是**录音**入口——「Click the record button to start」，产物是子主题、可播放；文档明确写「Xmind for desktop supports voice recording」，移动端不支持。<https://xmind.com/user-guide/audio-note-new>。官方没有任何「导入已有音频」的说明 → 结论：**不支持插入已录好的音频**（作为普通附件插入 MP3 可以，但那是文件附件，不是音频节点）。
- 图片：属于主题富内容，与贴纸、标记、备注并列。<https://xmind.com/user-guide/enrich-a-topic>
- 移动端同样能加附件：「You can attach a file or another mind map... The attachment will become a new topic」<https://xmind.app/mobile/ios>。
- 附件是付费功能：Pro 档权益里写明「Keep ideas connected with links, numbering & attachments」<https://xmind.com/pricing>。
- 文件体积上限：官方文档未给出任何单附件大小或总容量限制 → **未确认**。可确认的是附件随文档一起进 ZIP（第三方格式说明列 `resources/` 为附件目录：<https://file-extensions.com/docs/xmind>）。

**幕布**

- 附件是**文档级**而非节点级：入口在「文档标题下方的『上传文件』」，上传后在「文件」列表里预览，可把预览窗放到文档上/下/左/右，可拖拽改大小、可全屏。<https://mubu.com/help/139>
- 支持预览的格式：pdf、docx/doc、pptx、markdown、txt、xlsx/csv、**mp3、mp4**。这正是「插入一段已录好的音频」的竞品参照，但它是文档侧栏播放，不是节点内播放。
- 数量与配额：单文档附件 1 个（免费）/ 10 个（高级、超级）；存储 1G/50G/200G；图片上传 ≤15MB（免费，压缩画质）/ ≤50MB（会员，高清原图）。<https://mubu.com/help/56>
- 附件随云端同步，不随导出文件走：帮助页的导出清单只有 Word/PDF/Markdown/图片/HTML/OPML/Freemind，没有「带附件导出」→ 附件留在云端账户里。<https://mubu.com/help/30>
- 图片功能与付费的关系有版本差异：较早的会员协议把「文档插入图片」列为高级版权益 <https://mubu.com/purchaseAgreement>；现行会员表则按上传规格分级（免费 15MB 压缩画质 / 会员 50MB 高清原图）<https://mubu.com/help/56>。以现行表格为准。

**MindNode**

- 官方「媒体」只有三类：贴纸、Emoji、照片（可从相册导入或直接拍照）。<https://www.mindnode.com/support/guides/stickers-emojis-and-photos>
- 没有任意文件附件。旧版 MindNode 2 for Mac 曾支持「把任意文件拖到备注，生成别名（Alias）」——那是 macOS 别名/链接，不是嵌入副本。<https://www.mindnode.com/blog/linking-files>
- 图片属 Plus 权益（免费版不含 Images/Emojis/Stickers）。<https://www.mindnode.com/pricing>
- 导出 Markdown 时可选择「include images in a TextBundle」，即图片能随 TextBundle 走；PDF/SVG/PNG 自然含图。<https://www.mindnode.com/support/guides/import-and-export>

**MindManager**

- 附件是原生功能（Home 选项卡的 Attach Files），.mmap 是 ZIP，内含 `Document.xml`、`attachments/`、`images/`。<https://file-extensions.com/docs/mmap>
- 官方用户指南明确给出体积策略：「map size, use links to point to the documents instead of attaching them. Links do not increase the size of your map significantly」——即**嵌入会让地图变大，官方建议大文件改用链接**。<https://www.mindmanager.com/static/mm/docs/MindManager_2017_User_Guide_EN.pdf>
- 移动端只有 MindManager Go，定位是查看/筛选/搜索，不是编辑 <https://kb.mindmanager.com/en/125550>。附件在移动端能否打开：未确认。

**iThoughts**

- 附件机制最接近 Floretta 的目标形态：「That is a COPY of the document is embedded within the map ITMZ file itself.」可挂在**主题**或**主题备注**两处；macOS/Windows 拖放时按住 Option/Alt 即嵌入；iOS 走「拷贝到 iThoughts → 粘贴」。
- 作者对 ITMZ 的描述：「The ITMZ file is just a ZIP file containing an XML file and any attachments/images.」<https://www.toketaware.com/>
- 代价是互操作有损：导入第三方格式时「If an attribute is not recognised by iThoughts then it is simply ignored」，且多页/多画布只导入第一页，其余丢弃。<https://www.toketaware.com/ithoughts-faq-compatibility>
- 2024-01-30 停止运营，无 bug 修复，未来系统升级可能失效。<https://www.toketaware.com/>

**SimpleMind**

- 图片可加到主题（免费版也含「Add images, icons, labels」）<https://simplemind.eu/features-pricing/>。
- 文件只能**链接**：官方特性写作「Add links to documents or webpages」，不是嵌入。<https://simplemind.eu/features-pricing/>
- 导出明确降级：「It is possible to share as basic Freemind (.mm) or opml... Any additional information, such as images will be discarded.」<https://simplemind.eu/faq/share-export-in-different-formats>
- 导入支持 `.itmz/.opml/.txt/.mm`，其中 ITMZ 会保留图片与备注 <https://simplemind.eu/faq/what-files-can-simplemind-import>。

**Freeplane**

- 图片/文件以「外部对象」插入（Insert > External object），插入时可选文件并带预览；插入后可缩放、双击恢复原始大小、双击打开外部编辑器。<https://docs.freeplane.org/attic/old-mediawiki-content/External_objects.html>
- 存储位置是硬伤：粘贴图片会在 `.mm` 同目录生成 `<地图名>_files/` 文件夹，图片存在那里；改存新文件名会再生成一个 `_files`，搬地图必须连文件夹一起搬。这是社区用户原话。<https://github.com/freeplane/freeplane/discussions/2076>
- 结论：Freeplane 的地图**不是自包含文档**，与 Floretta 的 ZIP 容器是相反路线。

**FreeMind**

- 图片是引用而非嵌入（外部图片路径）；FreeMind wiki 的「Bitmap images (development)」页讨论过「把图片以二进制存进 XML」的方案，说明当时并未实现。最后正式版 1.0.1（2014-04-12），此后仅 beta。<https://freemind.sourceforge.io/wiki/index.php/Download>
- 无附件功能，只有超链接。

**markmap**

- 定位是「Markdown → 交互导图」，节点内容就是 Markdown/HTML，官方特性列「Rich content: bold, links, code, highlights, task lists, **images** and math」。图片靠 URL，不存在附件容器；导出的单文件 HTML 会引用外部图片地址。<https://github.com/markmap/markmap>
- 无视频/音频的一等支持（可手写 HTML 标签，但不是产品能力）。

**mind-elixir**

- 节点结构里图片是一个对象：`image?: { url: string; width: number; height: number }`，宽高必填；`url` 可为 http 或 data URL。<https://docs.mind-elixir.com/docs/guides/node-data>
- 另有 `dangerouslySetInnerHTML`，理论上能塞 `<video>/<audio>`，但这是库的逃生口，不是附件模型。无文件、无音频字段。

**markmind**

- 是 Obsidian 插件，数据存 Markdown（basic 模式）或 Markdown 内嵌 JSON（rich 模式）；PDF 以 `[[]]` 链接打开并做标注，标注存 `annos` 或 `-annotate.md`。<https://www.markmind.net/cn/docs>
- 无附件容器，无音视频。

### 2.3 横向结论

1. **三种存储范式**：(a) 单文件容器内嵌（XMind `.xmind`、MindManager `.mmap`、iThoughts `.itmz`）；(b) 旁挂目录（Freeplane `_files/`）；(c) 仅链接（MindNode 旧版别名、SimpleMind、FreeMind）。Floretta 的 `assets/<sha256>.<ext>` 属于 (a)，是主流商业产品的一致选择。
2. **没有一家做「节点级 + 应用内渲染任意文件」**。XMind 明确外抛给系统程序；幕布能做内嵌预览，但附件挂文档不挂节点。这两件事的交集是空的——Floretta 若做「节点附件 + QuickLook 内嵌预览」，位置是独特的。
3. **音频是最大空白**。XMind 只有录音器；幕布只有文档级 MP3 播放；其余全无。用户要的「插入已录好的音频」在主流产品里没有对应功能。
4. **体积处理普遍是「警告 + 建议外链」而不是「自动优化」**：MindManager 官方直接建议大文件用链接；幕布用配额和上传分级（15MB 压缩 / 50MB 原图）硬控；XMind 未公开策略。没有一家公开做附件去重（sha256）或按需解压。
5. **导出即降级是行业默认**：除原生格式外，附件一律不跟随。iThoughts 甚至明说转换有损。Floretta 需要在 UI 上把「导出 PDF 不含附件」讲清楚，否则用户会认为丢数据。

### 2.4 对 Floretta 的直接启示

- 图片必须**内嵌原件 + 节点内渲染**，并生成缩略图缓存；原图与缩略图分离，避免每次滚动都解码大图。
- 任意文件应当**节点级**，用 UTType 图标 + 文件名 + 大小做角标，点击走 QuickLook（macOS `QLPreviewPanel`，iOS `QLPreviewController`）。
- 音频应当是**节点级一等公民**：AVKit 播放条 + 时长 + 可选波形；这与「录音机」是两个功能，不要合并。
- 视频同理：可播放但不必转码；用 AVPlayer 直接播原文件，体积问题用「导入时提示」而非「偷偷转码」。
- 自动去重（sha256 已是容器约定）应体现在「同一文件插入两次不翻倍」，这是竞品都没做的低成本差异点。

---

## 3. 格式互操作专题

### 3.1 导入/导出矩阵

| 产品 | 可导入 | 可导出 |
|---|---|---|
| XMind | EdrawMind、MindManager、FreeMind、MindNode、Word(DOCX)、Markdown、OPML、TextBundle 等 | PNG、SVG、PDF、Excel、Word、OPML、TextBundle、PowerPoint、Markdown |
| 幕布 | XMind、FreeMind、OPML、Markdown | 大纲：Word/PDF/Markdown/图片/HTML/OPML；导图：PDF/图片/FreeMind |
| MindNode | MindNode Next/Classic、纯文本、RTF、DOCX(仅 mac)、Markdown、TextBundle、FreeMind、iThoughts、OPML、XMind | MindNode Next/Classic、PDF、SVG、FreeMind、OPML、PNG、Markdown、Text |
| MindManager | Word、OPML 等（未见 .xmind 导入） | `.mmap`、PDF、PNG、Word、OPML、HTML 等 |
| iThoughts | 20+ 种（含 XMind8/2021、MindManager v6+、FreeMind、MindNode、SimpleMind、OPML、Markdown、CSV、Scapple） | 20+ 种（含 XMind8、MindManager、FreeMind、OPML、DOCX、PPTX、PDF、PNG、Markdown、TextPack） |
| SimpleMind | `.itmz`、`.opml`、`.txt`、`.mm` | `.smmx`、PDF、PNG、HTML、TXT、`.mm`、`.opml` |
| FreeMind | `.mm`（原生；其他导入格式未逐项核实） | `.mm`、HTML、PDF、PNG |
| Freeplane | FreeMind `.mm`、OPML、文本、Markdown（是否支持 XMind 导入未确认） | `.mm`、PDF、PNG、SVG、HTML、OPML、Markdown |
| markmap | Markdown | HTML、SVG、PNG |
| mind-elixir | JSON | JSON（导出图片由宿主实现） |
| markmind | Markdown/JSON（Obsidian 内） | HTML、PDF、Markdown |

出处：XMind 导入 <https://xmind.com/user-guide/import-new>、导出 <https://xmind.com/user-guide/export-new>；幕布 <https://mubu.com/help/30>；MindNode <https://www.mindnode.com/support/guides/import-and-export>；iThoughts <https://www.toketaware.com/ithoughts-faq-compatibility>；SimpleMind 导入 <https://simplemind.eu/faq/what-files-can-simplemind-import>、导出 <https://simplemind.eu/faq/share-export-in-different-formats>；markmap <https://github.com/markmap/markmap>。

### 3.2 公开规范与第三方读写

| 格式 | 容器/结构 | 是否有公开规范 | 第三方读写现状 |
|---|---|---|---|
| `.xmind` | ZIP：`content.json`（旧版 `content.xml`）+ `metadata.json` + `manifest.json` + `Thumbnails/thumbnail.png` + `resources/`（附件） | **无正式规范文档**。XMind 官方 GitHub wiki 的 XMindFileFormat 页面已 404 | 官方提供 MIT 许可 SDK（Swift：<https://github.com/xmindltd/xmind-sdk-swift>；JS：<https://github.com/xmindltd/xmind-sdk-js>）；第三方解析器如 simple-mind-map 的 xmind 模块 <https://wanglin2.github.io/mind-map-docs/en/api/xmind.html>；MindNode、iThoughts、幕布均能导入 |
| `.mmap` | ZIP：`Document.xml` + `[Content_Types].xml` + `attachments/` + `images/` | 否，专有 XML schema | XMind、iThoughts 可导入；无公开写库 |
| `.itmz` | ZIP：XML + 附件/图片 | 作者称「relatively open」，无规范文件 | 仅 iThoughts 系与少数迁移工具 |
| `.mm` | 单文件 XML | 部分：FreeMind wiki 有格式说明，Freeplane 在其上扩展 | 几乎所有导图工具都读写（事实标准） |
| `.smmx` | 包格式（ZIP + XML，schema 未公开） | 否 | 仅 SimpleMind 系 |
| Markdown / OPML | 纯文本 / XML | 是（公开） | 全行业通用 |

要点：

- **`.xmind` 是「事实开放、规范缺位」**：容器结构简单到任何语言几十行就能解析，官方 SDK 也开源（MIT），但没有一份可引用的正式 spec（wiki 页 404 实测）。这对 Floretta 是机会也是风险：可以低成本实现导入，但需自行处理旧版 `content.xml` 与多画布。
- **多画布是导入的常见陷阱**：iThoughts 明确只取第一页、其余丢弃 <https://www.toketaware.com/ithoughts-faq-compatibility>；Floretta 若导入 .xmind，需要明确「只取第一张画布」还是「拆成多个文档」。
- **真正的互通货币是 OPML / FreeMind / Markdown**：这三者所有产品都支持，且能保住层级与文本；图片与样式必然丢失。Floretta 的互操作优先级应是「先保结构，再谈样式」。

---

## 4. 同步与协作（Floretta 暂不做，仅供知己知彼）

| 产品 | 同步方式 | 实时协作 | 账号要求 |
|---|---|---|---|
| XMind | 自有云（Xmind 账号）；文件也可存本地 | ✅ Premium 起「Collaborate in real time」，Business 面向团队 | 云功能需账号；本地文件不需要 |
| 幕布 | 自有云，全平台同步对免费用户开放 | 分享链接为主；实时共同编辑未确认 | 需账号 |
| MindNode | iCloud/CloudKit，端到端存于用户自己的 iCloud | ✅ Plus 含 Collaboration（基于 iCloud 共享） | 需 iCloud |
| MindManager | 本地文件 + SharePoint/OneDrive/Teams | ✅ Professional 起 Co-editing | 协作需企业账号体系 |
| iThoughts | iCloud Drive / Dropbox / WebDAV 文件夹 | ❌ 无实时协作 | 无自有账号 |
| SimpleMind | iCloud Drive / Dropbox / OneDrive / Google Drive 文件夹 | ❌ 无实时协作 | 无账号 |
| Freeplane | 本地文件；靠网盘同步 | ❌ 无；有第三方 freeplane-collab 做「离线编辑 + 事后同步」 | 无 |
| FreeMind | 本地文件 | ❌ | 无 |
| markmap / mind-elixir / markmind | 无（文件/宿主负责） | ❌ | 无 |

出处：XMind <https://xmind.com/pricing>；MindNode <https://www.mindnode.com/support/guides/how-does-mindnode-store-documents-in-the-cloud>、<https://www.mindnode.com/pricing>；MindManager <https://www.mindmanager.com/en/pricing/>；SimpleMind <https://simplemind.eu/faq/save-and-sync-mind-maps>；Freeplane 协作插件 <https://freeplanecollab.sourceforge.net>。

值得注意的结构性事实：**本地优先的产品（iThoughts、SimpleMind、Freeplane、FreeMind）全部没有实时协作**，它们用「网盘同步文件」代替协作。这说明「本地优先 + 不登录」与「实时协作」在产品上确实是两条路，Floretta 选择前者并不算缺失，而是选了一个已被验证的阵营（代价是放弃团队场景的收入）。

---

## 5. 按用户边界筛选

### 5.1 直接服务「画思维导图」——值得做

| 功能 | 理由 | 竞品参照 |
|---|---|---|
| 节点内插入图片（内嵌原件 + 渲染 + 缩放） | 图片是导图最常用的表达单元，缺它等于不能画完整的图 | XMind、MindNode、SimpleMind、幕布全部有 |
| 节点级任意文件附件（PDF/PSD/工程文件） | 「这张图的源文件在哪」是创作型导图的真实需求；Floretta 的 assets 容器已为此设计 | XMind、MindManager、iThoughts 有；但都外抛打开 |
| 节点级音频（插入已有录音 + 播放） | 直接扩展「节点能承载的信息类型」，且是竞品空白 | 无直接竞品；幕布仅文档级 MP3 |
| 节点级视频（插入 + 播放） | 同上，教程/素材类导图需要 | 无（都只能当附件外抛） |
| 附件预览（QuickLook / PDFKit / AVKit） | 预览决定「插入后是否还敢用」；XMind 外抛是体验断点 | 幕布做得最好（双栏） |
| 附件角标与元信息（类型图标、文件名、大小） | 没有标识，用户不知道节点里有什么 | 各家都有 paperclip/图标 |
| 附件去重与体积提示（sha256 天然去重） | 防止同一 PSD 被插十次导致文档爆炸 | 无人做，低成本差异点 |
| 导入 .xmind / .mm / OPML / Markdown | 迁移门槛决定能否从竞品拉人 | 全行业标配 |
| 导出 PDF / PNG / SVG / Markdown / OPML | 交付与分享的基本盘 | 全行业标配 |
| 多画布/多页支持 | XMind 有 Sheet，iThoughts 因不支持而被诟病；画大图必然需要 | XMind、MindManager |

### 5.2 与思维导图无关——不做

| 功能 | 不做的理由 |
|---|---|
| AI 生成导图 / AI 总结 / 会议纪要转写 | 不改变「画」的动作，属于内容生产，且需要联网与账号，与「本地优先、不联网」直接冲突 |
| 实时协作 / 评论 / 团队空间 | 需要服务端、账号、权限体系；本地优先产品阵营（iThoughts/SimpleMind/Freeplane）全部没有，验证了这不是必需 |
| 云同步 / 跨设备账号 | 同上；文件放 iCloud Drive 已能解决 80% 需求，且不引入账号 |
| 甘特图 / 任务指派 / 日历导出 | XMind 把它放在 Premium 拉企业收入，但那是项目管理，不是画图 |
| 演示模式（Pitch/Slides） | 把导图当 PPT 用，是另一个交付场景；会牵出大量排版与动画工作 |
| 内置录音机 | 用户明确只要「插入已录好的音频」；录音涉及权限、后台、音频会话管理，成本高且非核心 |
| 网页剪藏 / 稍后读 / 素材库 | 内容采集，不是画图 |
| 模板商店 / 贴纸商店 / 主题市场 | 美术资产运营，个人开发者不应背 |
| 公式（LaTeX）/ 表格节点 | 有价值但属「内容表达」的边缘；先把附件与结构做扎实 |
| Windows / Android 客户端 | 三端 Apple 已覆盖目标用户；跨平台会拖垮 UI 一致性 |
| 账号体系 / 订阅计费 | 与「不登录」冲突，买断或 App Store 内购足够 |

### 5.3 灰色地带（先留接口，不先做）

- **多画布**：数据结构上应预留（`sheets[]`），UI 第一版可以只做单画布。理由：后加会动文档格式，先加只是隐藏入口。
- **附件批量管理面板**（看所有附件、清理孤儿文件）：数据结构支持即可，UI 可后置。
- **链接型附件**（只存路径不存副本）：与「自包含」冲突，建议不做；若做，必须显式标注「此文件未随文档保存」。

---

## 6. 附件类功能的实现难度与工作量估计

### 6.1 假设

- 1 人日 = 6 小时有效编码时间；开发者熟悉 SwiftUI + 少量 AppKit/UIKit 互操作。
- 不含视觉设计、不含 App Store 审核与文案。
- 已有基础：ZIP 容器、`document.json`、`assets/<sha256>.<ext>`、节点树模型、基本画布渲染。
- 估算为「一次做对」的区间，不含返工；跨端（macOS/iOS/iPadOS）按一套代码复用计，平台差异单独列。

### 6.2 分解

| 工作项 | 人日 | 说明 |
|---|---|---|
| 附件数据模型 + assets 写入/读取 + sha256 去重 + 引用计数 | 2–3 | 含「删除节点后孤儿文件回收」策略；这是所有后续功能的地基 |
| 图片插入三条入口（文件选择 / 拖放 / 剪贴板粘贴） | 3–4 | iOS 需 PhotosPicker + onDrop + UIPasteboard 三套 |
| 图片渲染与布局（等比缩放、节点尺寸重算、导出时分辨率） | 3–4 | 画布性能敏感，需异步解码 |
| 缩略图生成 + 磁盘缓存 + 懒加载 | 3 | 决定滚动流畅度；macOS 用 CGImageSource，iOS 用 ImageIO |
| 任意文件附件（UTType 识别、图标、元数据、导入校验） | 3 | 含 PSD 等无系统图标的兜底 |
| QuickLook 预览（macOS QLPreviewPanel / iOS QLPreviewController） | 3–4 | 两端 API 差异大；需处理「预览中文件被删除」 |
| 音频节点（AVKit 播放条、时长读取、播放状态、后台音频会话） | 4–6 | 含 AVAsset 元数据、锁屏控制可后置 |
| 视频节点（AVPlayer、首帧缩略图、全屏） | 3–4 | 与音频共用播放层可省 1–2 天 |
| 附件 UI（节点角标、右键菜单、替换/另存为/删除、拖出） | 5 | 交互细节最多的一块；macOS 拖出到 Finder 是刚需 |
| 导出链路（PDF/PNG 渲染图片、TextBundle 带图、`.floretta` 含全部附件） | 4–6 | 需保证「导出 PDF 不含附件」有明确提示 |
| 导入链路（.xmind 图片提取、.mm 外链图片降级、Markdown 图片下载/跳过） | 5–7 | .xmind 旧版 content.xml + 多画布是主要坑 |
| 体积与性能（单附件阈值提示、总大小显示、后台压缩选项） | 3–4 | 不做自动转码，只做提示与可选压缩 |
| 测试（大文件、iCloud 备份排除、iPad 分屏、低内存） | 3 | 附件类 bug 多在内存与路径 |
| **合计（完整版）** | **44–56** | 上表各项相加 |
| **MVP（图片 + 任意文件 + QuickLook + 角标，无音视频/导入导出）** | **22–26** | 数据模型 + 图片三入口 + 渲染 + 缩略图 + 文件附件 + QuickLook + 附件 UI |
| **音视频增量** | **7–10** | 音频 4–6 + 视频 3–4，共用播放层可取下限 |

### 6.3 三档交付建议

1. **MVP（约 4–5 周）**：图片 + 任意文件 + QuickLook + 角标 + 去重 + 图片随 PDF/PNG 导出。这已覆盖 XMind 桌面端的附件能力，且预览体验更好。
2. **差异化档（再加 1.5–2 周）**：音频 + 视频节点内播放。这是竞品空白，也是用户最在意的点。
3. **互操作档（再加 1.5–2 周）**：.xmind 导入（含图片提取）+ OPML/Markdown 导入导出。用来承接迁移用户。

### 6.4 主要风险

- **画布性能**：附件缩略图若同步解码，100 节点以上会掉帧；必须异步 + 缓存，这部分估算已含，但容易低估。
- **导出语义**：用户会默认「导出 PDF 应该带上我的 PSD」，需要在导出面板明确写清，否则是差评来源。
- **iCloud 备份**：大附件会让 App 备份体积暴涨，应把 assets 标记为「不备份」或提供开关（未在估算内，约 +1 人日）。
- **.xmind 导入**：无正式规范，旧版 `content.xml` 与多画布组合会产生长尾 bug，建议第一版只支持 2020+ 的 `content.json` 并明示。

---

## 7. 未确认清单（明确不编造）

1. XMind 单个附件/单文档的体积上限与压缩策略——官方文档未提及。
2. XMind 移动端是否支持 Audio Note——文档只写 desktop。
3. 幕布导出 Word/PDF 时附件是否以任何形式带出——帮助页只列格式，未说明附件。
4. 幕布是否支持多人实时共同编辑——只查到分享与同步，未见实时协作说明。
5. MindManager 附件是否有应用内预览、移动端能否打开附件——未查到官方说明。
6. MindManager 官网当前确切年费数字——页面数字未渲染，仅有第三方 US$169/179。
7. iThoughts 附件在 iOS 上的具体预览交互（Quick Look 还是内置查看器）——帮助页只写「To view the document」，截图缺失。
8. MindNode Next 是否仍保留旧版「任意文件别名」能力——现行文档只列三种媒体类型。
9. markmap 导出 HTML 时对本地相对路径图片的处理——官方文档未说明，需实测。
10. Floretta 目标用户对「PSD 等大文件」的实际体积分布——无数据，工作量按 50MB 量级假设。

---

*本报告仅使用公开可访问的官方资料；所有「未确认」项均未以推测填充。*
