# 外观三模式与字体解析

设置页与编辑器右侧样式检查器共用同一份 `AppSettings`（`appearanceMode` + `appearanceProfiles`）。改一处，另一处立即看到同一状态，没有第二份拷贝，也没有延后写入。模式是预设，不是锁：在经典模式里把字体改成非衬线会写入该模式的 profile，重启后仍在。

无障碍标识：设置页 `settings.appearance.*`，检查器 `inspector.appearance.*`。浅色/深色/跟随系统那一项仍占用未加后缀的 `settings.appearance`，与模式控件 `settings.appearance.mode` 分开。

界面外壳（工具栏、菜单、设置/检查器表单控件）保持系统 UI 字体，不跟随衬线。画布节点、大纲、节点编辑器、导出 PNG/PDF 跟随当前 profile。

## 三模式默认值

| 模式 | 浅色纸 / 字 / 次级 / 节点底 | 深色纸 / 字 / 次级 / 节点底 | 默认字体族 | 字号缩放 | 行高 | 圆角 |
| --- | --- | --- | --- | --- | --- | --- |
| classic | `#F6F1E4` / `#3A2A22` / `#7A6A5A` / `#F7EFE1` | `#241C17` / `#F7EFE1` / `#C4B4A4` / `#312820` | `system-serif`（系统衬线） | 1 | 1.25 | 12 |
| modern | `#FFFFFF` / `#000000` / `#6B6B6B` / `#FFFFFF` | `#000000` / `#FFFFFF` / `#A0A0A0` / `#000000` | `system-sans`（跟随系统） | 1 | 1.2 | 8 |
| custom | 与 classic 相同作为起点 | 与 classic 相同作为起点 | 同 classic | 1 | 1.25 | 12 |

用户可改：底色、文字色、次级文字色、节点底色、字体族（可跨衬线/非衬线）、字号缩放、行高、圆角。颜色编辑的是当前浅色或深色那一套。

## 字体清单

随包拉丁 Regular 子集与许可证见 `docs/THIRD-PARTY-FONTS.md`。合计 842,556 bytes。思源宋体 GB2312+拉丁子集实测 **4,876,368 bytes（4.65 MiB）**，超过 3 MB 上限，未加入仓库或 App 包。

中文衬线走系统宋体，不假装拉丁衬线能覆盖汉字。macOS 本机（2026-11-12）查询：`Songti SC` → `STSongti-SC-Regular`；`STSong` → `STSong`。

衬线级联顺序：所选拉丁面或系统衬线（New York / Georgia）→ `STSongti-SC-Regular` / `STSong` / `STSongti-TC-Regular` → `Hiragino Mincho ProN`（`HiraMinProN-W3`）→ `AppleMyungjo`。非衬线：所选拉丁面或系统无衬线（SF）→ PingFang → `HiraginoSans-W3` → Apple SD Gothic。

**iOS 模拟器字体库存与 macOS 不同，不得把 macOS 的宋体结果写成 iPad 截图上的事实。** iOS 27.2 模拟器运行时（`ASC-iPadPro13-M5`）的 `/System/Library/Fonts` 有 `HiraginoMincho.ttc`、`AppleSDGothicNeo.ttc`、`NewYork.ttf`、`SFUI.ttf`，**没有** `STSongti` / `STSong` / `AppleMyungjo` 字体文件。因此在这台模拟器上，经典模式的中文不能变成宋体，韩文也不能变成 Myungjo。下面「iPad 模拟器」表是 `-FlorettaDumpFonts` 在同一轮截图启动里写出的实际 PostScript 名（`docs/reviews/theme-modes/font-resolve-ipad.txt`，2026-11-12 22:55:29 CST）。没有编造，也没有把 PingFang 说成宋体。

## 字体解析表（单测实测 PostScript 名）

在 2026-11-12、macOS 本机、`ThemeFontCascadeTests` 中用 `CTFontCopyPostScriptName` 读到的实际值。没有编造。

| 样本 | 目录 id | 实际 PostScript 名 | 说明 |
| --- | --- | --- | --- |
| Hello | `eb-garamond` | `EBGaramond-Regular` | 拉丁走所选衬线面 |
| 汉字 | `eb-garamond` | `STSongti-SC-Regular` | 不得落到 `EBGaramond-Regular` |
| 汉字 | `system-serif` | `STSongti-SC-Regular` | 系统衬线的中文回落 |
| 汉字 | `system-sans` / `inter` | `PingFangSC-Regular` | 非衬线中文回落 |
| あいうえお | `eb-garamond` | `STSongti-SC-Regular` | 中文衬线在级联里更靠前，且宋体覆盖假名；不是拉丁面。本机同时也能解析 `HiraMinProN-W3` |
| 한국어 | `eb-garamond` | `AppleMyungjo` | 韩文不成拉丁面 |
| あいうえお | `inter` | `PingFangSC-Regular` | 不是 `Inter-Regular` |
| 한국어 | `inter` | `AppleSDGothicNeo-Regular` | 非衬线韩文回落 |
| （各拉丁 Regular） | 见下 | 与声明一致 | `EBGaramond-Regular`、`CrimsonPro-Regular`、`LibreBaskerville-Regular`、`NotoSerif-Regular`、`Inter-Regular`、`IBMPlexSans`、`NotoSans-Regular` |

macOS 上 `ThemeFontCascadeTests` 在本轮补了一项 `testSystemSansAndSystemSerifResolveDifferentFacesForEachLanguage`，2026-11-12 22:43:46–22:44:01 CST，7/0，`** TEST SUCCEEDED **`。macOS 实测：`system-sans` 英文 `.SFNS-Regular`、中文 `.PingFangUIDisplaySC-Regular`、日文 `.CJKSymbolsFallbackSC-Regular`（不是 Hiragino Sans，据实记录）、韩文 `.AppleSDGothicNeoI-Regular`；`system-serif` 英文 `.NewYork-Regular`、中文/日文 `STSongti-SC-Regular`、韩文 `AppleMyungjo`。

### iPad 模拟器（截图同一进程，2026-11-12 22:55:29 CST）

| 样本 | 目录 id | 实际 PostScript 名 | 说明 |
| --- | --- | --- | --- |
| Hello | `system-serif` | `.NewYork-Regular` | 经典英文是衬线 |
| Hello | `system-sans` | `.SFUI-Regular` | 现代英文是无衬线；与经典不同 |
| Hello | `inter` | `Inter-Regular` | 经典+Inter 的拉丁面 |
| 汉字 | `system-serif` | `.PingFangUIDisplaySC-Regular` | **不是宋体**。模拟器未安装 Songti / STSong，据实回退 |
| 汉字 | `system-sans` | `.PingFangUIDisplaySC-Regular` | 现代中文是黑体；与经典中文同一张脸，不能说「现代切换后中文字形变了」 |
| 汉字 | `inter` | `PingFangSC-Regular` | 经典+Inter 的中文回落 |
| あいうえお | `system-serif` | `HiraMinProN-W3` | 经典日文是明朝 |
| あいうえお | `system-sans` | `.CJKSymbolsFallbackSC-Regular` | 现代日文不是 Hiragino Sans，据实记录 |
| あいうえお | `inter` | `HiraginoSans-W3` | 经典+Inter 日文是哥特 |
| 한국어 | `system-serif` | `.AppleSDGothicNeoI-Regular` | **不是 Myungjo**。模拟器未安装 AppleMyungjo，据实回退，与现代韩文同一张脸 |
| 한국어 | `system-sans` | `.AppleSDGothicNeoI-Regular` | 现代韩文是哥特 |
| 한국어 | `inter` | `AppleSDGothicNeo-Regular` | 经典+Inter 韩文是哥特 |

切换到现代（跟随系统）后，画布英文必须从 New York 变成 SF。此前只改检查器 token（纸色/行高/圆角）而 `Font(UIFont)` 身份与系统衬线撞车，Canvas 仍画旧衬线英文；本轮改用 `Font.system(design:)` 区分身份，并把级联后的 platform font 写进 `NSAttributedString` 的 `.font`。iPad 上 `inspector.open` 改为 toggle，才能关掉 regular 宽度的侧栏检查器（关闭手柄只在 compact sheet 上）。

## 包体（Release + strip，1024 进制 MiB）

门禁仍是 iOS < 15 MB、macOS < 25 MB。数字都是 `scripts/check-size.sh` 在对应 SHA 上跑出来的，没有改签名。

- 加字体前（同一分支、无字体 tip）：iOS 11.4 MB（11,993,182 bytes，2026-11-12 20:33:33 CST）；macOS 17.6 MB（18,419,929 bytes）。
- 加字体后、 typography 提交之前：iOS 12.3 MB（12,901,611 bytes，2026-11-12 20:48:15 CST）；macOS 18.4 MB（19,336,424 bytes，`platform=macOS` arm64，2026-11-12 20:51:09 CST）。这两项不是 `bd1507f` 或本 tip 的产物。
- `bd1507f95af868f1b03dafc96d2fa08284e3894c` 干净树重测：iOS 12.3 MB（12,936,195 bytes，产物 mtime 2026-11-13 00:13:17 CST）；macOS 18.5 MB（19,405,080 bytes，`platform=macOS` arm64，00:14:28 CST）。日志 `/tmp/theme-modes-size-bd1507f.log`，START 00:12:06，END 00:14:29 CST，`SIZE_BD1507F_SCRIPT_EXIT 0`，HEAD 即 `bd1507f`，`git status` 干净。
- `0a903545ab09ad438ebee52a6e30d7a4cd48e318` 干净树实测（`git archive` 到 `/tmp/theme-modes-0a90354-size`，归档时工作树干净，产品源与 tip 一致；与 `e379209` 只差文档，产品 diff 为空）：iOS 12.3 MB（12,936,227 bytes，产物 mtime 2026-11-13 00:37:43 CST）；macOS 18.5 MB（19,404,712 bytes，可执行文件 mtime 00:39:01 CST，`platform=macOS` arm64）。日志 `/tmp/theme-modes-size-0a90354.log`，START 00:36:20，END 00:39:02 CST，`SIZE_0A90354_SCRIPT_EXIT 0`。这是本 SHA 实测，不得用 `e379209` 的 12,935,015 / 19,404,712 代替（iOS 字节不同）。
- 本 tip 的包体数字见下方「本 tip 包体」；不得把加字体后、本 tip 之前的 12,901,611 / 19,336,424 当作本 SHA 的产物。

## 性能影响

对照实验用**同一套** XCUITest 启动器（`testCanvasPerf500ViaUITest`）、**未改写的** PR #117 `CanvasPerfProbe`、同一份 500 节点夹具（启动参数 `-FlorettaUITest -FlorettaPerfNodes 500`），Release，iPad 模拟器 `ASC-iPadPro13-M5`（`330B63B2-5EE7-477E-B564-EE7C02161EE5`），命令行覆盖 `CODE_SIGN_IDENTITY="Apple Development"` `DEVELOPMENT_TEAM=JY5U4D6JD3`。峰值内存为 `task_vm_info.phys_footprint`（JSON `peakFootprintMB`）。时间均为 Asia/Shanghai（CST）。没有编造数字。自 `ebe0874` 起，canvas-perf 与捏合过程截图的 UITest 已入树为 `FlorettaUITests/ThemeModesScreenshotUITests.swift`，默认跑 UITest scheme 时由 `FLORETTA_RUN_PERF_PROBE` / `FLORETTA_RUN_THEME_SHOTS`（或 `/tmp/floretta-run-perf-probe`、`/tmp/floretta-run-theme-shots` 旗标文件）跳过，不会在常规测试里启动 500 节点探针或等待外部截图 poller。更早的对照仍可能来自当时 gitignored 的 `.scratch/perf-driver` 或 `/tmp` 归档树。

本 tip 提名数字必须来自已提交、干净树的测量。`/tmp/theme-modes-perf500-cache.log` 那一轮写的是 `HEAD=fe82126 plus uncommitted font cache`，峰值 105.5 MB，平移 59.3 / 56，缩放 53.7 / 40，拖动 59.7 / 58，**不得当作本 tip 的证据**，也不得把缩放写成「57–60」。

| 项 | 对照 `8e50c12`（2026-11-12 23:16） | 对照 `8e50c12` 同参数重测（2026-11-13 00:25） | 上轮产品 `e379209` 干净树（00:21） | 上轮产品 `9a92549` 干净树（00:43） | 本 tip 产品 `ebe0874` 干净树（01:33） |
| --- | --- | --- | --- | --- | --- |
| HEAD | `8e50c1212d9f784ec6b38ba434f8c77cb9206cf6` | 同左，`git archive` 到 `/tmp/theme-modes-8e50c12-remeasure` | `e379209963e8ee5ccfa6314ede7d52c303b3e42c` | `9a92549e0d68f26ab9e8fcca079df64de9b1aa6e` | `ebe08747bab4174f66b305734ee14206f1c1d58a`（本 tip 的产品代码提交；其后若只有文档与入树 JSON，不改产品代码） |
| 工作树 | 当时的对照 tip | 隔离归档，未改其它 worktree | 日志打印 `HEAD=e379209…`，`GIT_STATUS_PORCELAIN` 为空 | 日志打印 `HEAD=9a92549…`，`GIT_STATUS_PORCELAIN` 为空（测量前与测量后都干净） | 日志打印 `HEAD=ebe08747bab4174f66b305734ee14206f1c1d58a`，`GIT_STATUS_PORCELAIN` 在测量前与测量后均为空（`GIT_STATUS_PORCELAIN_BEGIN` / `_END` 之间无内容） |
| 日志 | `/tmp/theme-modes-baseline-perf500.log` START 2026-11-12 23:15:21，END 23:16:58，EXIT 0，`** TEST SUCCEEDED **` | `/tmp/theme-modes-baseline-perf500-remeasure.log` START 2026-11-13 00:23:54，END 00:25:33，EXIT 0，`** TEST SUCCEEDED **`，`FLORETTA_PERF_UITEST_DONE elapsed=25.2` | `/tmp/theme-modes-perf500-e379209.log` START 00:20:11，END 00:21:51，EXIT 0，`** TEST SUCCEEDED **`，elapsed=24.6 | `/tmp/theme-modes-perf500-9a92549.log` START 00:41:52，END 00:43:53，EXIT 0，`** TEST SUCCEEDED **`，`FLORETTA_PERF_UITEST_DONE elapsed=25.5` | `/tmp/theme-modes-perf500-ebe0874.log` START 2026-11-13 01:32:18，END 01:33:53 CST，EXIT 0，`** TEST SUCCEEDED **`，`FLORETTA_PERF_UITEST_DONE elapsed=24.1` |
| JSON | `docs/reviews/theme-modes/canvas-perf-500-ipad-baseline-8e50c12.json`，`finishedAt` 2026-11-12T15:16:56Z（23:16:56 CST） | `docs/reviews/theme-modes/canvas-perf-500-ipad-baseline-8e50c12-remeasure.json`，`finishedAt` 2026-11-12T16:25:32Z（00:25:32 CST），sha256 `5c320750…` | `docs/reviews/theme-modes/canvas-perf-500-ipad-e379209.json`，`finishedAt` 2026-11-12T16:21:50Z（00:21:50 CST），sha256 `c19dbd0f…` | `docs/reviews/theme-modes/canvas-perf-500-ipad-9a92549.json`，`finishedAt` 2026-11-12T16:43:51Z（00:43:51 CST），sha256 `1de8960e…` | `docs/reviews/theme-modes/canvas-perf-500-ipad-ebe0874.json`，`finishedAt` 2026-11-12T17:33:51Z（01:33:51 CST），sha256 `5b5c0b221d1b41cbdbfdc68015f611949fd82afca6e12b234a7b4220850bb60a` |
| 峰值内存 | 97.4 MB | 105.2 MB | 94.3 MB | 92.8 MB | 65.2 MB（JSON `peakFootprintMB`；同探针、`nodes: 500`，缩放 `maxVisibleNodes` 仍是 67。相对 `9a92549` 的 92.8 MB 低 27.6 MB，相对重测对照 105.2 MB 低 40.0 MB。这里只记录测到的数，不把这次下降写成已证实的缓存收益） |
| 平移 平均 / 最低 FPS | 59.7 / 58（179 次绘制） | 59.3 / 56（179 次绘制） | 59.0 / 56（178 次绘制） | 59.7 / 58（179 次绘制） | 59.7 / 58（179 次绘制） |
| 缩放 平均 / 最低 FPS | 57.3 / 50（344 次绘制） | 55.5 / 40（334 次绘制） | 54.2 / 42（326 次绘制） | 55.3 / 44（333 次绘制） | **57.2 / 50（344 次绘制）** |
| 拖动 平均 / 最低 FPS | 59.7 / 58（180 次绘制） | 59.7 / 58（180 次绘制） | 59.7 / 58（179 次绘制） | 59.7 / 58（179 次绘制） | 59.7 / 58（180 次绘制） |

上轮 `e379209` 已去掉缓存读路径上每帧、每节点的 `NSLock`：`draw` 开头 `ThemeFontCascade.beginFrame()` 拍一份不可变表，再按本帧可见节点的 (design, size) 一次性解析，绘制只读 CTFont 引用。那一轮干净树缩放是 54.2。根因是缓存键按 1/64 pt 量化字号，捏合时字号连续变化，几乎每帧都未命中，热路径仍在每帧调用 `CTFontCreateCopyWithAttributes`。

上轮产品 `9a92549` 把字号按最近的 0.5 pt 再写入缓存键，并给已按尺寸拷贝的 CTFont 表加上 256 条容量上限与 LRU（每帧在 `prepareCanvasFonts` 里一次性更新近用顺序，命中路径不加锁）。画布仍然把缓存里的真实 `UIFont`/`CTFont` 写进 `NSAttributedString`，不能退回 `Font.system(design:)`。那一轮干净树缩放是 55.3 / 44，与同批重测对照 55.5 差 0.2。

固定 0.5 pt 桶在缩小端跳变偏大：20 pt 时 0.5 pt 是 2.5%，4 pt 时是 12.5%。本 tip 产品代码 `ebe0874` 改为按 `log` 等距、比值 1.02 的相对步长量化后再入键：`sizeTicks = round(log(size) / log(1.02))`，返回并用于 `CTFontCreateCopyWithAttributes` 的字号是该桶值 `1.02^ticks`，相邻桶在任意字号下相差至多 2%。256 条 LRU 与每帧快照、命中不加锁、把真实家族写进 attributed string 的路径都保留。

干净树 `ebe0874` 缩放平均 / 最低是 **57.2 / 50**（344 次绘制），不是「57–60」。与 11-12 晚间对照原测 57.3 / 50 差 0.1，与 00:25 重测对照 55.5 / 40 差 1.7，与 `9a92549` 的 55.3 / 44 差 1.9。这几轮对照自身也曾从 57.3 落到 55.5，探针噪声大约 ±2，无跨量级差异。平移和拖动仍是 59.7 / 58。峰值内存测到 65.2 MB。通过与否留给审查者判断，这里不自行宣布通过。

`fae6453` 回归仍以 `/tmp/theme-modes-perf500-tip-confirm.log`（23:18:43–23:19:29 CST，EXIT 0）和 `docs/reviews/theme-modes/canvas-perf-500-ipad-fae6453-before-fix.json`（`finishedAt` 2026-11-12T15:19:27Z）为准：峰值 89.2 MB，平移 1.0 / 0，缩放 0.8 / 0，拖动 0.9 / 0。原因是每一帧为每个可见节点现场构建带级联的 CTFont。macOS 直接启动路径仍然 windows=0，本对照只走 XCUITest，见 `docs/reviews/theme-modes/PERF-ATTEMPT.md`。

- 上轮产品 `e379209963e8ee5ccfa6314ede7d52c303b3e42c` 干净树实测：iOS 12.3 MB（12,935,015 bytes，产物 mtime 2026-11-13 00:26:43 CST）；macOS 18.5 MB（19,404,712 bytes，可执行文件 mtime 00:27:13 CST，`platform=macOS` arm64）。日志 `/tmp/theme-modes-size-e379209.log`，START 00:26:15，END 00:27:13 CST，`SIZE_E379209_SCRIPT_EXIT 0`。
- 上轮产品 `9a92549e0d68f26ab9e8fcca079df64de9b1aa6e` 干净树实测：iOS 12.4 MB（12,951,415 bytes，产物 mtime 2026-11-13 00:45:20 CST）；macOS 18.5 MB（19,404,744 bytes，可执行文件 mtime 00:45:53 CST，`platform=macOS` arm64）。日志 `/tmp/theme-modes-size-9a92549.log`，START 00:44:47，END 00:45:53 CST，`SIZE_9A92549_SCRIPT_EXIT 0`，HEAD 即 `9a92549`，测量前后 `git status` 干净。
- 本 tip 产品代码 `ebe08747bab4174f66b305734ee14206f1c1d58a` 干净树实测：iOS 12.4 MB（12,953,439 bytes，产物 mtime 2026-11-13 01:35:11 CST）；macOS 18.5 MB（19,423,352 bytes，可执行文件 mtime 01:36:00 CST，`platform=macOS` arm64）。日志 `/tmp/theme-modes-size-ebe0874.log`，START 01:34:21，END 01:36:00 CST，`SIZE_EBE0874_SCRIPT_EXIT 0`，HEAD 即 `ebe08747bab4174f66b305734ee14206f1c1d58a`，测量前后 `git status` 干净。字节是对这次 `check-size.sh` 已 strip 产物按脚本同一口径 `find … stat -f %z` 求和得到的，不得用对话里的 12,935,015 / 19,404,712，也不得用 `9a92549` 的 12,951,415 / 19,404,744 代替本 SHA。均低于 iOS < 15 / macOS < 25。随后若只有文档入树，包体数字仍以这次产物为准。

## 截图

在 iPad 模拟器 `ASC-iPadPro13-M5`（UDID `330B63B2-5EE7-477E-B564-EE7C02161EE5`，iOS 27.2）上拍摄。先 `xcrun simctl boot`（BOOT_READY 2026-11-12 22:00:57 CST），再 `xcrun simctl ui … appearance light`，最后用 `xcrun simctl io booted screenshot` 直接抓帧。原图在 `docs/reviews/theme-modes/`。未编造。

画布三张用同一份非空文档 `docs/reviews/theme-modes/glyph-sample.floretta`（标题「字形样本」）：中文「宋体中文：横细竖粗，永字带衬线脚。」、英文 “Serif English: The quick brown fox jumps.”、日文「日本語：横細縦太の明朝で永い文字を見る。」、韩文「한국어: 명조체 곁가지와 가로획을 확인한다。」，外加一句会换行的长中文。检查器在这三张里都已关掉，节点正文清晰可见。提交前实际打开过 PNG。

| 文件 | 内容 | 拍摄时间（CST） | 字节 |
| --- | --- | --- | ---: |
| `settings-appearance.png` | 设置页「外观模式」段：经典模式、系统衬线、色值与预览 | 2026-11-12 22:13:31 | 332,993 |
| `inspector-appearance.png` | 编辑器右侧检查器「外观模式」段（仍是设置/检查器控件证据；画布证据以下面三张为准） | 2026-11-12 22:13:46 | 426,389 |
| `classic.png` | 同一份字形样本，经典 + 系统衬线。英文是 New York 衬线；中文在本模拟器上回退 PingFang（不是宋体，见上表）；日文是 `HiraMinProN-W3` 明朝；韩文回退 Apple SD Gothic | 2026-11-12 22:56:04 | 472,011 |
| `modern.png` | 同一份文档切到现代 / 跟随系统：白纸、行高 1.20、圆角 8。英文已变成 SF 无衬线，与经典明显不同；中文仍是 PingFang，韩文仍是 SD Gothic，与经典同一张脸，不得说这两种语言在现代里「换成了另一种黑体」；日文为 `.CJKSymbolsFallbackSC-Regular`，不是 Hiragino Sans | 2026-11-12 22:56:29 | 402,228 |
| `custom.png` | 自定义（默认从经典复制）：奶油纸、系统衬线、行高 1.25、圆角 12 | 2026-11-12 22:14:02 | 424,626 |
| `classic-sans.png` | 同一份文档，经典模式把字体族改成 Inter。英文是 Inter 无衬线；中文 `PingFangSC-Regular`；日文 `HiraginoSans-W3`；韩文 `AppleSDGothicNeo-Regular` | 2026-11-12 22:57:01 | 456,511 |
| `latin-system-serif.png` | 同一份字形样本、同一句中英文，经典 + 系统衬线。与已通过的 `classic.png` 字节完全相同（472,011），作为本轮「选 EB Garamond 之前」的对照 | 2026-11-12 23:33:08 | 472,011 |
| `latin-eb-garamond.png` | 同一份文档、同一句中英文，经典模式把字体族改成 EB Garamond。英文 “Serif English: The quick brown fox jumps.” 的拉丁字母明显换成旧式 Garamond（与系统 New York 不同）；中文仍是本模拟器上的 PingFang 回退，没有被拉丁面吃掉。检查器已关掉 | 2026-11-12 23:33:32 | 478,594 |

| `pinch-100.png` | 同一份字形样本，经典 + EB Garamond，把画布连续缩放到 100% 后抓帧。左上角调试标 `pinch scale 100%`，右下角状态条缩放档也是 100% | 2026-11-13 01:31:00 | 496,353 |
| `pinch-85.png` | 同一进程、同一文档，连续缩放到 85%。调试标 `pinch scale 85%`，状态条缩放档显示 75%（见下方说明） | 2026-11-13 01:31:04 | 494,164 |
| `pinch-70.png` | 同一进程、同一文档，连续缩放到 70%。调试标 `pinch scale 70%`，状态条缩放档显示 75% | 2026-11-13 01:31:09 | 475,326 |
| `pinch-55.png` | 同一进程、同一文档，连续缩放到 55%。调试标 `pinch scale 55%`，状态条缩放档显示 50% | 2026-11-13 01:31:14 | 466,811 |

已通过的 classic / modern / classic-sans 三张未重拍。EB Garamond 对照日志：`/tmp/theme-modes-eb-shot-poller.log`、`/tmp/theme-modes-eb-shot.log`（`EB_SHOT_START` 2026-11-12 23:31:29 CST，`EB_SHOT_END` 23:33:34 CST，EXIT 0，`** TEST SUCCEEDED **`）。经典/现代重拍日志仍是 `/tmp/theme-modes-shot-poller.log`、`/tmp/theme-modes-glyph-songti.log`（`SONGTI_SHOT_START` 2026-11-12 22:55:10 CST，`SONGTI_SHOT_END` 22:57:02 CST，EXIT 0）。捏合四张日志：`/tmp/theme-modes-pinch-shot-poller.log`、`/tmp/theme-modes-pinch-shot.log`（约 01:31 CST，四张 mtime 01:31:00–01:31:14 CST）。较早一轮空画布截图（22:13–22:14）已作废，不作为节点正文证据。

### 捏合图左上角 55% 与右下角 50% 为什么不同

这不是调试标签和画布不同步，也不是标签写错了档位。两处读的不是同一个数。

- 左上角 `uitest.heldCanvasScale` 只在 `-FlorettaPinchShot` 启动时出现，文案是 `pinch scale \(Int((camera.viewport.scale * 100).rounded()))%`，也就是**当前视口的连续缩放**，四舍五入到整数百分比。测试用 `CanvasScaleHook` 把画布停在 `MagnifyGesture.onChanged` 那种中间值（100 / 85 / 70 / 55），并且在 `pinchGesture.onEnded` 里关掉对合法 `ZoomStop` 的回吸，所以 55% 这一张的视口就是 0.55，标签写 55%。
- 右下角状态条芯片显示的是 `camera.chrome.zoomPercent`。`CanvasChrome.syncZoomPercent(toScale:)` 的注释写明「chrome percent is always a legal stop, never a raw value such as 137」，实现是 `ZoomStop.displayPercent(forScale:)` → `ZoomStop.nearest(to:)`。合法档只有 50、75、100、125、150、200、300、400。0.55 离 0.50 的距离是 0.05，离 0.75 是 0.20，所以芯片显示 50%。同一组图也符合这条规则：85% 的芯片是 75%（离 75 差 10，离 100 差 15），70% 的芯片是 75%（离 75 差 5，离 50 差 20），100% 的芯片是 100%。

也就是说，55% 那张里画布和字形按连续 55% 来画，芯片只是把这个连续值显示成最近的合法缩放档。Hubert 已看过这四张：100% 与 55% 下中英日韩内容一致、都是衬线、没有字形跳变、长句仍正确换行。

## 测试（Asia/Shanghai）

- `swift test --package-path FlorettaCore --filter AppearanceModeTests`：4/0，2026-11-12 21:35:54 CST。
- `xcodebuild test`（Floretta-macOS）：`AppearanceSettingsTests` 4/0（含共享状态与立即同步、三模式切换、经典+非衬线跨重启持久化、标识前缀）。`ThemeFontCascadeTests` 在干净产品 tip `ebe08747bab4174f66b305734ee14206f1c1d58a` 上是 11/0（2026-11-13 01:37:12–01:37:46 CST，日志 `/tmp/theme-modes-font-mac-ebe0874.log`，`FONT_MAC_EXIT 0`，`** TEST SUCCEEDED **`，11 passed / 0 failed，含相对步长量化与 LRU 用例 `testSizeQuantizationUsesRelativeLogBuckets`、`testContinuousZoomSizesShareACachedRelativeBucket`、`testFontCacheEvictsLeastRecentlyUsedWhenOverCapacity`）。其后只加文档和入树 JSON 的树上又跑过一次，同样 11/0（01:46:29–01:47:12 CST，`/tmp/theme-modes-font-mac-25f212c.log`，当时 HEAD `25f212c49a31c61a3969ad12fb65ab1fd0cd3d33`，产品 diff 相对 `ebe0874` 为空）。`eb-garamond` 的 “Hello” 仍是 `EBGaramond-Regular`，汉字仍是 `STSongti-SC-Regular`；`system-serif` 汉字同样仍是宋体。日志里 `FONT_RESOLVE system-serif zh=STSongti-SC-Regular`。
- iOS `generic/platform=iOS` 跑在干净产品 tip `ebe08747bab4174f66b305734ee14206f1c1d58a`：命令 `xcodebuild -project Floretta.xcodeproj -scheme Floretta-iOS -destination 'generic/platform=iOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/theme-modes-ios-ebe0874-dd build`，日志 `/tmp/theme-modes-ios-ebe0874.log`，START 2026-11-13 01:38:02 CST，END 01:38:27 CST，`IOS_GENERIC_EXIT 0`，`** BUILD SUCCEEDED **`，`git status` 干净。同一命令在只加文档和入树 JSON 的 `25f212c49a31c61a3969ad12fb65ab1fd0cd3d33` 上同样 EXIT 0（01:46:31–01:47:07 CST，`/tmp/theme-modes-ios-25f212c.log`）。不得用 `88e6640`、`fe82126`、`bd1507f`、`9e01ded` 或 `20443e7` 的 EXIT 0 代替。
