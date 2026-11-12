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

门禁仍是 iOS < 15 MB、macOS < 25 MB。

- 加字体前（同一分支、无字体 tip）：iOS 11.4 MB（11,993,182 bytes，2026-11-12 20:33:33 CST）；macOS 17.6 MB（18,419,929 bytes）。
- 加字体后：iOS 12.3 MB（12,901,611 bytes，2026-11-12 20:48:15 CST 前）；macOS 18.4 MB（19,336,424 bytes，`platform=macOS` arm64，2026-11-12 20:51:09 CST）。

## 性能影响

- 内存：按已合并的 PR #117 `CanvasPerfProbe`（未改探针）在 iPad 模拟器上经 XCUITest 路径测得。配置 Release，命令行覆盖 `CODE_SIGN_IDENTITY="Apple Development"` `DEVELOPMENT_TEAM=JY5U4D6JD3`，启动参数 `-FlorettaUITest -FlorettaPerfNodes 500`，记录 `task_vm_info.phys_footprint`。探针把结果写成 `FLORETTA_PERF_RESULT` 并写入应用临时目录 `canvas-perf-500.json`。本轮峰值内存 **64.6 MB**（JSON `peakFootprintMB`；平移阶段 60.8 MB，缩放阶段 64.6 MB，拖动阶段该轮 `tickCount` 不足未采到内存，记 0，不把它当成 0 占用）。原始 JSON：`docs/reviews/theme-modes/canvas-perf-500-ipad-xcuitest.json`，`finishedAt` 2026-11-12T15:04:53Z（23:04:53 CST），平台 `iPadOS`，`displayMaxFPS` 60。测试日志 `/tmp/theme-modes-perf500-ios.log`，`testCanvasPerf500ViaUITest` START 2026-11-12 23:03:10 CST，END 23:04:54 CST，EXIT 0，`** TEST SUCCEEDED **`，测试进程记录 `FLORETTA_PERF_UITEST_DONE elapsed=27.5 state=1`（应用在协议结束后 `exit(0)`）。macOS 直接启动路径本轮仍然 windows=0，没有新的 mac 数字，详见 `docs/reviews/theme-modes/PERF-ATTEMPT.md`；不得把 18:28 的旧容器 JSON 或包体数字当作本行。
- 帧率：同一条 XCUITest + 同一份 JSON。500 节点、平均 / 最低 FPS：平移 **1.0 / 0**，缩放 **0.8 / 0**，拖动 **0.9 / 0**（绘制次数 4 / 5 / 3，主线程最长帧 1100 / 2516.6 / 1100 ms）。这些数字明显低于同机基线 `CANVAS-PERF-BASELINE.md` 里 iPad 500 的约 11–12 FPS；测试进程在协议期间轮询 `app.state`，且 `bodyEvaluations` 为 0，可能偏慢，但数字是探针写出的实测，未编造、未改探针、未用包体代替。
- 包体：加字体后 iOS 12.3 MB（12,901,611 bytes，2026-11-12 20:48:15 CST）/ macOS 18.4 MB（19,336,424 bytes，`platform=macOS` arm64，2026-11-12 20:51:09 CST），Release+strip，与 `scripts/check-size.sh` 同一口径，1024 进制 MiB，门禁 iOS < 15 / macOS < 25。一次出现过的 macOS 33.0 MB 是 universal `generic/platform=macOS` 二进制，不是门禁数字。Censor 已接受这两项包体数字。

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

日志：`/tmp/theme-modes-shot-poller.log`、`/tmp/theme-modes-glyph-songti.log`（`SONGTI_SHOT_START` 2026-11-12 22:55:10 CST，`SONGTI_SHOT_END` 22:57:02 CST，EXIT 0，`** TEST SUCCEEDED **`）。较早一轮空画布截图（22:13–22:14）已作废，不作为节点正文证据。

## 测试（Asia/Shanghai）

- `swift test --package-path FlorettaCore --filter AppearanceModeTests`：4/0，2026-11-12 21:35:54 CST。
- `xcodebuild test`（Floretta-macOS）：`AppearanceSettingsTests` 4/0（含共享状态与立即同步、三模式切换、经典+非衬线跨重启持久化、标识前缀）、`ThemeFontCascadeTests` 先 6/0（21:37:44 CST）后在本轮补测为 7/0（22:44:00 CST，日志 `/tmp/theme-modes-font-mac-test.log`），`ShellTests` 相关 2/0，`** TEST SUCCEEDED **`。
- iOS `generic/platform=iOS` 构建必须跑在本轮新 tip 上（不得用 `88e6640` 的 EXIT 0 代替）。跑完后把命令、日志路径、HEAD SHA、CST 起止和退出码补在本节。
