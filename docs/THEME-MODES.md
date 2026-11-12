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
- 本 tip 的包体数字见下方「本 tip 包体」；不得把加字体后、本 tip 之前的 12,901,611 / 19,336,424 当作本 SHA 的产物。

## 性能影响

对照实验用**同一套** XCUITest 启动器（`testCanvasPerf500ViaUITest`）、**未改写的** PR #117 `CanvasPerfProbe`、同一份 500 节点夹具（启动参数 `-FlorettaUITest -FlorettaPerfNodes 500`），Release，iPad 模拟器 `ASC-iPadPro13-M5`（`330B63B2-5EE7-477E-B564-EE7C02161EE5`），命令行覆盖 `CODE_SIGN_IDENTITY="Apple Development"` `DEVELOPMENT_TEAM=JY5U4D6JD3`。峰值内存为 `task_vm_info.phys_footprint`（JSON `peakFootprintMB`）。时间均为 Asia/Shanghai（CST）。没有编造数字。临时 UITest / pbx 驱动只放在 gitignored 的 `.scratch/perf-driver`（或对照的 `/tmp` 归档树）里，不进 tip。

本 tip 提名数字必须来自已提交、干净树的测量。`/tmp/theme-modes-perf500-cache.log` 那一轮写的是 `HEAD=fe82126 plus uncommitted font cache`，峰值 105.5 MB，平移 59.3 / 56，缩放 53.7 / 40，拖动 59.7 / 58，**不得当作本 tip 的证据**，也不得把缩放 53.7 或本 tip 的 54.2 写成「57–60」。

| 项 | 对照 `8e50c12`（2026-11-12 23:16） | 对照 `8e50c12` 同参数重测（2026-11-13 00:25） | 本 tip 干净树 `e379209`（2026-11-13 00:21） |
| --- | --- | --- | --- |
| HEAD | `8e50c1212d9f784ec6b38ba434f8c77cb9206cf6` | 同左，`git archive` 到 `/tmp/theme-modes-8e50c12-remeasure` | `e379209963e8ee5ccfa6314ede7d52c303b3e42c`（本 tip 的产品代码提交） |
| 工作树 | 当时的对照 tip | 隔离归档，未改其它 worktree | 日志打印 `HEAD=e379209…`，`GIT_STATUS_PORCELAIN` 为空（测量前与测量后都干净） |
| 日志 | `/tmp/theme-modes-baseline-perf500.log` START 2026-11-12 23:15:21，END 23:16:58，EXIT 0，`** TEST SUCCEEDED **` | `/tmp/theme-modes-baseline-perf500-remeasure.log` START 2026-11-13 00:23:54，END 00:25:33，EXIT 0，`** TEST SUCCEEDED **`，`FLORETTA_PERF_UITEST_DONE elapsed=25.2` | `/tmp/theme-modes-perf500-e379209.log` START 2026-11-13 00:20:11，END 00:21:51，EXIT 0，`** TEST SUCCEEDED **`，`FLORETTA_PERF_UITEST_DONE elapsed=24.6` |
| JSON | `docs/reviews/theme-modes/canvas-perf-500-ipad-baseline-8e50c12.json`，`finishedAt` 2026-11-12T15:16:56Z（23:16:56 CST） | `docs/reviews/theme-modes/canvas-perf-500-ipad-baseline-8e50c12-remeasure.json`，`finishedAt` 2026-11-12T16:25:32Z（00:25:32 CST），sha256 `5c320750…` | `docs/reviews/theme-modes/canvas-perf-500-ipad-e379209.json`，`finishedAt` 2026-11-12T16:21:50Z（00:21:50 CST），sha256 `c19dbd0f…` |
| 峰值内存 | 97.4 MB | 105.2 MB | 94.3 MB |
| 平移 平均 / 最低 FPS | 59.7 / 58（179 次绘制） | 59.3 / 56（179 次绘制） | 59.0 / 56（178 次绘制） |
| 缩放 平均 / 最低 FPS | 57.3 / 50（344 次绘制） | 55.5 / 40（334 次绘制） | **54.2 / 42（326 次绘制），低于门禁 ≥55** |
| 拖动 平均 / 最低 FPS | 59.7 / 58（180 次绘制） | 59.7 / 58（180 次绘制） | 59.7 / 58（179 次绘制） |

本 tip 去掉了缓存读路径上每帧、每节点的 `NSLock`：`draw` 开头 `ThemeFontCascade.beginFrame()` 拍一份不可变表，再按本帧可见节点的 (design, size) 一次性解析，绘制只读 CTFont 引用；捏合新字号仍走 `CTFontCreateCopyWithAttributes`，但拷贝不在锁内进行。画布仍然把缓存里的真实 `UIFont`/`CTFont` 写进 `NSAttributedString`，不能退回 `Font.system(design:)`。

缩放平均 54.2 仍低于门禁 ≥55，也低于同参数重测对照的 55.5，以及 11-12 晚间对照的 57.3。平移和拖动仍在 59 一带。这与 `fae6453` 的约 1 FPS 不是同一量级，但**不能**把本 tip 写成「57–60」，也**不能**按缩放达标来申请通过。同参数对照本身也有波动（缩放 57.3 / 50 对 55.5 / 40），两组数字都据实列出。

`fae6453` 回归仍以 `/tmp/theme-modes-perf500-tip-confirm.log`（23:18:43–23:19:29 CST，EXIT 0）和 `docs/reviews/theme-modes/canvas-perf-500-ipad-fae6453-before-fix.json`（`finishedAt` 2026-11-12T15:19:27Z）为准：峰值 89.2 MB，平移 1.0 / 0，缩放 0.8 / 0，拖动 0.9 / 0。原因是每一帧为每个可见节点现场构建带级联的 CTFont。macOS 直接启动路径仍然 windows=0，本对照只走 XCUITest，见 `docs/reviews/theme-modes/PERF-ATTEMPT.md`。

- 本 tip `e379209963e8ee5ccfa6314ede7d52c303b3e42c` 干净树实测：iOS 12.3 MB（12,935,015 bytes，产物 mtime 2026-11-13 00:26:43 CST）；macOS 18.5 MB（19,404,712 bytes，可执行文件 mtime 00:27:13 CST，`platform=macOS` arm64）。日志 `/tmp/theme-modes-size-e379209.log`，START 00:26:15，END 00:27:13 CST，`SIZE_E379209_SCRIPT_EXIT 0`。随后若只有文档入树，包体数字仍以这次产物为准。

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

已通过的 classic / modern / classic-sans 三张未重拍。EB Garamond 对照日志：`/tmp/theme-modes-eb-shot-poller.log`、`/tmp/theme-modes-eb-shot.log`（`EB_SHOT_START` 2026-11-12 23:31:29 CST，`EB_SHOT_END` 23:33:34 CST，EXIT 0，`** TEST SUCCEEDED **`）。经典/现代重拍日志仍是 `/tmp/theme-modes-shot-poller.log`、`/tmp/theme-modes-glyph-songti.log`（`SONGTI_SHOT_START` 2026-11-12 22:55:10 CST，`SONGTI_SHOT_END` 22:57:02 CST，EXIT 0）。较早一轮空画布截图（22:13–22:14）已作废，不作为节点正文证据。

## 测试（Asia/Shanghai）

- `swift test --package-path FlorettaCore --filter AppearanceModeTests`：4/0，2026-11-12 21:35:54 CST。
- `xcodebuild test`（Floretta-macOS）：`AppearanceSettingsTests` 4/0（含共享状态与立即同步、三模式切换、经典+非衬线跨重启持久化、标识前缀）。`ThemeFontCascadeTests` 在干净树上仍是 8/0（2026-11-13 00:28:30–00:28:36 CST，日志 `/tmp/theme-modes-font-mac-test5.log`，当时 HEAD `9e01ded1bf5b8a179193f859c5f7b3bc1d32e56a`，与产品代码提交 `e379209` 只差文档，`FONT_MAC_EXIT 0`，`** TEST SUCCEEDED **`，8 passed / 0 failed）。`eb-garamond` 的 “Hello” 仍是 `EBGaramond-Regular`，汉字仍是 `STSongti-SC-Regular`；`system-serif` 汉字同样仍是宋体。
- iOS `generic/platform=iOS` 跑在干净树 `9e01ded1bf5b8a179193f859c5f7b3bc1d32e56a`（产品代码同 `e379209`，只差文档）：命令 `xcodebuild -project Floretta.xcodeproj -scheme Floretta-iOS -destination 'generic/platform=iOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/theme-modes-ios-9e01ded-dd build`，日志 `/tmp/theme-modes-ios-9e01ded.log`，START 2026-11-13 00:28:29 CST，END 00:29:04 CST，`IOS_GENERIC_EXIT 0`，`** BUILD SUCCEEDED **`，`git status` 干净。不得用 `88e6640`、`fe82126` 或 `bd1507f` 的 EXIT 0 代替。
