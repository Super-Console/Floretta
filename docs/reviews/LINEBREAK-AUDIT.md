# 换行与折行排查（LINEBREAK-AUDIT）

日期：2026-11-12 18:15 CST  
基线：`origin/main` `e20c28d`（#115 合入后）  
工作区：`.worktrees/linebreak`，分支 `feat/node-line-breaking`  
探针日志与重建截图：`docs/reviews/linebreak/`（`probe-log.txt`，`*-before-after.png`）

和 `perf/canvas-baseline`（`.worktrees/canvas-perf`，tip `957c34e`，另有未提交的 `DocumentEditor.swift`）做了只读对照。该分支改过 `InfiniteCanvas.swift`，但只加了 `CanvasPerfRun` 探针与 `-FlorettaPerfNodes` 驱动，没有改折行、测量或布局。本任务从 `origin/main` 起步，画布改动只限于节点标题的 `draw(in:)` 与 `styledText`，避免覆盖他们的性能工作。

测量与渲染都走已有的 `FontMetricsPort`（苹果侧实现 `CoreTextFontMetrics`）。没有缩小字号，也没有截断文本来“看起来正常”。

## 总表

| 场景 | 改前是否有问题 | 改后 |
|---|---|---|
| A. 节点长文本自动折行 | **有问题** | 已修 |
| B. Shift+Enter 手动换行 | **有问题**（插入位置 / 是否被吞掉） | 已修 |
| C. 中文标点避头尾 | 测量层在产品宽度下基本正常；画布因 A 不折行，避头尾无从谈起 | 随 A 修复；官方 `lineBreakStrategy = .standard` 已接上。极窄宽度下的连续标点是平台限制 |
| D. 英文超长单词 | **有问题**（画布侧溢出裁切）；测量层本来就会按字符断开 | 已修（画布改为按矩形折行） |
| E. 缩放后重排 | 测量层 50/100/200% 断行一致；画布因 A 看不出折行 | 修复 A 后逻辑断行保持一致。50% 下 16pt 节点会因 LOD（< 9pt）隐藏标题，这不是折行重排 |
| F. 导出保真 | **PNG/PDF 与画布不一致**（导出已 `draw(in:)`，画布是 `draw(at:)` 裁切）。Markdown 会把手动换行压成空格 | PNG/PDF 与画布共用同一套折行。Markdown 的换行丢失是标题格式限制，未改 |
| G. 编辑态 vs 非编辑态行高跳变 | **有问题** | 主要跳变已消。测量改为系统字体 + 同一段落样式；iOS 编辑器竖向留白改为 `usedRect`。残余几 pt 的行框差见下 |

**不是“全部已优化”。** A、B、D、F（画布/导出）、G 改前都是真实问题。C 在 240pt 产品宽度下测量层本来就没有避头尾违规。E 的逻辑断行在测量层本来就是稳定的。

---

## A. 节点长文本自动折行

**怎么验：** 40 / 80 / 120 字中文，以及一段约 80 词的英文，在 `maxTextWidth = 240`、20pt（一级主题）下看宽度与断行。

**实际行为（改前）：**
- 布局测量（`TextMeasurementCache` → `CoreTextFontMetrics`）会折行。80 字中文量出 7 行，节点约 264×212（Helvetica 测量，含 24×16 内边距）。见 `probe-log.txt` 18:09 CST。
- 画布绘制在 `InfiniteCanvas.swift`（原 1758 行）用 `GraphicsContext.draw(_:at:anchor: .center)`，再 `clip(to: textRect)`。这个 API 按理想尺寸（通常一行）画，不按节点宽度折行，两端把字裁成两半，上下留出大片空白。
- 重建截图：`docs/reviews/linebreak/A-zh80-before-after.png`、`A-zh40-before-after.png`、`A-zh120-before-after.png`、`A-en80-before-after.png`。左边是改前 API，右边是 `draw(in:)`（与 `MapExport` 相同）。

**是否符合预期：** 不符合。“不出现半个字被裁；不出现整段不换行溢出”都失败了。

**根因：** `Floretta/Shared/Canvas/InfiniteCanvas.swift` 节点标题绘制（改前约 1754–1758 行）。测量与绘制不一致。导出路径已经在用 `draw(in: textRect)`。

**修复：** 改为 `textLayer.draw(text, in: textRect)`，标题 `Text` 带上与测量相同的 `NSParagraphStyle`。不缩小字号，不截断。

---

## B. 手动换行（Shift+Enter）

**怎么验：** 编辑态 Shift+Enter 输入两行；再进编辑看光标。

**实际行为（改前）：**
- 映射是对的：编辑态 Shift+Enter → `.insertNewline`（`KeyboardCommandMapper.swift` 137–139 行）。命令态 Shift+Enter 仍是插入兄节点。
- 会话实现 `MindMapKeyboardSession.insertNewline` 把 `"\n"` **追加到缓冲区末尾**，不知道光标位置。测试 `testShiftEnterInsertsNewlineOnlyInEditMode` 只覆盖了“根”→“根\n”这种末尾情况（2026-11-12 读到的源码）。
- 真正的编辑器会把这个命令当成已处理：macOS `doCommandBy` 里 `onEvent` 返回 true 后，`NSTextView` 不再执行 `insertLineBreak:`；iOS `pressesBegan` 同样在 `onEvent == true` 时直接 return。同时 `updateNSView` 在 `ownsKeys` 时不会把 binding 写回 text view。结果是：光标在中间按时，视图里往往**看不到换行**，缓冲区却在末尾多了一个 `\n`，下一次 `textDidChange` 还可能用视图字符串把这个 `\n` 覆盖掉。
- 若 `\n` 已经进了节点文本，测量和 `draw(in:)` 都会保留两行。`B-manual-before-after.png` 里的短文本两边都能看出两行，因为理想高度也包含显式换行；这掩盖了“按在中间被吞掉”的问题。

**是否符合预期：** 不符合。“换行被保留、光标位置正确”在真实编辑路径上不成立。

**根因：** `NodeTextEditor.swift` 拦截了 Shift+Enter 并交给会话；`MindMapKeyboardSession.insertNewline`（约 366–368 行）只在末尾追加。

**修复：** `NodeEditLineBreak.textViewInsertsLine` 让 focused text view 自己在光标处插入换行，再通过 `textDidChange` → `replaceEditingText` 同步。会话方法只作为无 text view 时的后备（测试仍走这条路径）。没有改命令态 Shift+Enter 插兄节点的行为。

---

## C. 中文标点避头尾

**怎么验：** 含「，。」「（）」的长句，让折行点落在标点前后。另在 60–280pt 宽度上做了扫描。

**实际行为：**
- 在产品宽度 240pt、16/20pt 下，Helvetica 与系统字体、无论是否设置 `lineBreakStrategy = .standard`，扫描过的常规句子都没有行首「，。」或行尾「（「。UAX #14 / CoreText 默认已经处理了这类标点。日志见 `probe-log.txt` 的 C 节，以及 18:11 CST 的宽度扫描。
- 画布改前根本不折行，所以谈不上避头尾，表现并进 A。
- 只在极端情况下仍会违规：约 60–62pt 宽、30pt 字号（一行两字），且文本里有连续「，。」或「「（「」这类标点串。`lineBreakStrategy = .standard` **不能**消除这些命中（有/无策略命中次数相同）。未手写字符规则表。

**是否符合预期：** 产品宽度下测量层可视为正常。画布改前因 A 不合格。极窄连续标点是平台限制，影响范围是节点被收到大约两个汉字宽的时候。

**根因：** 无单独的产品宽度缺陷。测量原先没有设段落样式，但 240pt 下结果已经合规。

**修复：** `CoreTextFontMetrics` 与画布 / 导出 / 编辑器统一使用 `NSParagraphStyle.lineBreakMode = .byWordWrapping`、`lineBreakStrategy = .standard`。不缩小字号、不截断。不声称官方策略修好了 60pt 连续标点。

---

## D. 英文超长单词

**怎么验：** `supercalifragilisticexpialidocious`（34 个字母），20pt，最大宽 240。

**实际行为（改前）：**
- 测量层已经会断开：无约束宽约 283pt，约束后约 236×48、两行（`supercalifragilisticexpialido` / `cious`），不溢出。默认 word wrap 在单词超过行宽时就会按字符断开，不必改成全局 `byCharWrapping`（后者会把普通英文句子在空格处切得更碎，见探针里 `systemStandardCharWrap` 的 L3 以空格开头）。
- 画布仍走 `draw(at:)`，超长单词会画出理想宽度并在节点边缘裁切。`D-longword-before-after.png`、`D-longword-sentence-before-after.png`。

**是否符合预期：** 测量正常；画布显示不符合“不溢出节点”。

**根因：** 与 A 相同，绘制 API。

**修复：** 随 A 改为 `draw(in:)`。策略明确为：按词换行，单个单词宽于节点时按字符断开。不是截断，也不是缩小字号。

---

## E. 缩放后重排

**怎么验：** 同一 80 字中文节点，在 50% / 100% / 200% 下比较断行（字体和宽度同时乘以缩放）。

**实际行为：**
- 测量层：三个缩放都是相同的 7 行、相同的断行位置（18:09 CST 探针）。
- 画布改前始终是一行裁切，看不出“因缩放改行数”，但显示是错的。
- LOD：`CanvasTextScale` / `CanvasTextLOD` 在屏幕字号 < 9pt 时不画标题。更深一层 16pt 在 50% 下是 8pt，标题会被藏成色块。根节点 30pt、一级 20pt 在 50% 仍可见。这是既有的远距简化，不是断行重排。

**是否符合预期：** 逻辑折行本身符合“缩放不改变行数”。显示问题并进 A。LOD 隐藏小字号标题按现有设计保留。

**根因：** 无独立的缩放重排 bug。

**修复：** 无单独补丁。A 修好后，字号与 `textRect` 一起缩放，断行保持一致。相关测试：`LineBreakTests.testLineBreaksStayStableAcrossZoom`。

---

## F. 导出保真

**怎么验：** PNG / PDF / Markdown 与画布对比。

**实际行为（改前）：**
- PNG/PDF 通过 `MapExporter.visibleFrames` → `CanvasPlacement`（已注入 `CoreTextFontMetrics`）排版，并用 `context.draw(_:in: textRect)` 画标题。画布用 `draw(at:)`。同一文档导出是折行的，画布是单行裁切。这是真实的不一致。
- Markdown：`FlorettaMarkdown.heading` 与 `FlorettaMarkdownDocumentCodec.flattenNewlines` 把节点里的 `\n` 换成空格。ATX 标题不能包含换行；再导入也会丢。自动折行本来就不进文件，只影响画面。

**是否符合预期：** PNG/PDF 相对画布不符合。Markdown 手动换行丢失是格式限制。

**根因：** 画布绘制（A）。Markdown：`FlorettaCore/Format/FlorettaMarkdown.swift` 约 67–68 行，`FlorettaMarkdownDocumentCodec.swift` 167–171 行。

**修复：** 画布与导出都走 `NodeTextTypography.canvasText` + `draw(in:)`。Markdown 未改——若改成在标题里保留换行，会破坏现有的导出/再导入契约。需要另开任务才能定一个可往返的写法（例如备注字段）。

---

## G. 编辑态 vs 非编辑态行高跳变

**怎么验：** 同一长文本节点进入 / 退出编辑。

**实际行为（改前）：**
- 非编辑：一行裁切，垂直居中在一个按多行高度撑起来的框里（80 字中文节点高约 212）。
- 编辑：`NSTextView` / `UITextView` 按节点宽度折行，系统字体，水平居中；macOS 用 `usedRect` 做垂直居中，iOS 却用**硬换行行数** × `lineHeight` 估高度（自动折行的 7 行会被当成 1 行），垂直留白会错。
- 测量用 Helvetica（中文回退字体行高更大）：80 字量出 196pt 文本高、节点 212；同一框里系统字体 TextKit 只用 140pt（差值 72pt）。见 `probe-log.txt` G 节与 `G-edit-vs-idle-zh80.png`。

**是否符合预期：** 不符合。用户之前说的「编辑时样式会掉」与这一跳变相符。

**根因：**
- 绘制 API（A）
- `TextMeasurementCache` 向 port 传 `"Helvetica"`，画布和编辑器画的是系统字体（`FlorettaTitleFont` / `editingFont`）
- iOS `FlorettaTextView.layoutSubviews`（约 908–910 行）用换行计数而不是 `usedRect`

**修复：** 测量在请求 Helvetica / 空名称时改用 `CTFontCreateUIFontForLanguage(.system, …)`；段落样式与编辑器、画布、导出对齐；iOS 竖向留白改用 `layoutManager.usedRect`。不缩字号、不截断。

**残余：** 系统字体下 CoreText `SuggestFrameSize` 与 TextKit `usedRect` 仍可能有大约十几 pt 的行框差（探针里 160 vs 140，外加 16pt 测量内边距对 8pt 编辑器inset）。节点高度仍略高于编辑器文字块，编辑器会把差额均分到上下。这比改前的 72pt 加单行裁切小得多，但没有强行把两种测量拧成同一个数字。

---

## 改动文件

- `Floretta/Shared/Ports/ApplePlatformPorts.swift` — `NodeTextTypography`，`CoreTextFontMetrics` 使用系统字体与官方段落样式
- `Floretta/Shared/Canvas/InfiniteCanvas.swift` — 标题 `draw(in:)`
- `Floretta/Shared/Canvas/MapExport.swift` — 与画布共用 `canvasText`
- `Floretta/Shared/Keyboard/NodeTextEditor.swift` — Shift+Enter 交给 text view；段落样式；iOS `usedRect`
- `FlorettaCore/Keyboard/MindMapKeyboardSession.swift` — 注明 `insertNewline` 只是后备
- `FlorettaTests/CanvasTests.swift` — `LineBreakTests`

未改 `docs/FEATURES-CHECKLIST.md`、`docs/STATUS.md`、`docs/SMOKE.md`、`docs/VERIFY.md`。未改签名与版本号。

## 编译与测试

- macOS `Floretta-macOS` 编译：exit 0，18:18:44 CST，`-derivedDataPath /tmp/linebreak-macos`，`CODE_SIGNING_ALLOWED=NO`。日志里仅有 xcodebuild 的 `error: the following command failed with exit code 0 but produced no further output`（2 条），无编译器 `error:`。
- iOS `Floretta-iOS` generic simulator 编译：exit 0，18:18:42 CST，`-derivedDataPath /tmp/linebreak-ios`，同样签名关闭。同样只有 2 条上述噪音，无编译器错误。
- macOS `FlorettaTests`：425 tests, 0 failures，** TEST SUCCEEDED **，18:20:26 CST。其中 `LineBreakTests` 6/0（18:19:16 CST）：长中文折行、超长英文单词断开、手动换行、缩放断行稳定、Shift+Enter 交给 text view、cache 宽度上限。`KeyboardTests` 亦在同一 bundle 中通过。
