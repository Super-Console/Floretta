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

| 项 | 对照 `8e50c12`（2026-11-12 23:16） | 对照 `8e50c12` 同参数重测（2026-11-13 00:25） | 上轮产品 `e379209` 干净树（00:21） | 上轮产品 `9a92549` 干净树（00:43） | 上轮产品 `ebe0874` 干净树（01:33） | 本 tip `aef98b0` 干净树（03:06）；产品代码 `44723d0` |
| --- | --- | --- | --- | --- | --- | --- |
| HEAD | `8e50c1212d9f784ec6b38ba434f8c77cb9206cf6` | 同左，`git archive` 到 `/tmp/theme-modes-8e50c12-remeasure` | `e379209963e8ee5ccfa6314ede7d52c303b3e42c` | `9a92549e0d68f26ab9e8fcca079df64de9b1aa6e` | `ebe08747bab4174f66b305734ee14206f1c1d58a` | `aef98b0f2073fd5b68ac959458c976394016341a`（实测 SHA。产品代码是 typography 修复 `44723d0246b31722acf988adb7ee0b8dfd145372`；`aef98b0` 相对它只差文档与捏合图，产品 diff 为空。不得把 `ebe0874` 的 57.2 / 50 或 65.2 MB 写成这一列） |
| 工作树 | 当时的对照 tip | 隔离归档，未改其它 worktree | 日志打印 `HEAD=e379209…`，`GIT_STATUS_PORCELAIN` 为空 | 日志打印 `HEAD=9a92549…`，`GIT_STATUS_PORCELAIN` 为空（测量前与测量后都干净） | 日志打印 `HEAD=ebe08747bab4174f66b305734ee14206f1c1d58a`，`GIT_STATUS_PORCELAIN` 在测量前与测量后均为空 | 日志打印 `HEAD=aef98b0f2073fd5b68ac959458c976394016341a`，`GIT_STATUS_PORCELAIN` 在测量前与测量后均为空（`GIT_STATUS_PORCELAIN_BEGIN` / `_END` 之间无内容） |
| 日志 | `/tmp/theme-modes-baseline-perf500.log` START 2026-11-12 23:15:21，END 23:16:58，EXIT 0，`** TEST SUCCEEDED **` | `/tmp/theme-modes-baseline-perf500-remeasure.log` START 2026-11-13 00:23:54，END 00:25:33，EXIT 0，`** TEST SUCCEEDED **`，`FLORETTA_PERF_UITEST_DONE elapsed=25.2` | `/tmp/theme-modes-perf500-e379209.log` START 00:20:11，END 00:21:51，EXIT 0，`** TEST SUCCEEDED **`，elapsed=24.6 | `/tmp/theme-modes-perf500-9a92549.log` START 00:41:52，END 00:43:53，EXIT 0，`** TEST SUCCEEDED **`，`FLORETTA_PERF_UITEST_DONE elapsed=25.5` | `/tmp/theme-modes-perf500-ebe0874.log` START 2026-11-13 01:32:18，END 01:33:53 CST，EXIT 0，`** TEST SUCCEEDED **`，`FLORETTA_PERF_UITEST_DONE elapsed=24.1` | `/tmp/theme-modes-perf500-aef98b0.log` START 2026-11-13 03:04:12，END 03:06:37 CST，EXIT 0，`** TEST SUCCEEDED **`，`FLORETTA_PERF_UITEST_DONE elapsed=24.4` |
| JSON | `docs/reviews/theme-modes/canvas-perf-500-ipad-baseline-8e50c12.json`，`finishedAt` 2026-11-12T15:16:56Z（23:16:56 CST） | `docs/reviews/theme-modes/canvas-perf-500-ipad-baseline-8e50c12-remeasure.json`，`finishedAt` 2026-11-12T16:25:32Z（00:25:32 CST），sha256 `5c320750…` | `docs/reviews/theme-modes/canvas-perf-500-ipad-e379209.json`，`finishedAt` 2026-11-12T16:21:50Z（00:21:50 CST），sha256 `c19dbd0f…` | `docs/reviews/theme-modes/canvas-perf-500-ipad-9a92549.json`，`finishedAt` 2026-11-12T16:43:51Z（00:43:51 CST），sha256 `1de8960e…` | `docs/reviews/theme-modes/canvas-perf-500-ipad-ebe0874.json`，`finishedAt` 2026-11-12T17:33:51Z（01:33:51 CST），sha256 `5b5c0b221d1b41cbdbfdc68015f611949fd82afca6e12b234a7b4220850bb60a` | `docs/reviews/theme-modes/canvas-perf-500-ipad-aef98b0.json`，`finishedAt` 2026-11-12T19:06:35Z（03:06:35 CST），sha256 `de04e53c317b5c58e5dbc9bac88274b474a95824afc26fce080f94b02c83f3d4` |
| 峰值内存 | 97.4 MB | 105.2 MB | 94.3 MB | 92.8 MB | 65.2 MB（`ebe0874` 当时测到的数；不把那次下降写成已证实的缓存收益，也不得当作本 tip 的峰值） | 93 MB（JSON `peakFootprintMB`；同探针、`nodes: 500`，缩放 `maxVisibleNodes` 仍是 67。这是本 SHA 测到的数，不得写成已证实的缓存收益，也不得再用 `ebe0874` 的 65.2 MB 代替） |
| 平移 平均 / 最低 FPS | 59.7 / 58（179 次绘制） | 59.3 / 56（179 次绘制） | 59.0 / 56（178 次绘制） | 59.7 / 58（179 次绘制） | 59.7 / 58（179 次绘制） | 58.7 / 52（177 次绘制） |
| 缩放 平均 / 最低 FPS | 57.3 / 50（344 次绘制） | 55.5 / 40（334 次绘制） | 54.2 / 42（326 次绘制） | 55.3 / 44（333 次绘制） | 57.2 / 50（344 次绘制） | **57.7 / 50（346 次绘制）** |
| 拖动 平均 / 最低 FPS | 59.7 / 58（180 次绘制） | 59.7 / 58（180 次绘制） | 59.7 / 58（179 次绘制） | 59.7 / 58（179 次绘制） | 59.7 / 58（180 次绘制） | 59 / 58（178 次绘制） |

上轮 `e379209` 已去掉缓存读路径上每帧、每节点的 `NSLock`：`draw` 开头 `ThemeFontCascade.beginFrame()` 拍一份不可变表，再按本帧可见节点的 (design, size) 一次性解析，绘制只读 CTFont 引用。那一轮干净树缩放是 54.2。根因是缓存键按 1/64 pt 量化字号，捏合时字号连续变化，几乎每帧都未命中，热路径仍在每帧调用 `CTFontCreateCopyWithAttributes`。

上轮产品 `9a92549` 把字号按最近的 0.5 pt 再写入缓存键，并给已按尺寸拷贝的 CTFont 表加上 256 条容量上限与 LRU（每帧在 `prepareCanvasFonts` 里一次性更新近用顺序，命中路径不加锁）。画布仍然把缓存里的真实 `UIFont`/`CTFont` 写进 `NSAttributedString`，不能退回 `Font.system(design:)`。那一轮干净树缩放是 55.3 / 44，与同批重测对照 55.5 差 0.2。

固定 0.5 pt 桶在缩小端跳变偏大：20 pt 时 0.5 pt 是 2.5%，4 pt 时是 12.5%。本 tip 产品代码 `ebe0874` 改为按 `log` 等距、比值 1.02 的相对步长量化后再入键：`sizeTicks = round(log(size) / log(1.02))`，返回并用于 `CTFontCreateCopyWithAttributes` 的字号是该桶值 `1.02^ticks`，相邻桶在任意字号下相差至多 2%。256 条 LRU 与每帧快照、命中不加锁、把真实家族写进 attributed string 的路径都保留。

上轮干净树 `ebe0874` 缩放平均 / 最低是 57.2 / 50（344 次绘制），峰值 65.2 MB，平移和拖动 59.7 / 58。那是 `ebe0874` 的实测，不得再写成 typography 修复之后的数。

本 tip 已在已提交、干净的 `aef98b0` 上重测（产品代码 `44723d0`，相对它只差文档与捏合图）。日志 `/tmp/theme-modes-perf500-aef98b0.log` 03:04:12–03:06:37 CST，`TIP_PERF500_EXIT 0`，`** TEST SUCCEEDED **`，`FLORETTA_PERF_UITEST_DONE elapsed=24.4`，`HEAD=aef98b0f2073fd5b68ac959458c976394016341a`，测量前后 `GIT_STATUS_PORCELAIN` 为空。JSON `docs/reviews/theme-modes/canvas-perf-500-ipad-aef98b0.json`，`finishedAt` 2026-11-12T19:06:35Z（03:06:35 CST），sha256 `de04e53c317b5c58e5dbc9bac88274b474a95824afc26fce080f94b02c83f3d4`。平移 **58.7 / 52**（177 次绘制），缩放 **57.7 / 50**（346 次绘制），拖动 **59 / 58**（178 次绘制），峰值内存 **93 MB**。缩放必须写成 57.7 / 50，不能写成「57–60」，也不得再用 `ebe0874` 的 57.2 / 50。与晚间对照原测 57.3 / 50 差 0.4，与 00:25 重测对照 55.5 / 40 差 2.2，与 `ebe0874` 的 57.2 / 50 差 0.5；对照自身也曾从 57.3 落到 55.5，探针噪声大约 ±2，无跨量级差异。平均 57.7 达到 ≥55 的数字门禁；最低 50 不是平均门禁的通过项。峰值 93 MB 是本次测到的数，不得写成已证实的缓存收益，也不得用 `ebe0874` 的 65.2 MB 代替。通过与否留给审查者判断，这里不自行宣布通过。

`fae6453` 回归仍以 `/tmp/theme-modes-perf500-tip-confirm.log`（23:18:43–23:19:29 CST，EXIT 0）和 `docs/reviews/theme-modes/canvas-perf-500-ipad-fae6453-before-fix.json`（`finishedAt` 2026-11-12T15:19:27Z）为准：峰值 89.2 MB，平移 1.0 / 0，缩放 0.8 / 0，拖动 0.9 / 0。原因是每一帧为每个可见节点现场构建带级联的 CTFont。macOS 直接启动路径仍然 windows=0，本对照只走 XCUITest，见 `docs/reviews/theme-modes/PERF-ATTEMPT.md`。

- 上轮产品 `e379209963e8ee5ccfa6314ede7d52c303b3e42c` 干净树实测：iOS 12.3 MB（12,935,015 bytes，产物 mtime 2026-11-13 00:26:43 CST）；macOS 18.5 MB（19,404,712 bytes，可执行文件 mtime 00:27:13 CST，`platform=macOS` arm64）。日志 `/tmp/theme-modes-size-e379209.log`，START 00:26:15，END 00:27:13 CST，`SIZE_E379209_SCRIPT_EXIT 0`。
- 上轮产品 `9a92549e0d68f26ab9e8fcca079df64de9b1aa6e` 干净树实测：iOS 12.4 MB（12,951,415 bytes，产物 mtime 2026-11-13 00:45:20 CST）；macOS 18.5 MB（19,404,744 bytes，可执行文件 mtime 00:45:53 CST，`platform=macOS` arm64）。日志 `/tmp/theme-modes-size-9a92549.log`，START 00:44:47，END 00:45:53 CST，`SIZE_9A92549_SCRIPT_EXIT 0`，HEAD 即 `9a92549`，测量前后 `git status` 干净。
- 上轮产品代码 `ebe08747bab4174f66b305734ee14206f1c1d58a` 干净树实测：iOS 12.4 MB（12,953,439 bytes，产物 mtime 2026-11-13 01:35:11 CST）；macOS 18.5 MB（19,423,352 bytes，可执行文件 mtime 01:36:00 CST，`platform=macOS` arm64）。日志 `/tmp/theme-modes-size-ebe0874.log`，START 01:34:21，END 01:36:00 CST，`SIZE_EBE0874_SCRIPT_EXIT 0`，HEAD 即 `ebe08747bab4174f66b305734ee14206f1c1d58a`，测量前后 `git status` 干净。不得用这组字节代替下面本 SHA 的产物。
- 产品代码 `44723d0246b31722acf988adb7ee0b8dfd145372` 干净树实测：iOS 12.4 MB（12,970,647 bytes，产物 mtime 2026-11-13 02:41:42 CST）；macOS 18.5 MB（19,441,560 bytes，可执行文件 mtime 02:42:32 CST，`platform=macOS` arm64）。日志 `/tmp/theme-modes-size-44723d0.log`，START 02:40:53 CST；脚本打印两行预算并通过，包装层随后在只读变量 `status` 赋值处退出，END 行是同一轮已 strip 产物上补记的。不得用 `ebe0874` 的 12,953,439 / 19,423,352 代替。
- 本 tip `aef98b0f2073fd5b68ac959458c976394016341a` 干净树重跑 `scripts/check-size.sh`（产品代码与 `44723d0` 相同，只有文档和图）：iOS 12.4 MB（12,970,647 bytes，产物 mtime 2026-11-13 03:07:18 CST）；macOS 18.5 MB（19,441,560 bytes，可执行文件 mtime 03:07:22 CST，`platform=macOS` arm64）。字节与 `44723d0` 那次相同。日志 `/tmp/theme-modes-size-aef98b0.log`，START 03:07:12，END 03:07:22 CST，`SIZE_AEF98B0_SCRIPT_EXIT 0`，脚本打印 `iOS: 12.4 MB (limit < 15 MB)` 与 `macOS: 18.5 MB (limit < 25 MB)`，无 FAIL。HEAD 即 `aef98b0f2073fd5b68ac959458c976394016341a`，测量前后 `git status` 干净。字节是对这次已 strip 产物按脚本同一口径 `find … stat -f %z` 求和得到的，同一包装层用 `rc` 接住退出码，没有再踩只读 `status`。均低于 iOS < 15 / macOS < 25。随后若只有文档入树，包体数字仍以这次产物为准。

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

| `pinch-100.png` | 同一份字形样本，经典 + EB Garamond，把画布连续缩放到 100% 后抓帧。中心节点标题完整显示「字形样本」。左上角调试标 `pinch scale 100%`，右下角状态条缩放档也是 100% | 2026-11-13 02:34:35 | 501,800 |
| `pinch-85.png` | 同一进程、同一文档，连续缩放到 85%。中心节点标题完整。调试标 `pinch scale 85%`，状态条缩放档显示 75%（见下方说明） | 2026-11-13 02:34:40 | 495,939 |
| `pinch-70.png` | 同一进程、同一文档，连续缩放到 70%。中心节点标题完整显示「字形样本」（`30e2e91` 同位置曾被裁成「字形…」）。调试标 `pinch scale 70%`，状态条缩放档显示 75% | 2026-11-13 02:34:45 | 475,202 |
| `pinch-55.png` | 同一进程、同一文档，连续缩放到 55%。中心节点标题完整显示「字形样本」。调试标 `pinch scale 55%`，状态条缩放档显示 50% | 2026-11-13 02:34:50 | 468,492 |

已通过的 classic / modern / classic-sans 三张未重拍。EB Garamond 对照日志：`/tmp/theme-modes-eb-shot-poller.log`、`/tmp/theme-modes-eb-shot.log`（`EB_SHOT_START` 2026-11-12 23:31:29 CST，`EB_SHOT_END` 23:33:34 CST，EXIT 0，`** TEST SUCCEEDED **`）。经典/现代重拍日志仍是 `/tmp/theme-modes-shot-poller.log`、`/tmp/theme-modes-glyph-songti.log`（`SONGTI_SHOT_START` 2026-11-12 22:55:10 CST，`SONGTI_SHOT_END` 22:57:02 CST，EXIT 0）。本 tip 捏合四张是在已提交、干净的 `44723d0` 上重拍的：日志 `/tmp/theme-modes-pinch-shot-44723d0.log`（`PINCH_SHOT_START` 2026-11-13 02:33:07 CST，`PINCH_SHOT_END` 02:34:52 CST，`PINCH_SHOT_EXIT 0`，`** TEST SUCCEEDED **`，`HEAD=44723d0246b31722acf988adb7ee0b8dfd145372`，拍摄前与拍摄后 `GIT_STATUS_PORCELAIN` 均为空）；poller `/tmp/theme-modes-pinch-shot-44723d0-poller.log`，四张先写到 `/tmp/theme-modes-pinch-44723d0/` 再拷入本目录，mtime 02:34:35–02:34:50 CST。01:31 那一轮（`/tmp/theme-modes-pinch-shot.log`，当时入树的是 `30e2e91` 附近的图）里 70% 中心标题被裁成「字形…」，已替换，不得再当本 tip 证据。较早一轮空画布截图（22:13–22:14）已作废，不作为节点正文证据。

### 捏合图左上角 55% 与右下角 50% 为什么不同

这不是调试标签和画布不同步，也不是标签写错了档位。两处读的不是同一个数。

- 左上角 `uitest.heldCanvasScale` 只在 `-FlorettaPinchShot` 启动时出现，文案是 `pinch scale \(Int((camera.viewport.scale * 100).rounded()))%`，也就是**当前视口的连续缩放**，四舍五入到整数百分比。测试用 `CanvasScaleHook` 把画布停在 `MagnifyGesture.onChanged` 那种中间值（100 / 85 / 70 / 55），并且在 `pinchGesture.onEnded` 里关掉对合法 `ZoomStop` 的回吸，所以 55% 这一张的视口就是 0.55，标签写 55%。
- 右下角状态条芯片显示的是 `camera.chrome.zoomPercent`。`CanvasChrome.syncZoomPercent(toScale:)` 的注释写明「chrome percent is always a legal stop, never a raw value such as 137」，实现是 `ZoomStop.displayPercent(forScale:)` → `ZoomStop.nearest(to:)`。合法档只有 50、75、100、125、150、200、300、400。0.55 离 0.50 的距离是 0.05，离 0.75 是 0.20，所以芯片显示 50%。同一组图也符合这条规则：85% 的芯片是 75%（离 75 差 10，离 100 差 15），70% 的芯片是 75%（离 75 差 5，离 50 差 20），100% 的芯片是 100%。

也就是说，55% 那张里画布和字形按连续 55% 来画，芯片只是把这个连续值显示成最近的合法缩放档。Hubert 此前看过 01:31 那一轮四张，确认 100% 与 55% 下中英日韩内容连续、都是衬线、没有字形跳变、长句仍正确换行；那些图不能当作本 tip 中心标题未裁切的证据。

### 中心节点标题「字形样本」在 70% / 55% 被裁切

对照实验用同一份 `glyph-sample.floretta`、同一块中心节点裁切、同一 70% 视口。基线 `8e50c12`（日志 `/tmp/theme-modes-baseline-pinch-shot.log`，2026-11-13 02:20:59–02:23:05 CST，EXIT 0）中心节点四个字「字形样本」都在；分支 `30e2e91` 同一位置只剩「字形…」。这是本变化引入的回归，不是预先就有的。

最初的混判是：100% / 85% 两侧都完整；70% 基线完整、tip 被裁（新问题）；55% 两侧都被裁，当时当成既有问题。Hubert 后来独立确认 70% 必须修，并把验收收紧为：同一文档在 100% / 85% / 70% / 55% 四个停点，中心节点都必须完整显示「字形样本」，与基线一致；55% 不得再当成既有问题留下。

排查结论：

1. **真正的原因是排版用 Helvetica / 系统 UI 测宽，绘制走字体级联，不是 log 桶字号不一致。** 70% 时桶量化只有约 +0.10%，解释不了裁切（Censor 亦作此纠正，不得再把根因写成测量字号与 log 桶对不上）。排版仍走 `TextMeasurementCache` 的 Helvetica → 系统 UI（`.AppleSystemUIFont`）测宽，绘制却走 `ThemeFontCascade`（本轮捏合是经典 + EB Garamond，汉字级联宋体 / 本模拟器回退 PingFang）。「字形样本」36 pt 时，系统 UI 画布宽 136.42、加 24 pt 边距后排成 161；宋体/苹方画布宽 144、排成 168。交叉（测量用系统 UI、绘制用宋体）时可用宽度按 `laidOut * scale − 12`（绘制 `textRect = rect.insetBy(dx: 6, dy: 4)`，这 12 px 是视图像素，不随缩放变）：100% 余量 +4.89 能放下；85% +1.85 能放下；70% −0.20 溢出，与 `30e2e91` 截图一致；55% −3.01 溢出。同一张脸（宋体测、宋体画）时 70% +4.70 能放下，55% 只剩 +0.84。
2. **不是缩放后复用了旧档位缓存的排版宽度。** 节点宽度在画布坐标里计算，不随视口缩放缓存一版旧宽度。
3. **选中态描边 / 手柄和固定的视图像素内边距会吃掉可用宽度**，缩放越低，那 12 px 内边距占的比例越大。这与测宽/绘制字体不一致叠在一起，才在 70% 裁字。

产品修复在 `44723d0246b31722acf988adb7ee0b8dfd145372`（Measure canvas titles with the painted font cascade）：有 appearance profile 时，标题宽度改用绘制同一套 `ThemeFontCascade.cachedCTFont(familyID:nodeDesign:size:)` 来测（`ThemeAwareFontMetrics`，因 `FontMetricsPort` 不能直接依赖 `ThemeFontCascade`，以免编进分享扩展）。修复后同一份文档、干净树上的官方四张里，100% / 85% / 70% / 55% 的中心节点都完整显示「字形样本」，没有再改视图像素内边距或选中态手柄。注意：70% / 55% 图左上导航栏标题仍可能显示「字…」，那是返回按钮挤掉了导航栏文案，不是中心节点，也不在这项验收里。

对照 typography 的说明：基线 `8e50c12` 捏合图是该提交的默认外观；本 tip 四张是经典 + EB Garamond。比较的是同一文档、同一中心节点、同一 70% 裁切，不是同一默认字体。

### 已知残留路径（不是本轮硬阻断）

下列路径仍与「闲置画布标题按绘制字体测宽」不一致。本轮不修，也不是中心节点截断的阻断项：

- `fontFamilyID` 为空时，`TextMeasurementCache` / `ThemeAwareFontMetrics` 仍走历史 Helvetica → 系统 UI 测宽。
- 编辑态 `NodeTextEditor` 仍默认使用四参数 `CoreTextFontMetrics()`，不走 `ThemeAwareFontMetrics`。
- `MapExport.images`（`ImageExportLoader.images`）用没有 appearance profile 的 `LayoutEngine()` 计算节点宽。
- 徽章与区域标签仍用 `Font.system`（例如 `InfiniteCanvas` 里徽章和区域标签，以及 `MapExport` 里的区域标签）。

### 字体缓存 LRU 未命中 / 淘汰计数

测试可见计数器：`resolvedFontCacheMissCountForTests` / `resolvedFontCacheEvictCountForTests`。新的尺寸化 CTFont 发布时记一次 miss，从键表里去掉时记一次 evict。官方干净树日志 `/tmp/theme-modes-font-mac-44723d0.log`（`FONT_MAC_OFFICIAL_START` 2026-11-13 02:38:31 CST，`FONT_MAC_OFFICIAL_END` 02:39:04 CST，`FONT_MAC_OFFICIAL_EXIT 0`，`** TEST SUCCEEDED **`，`HEAD=44723d0246b31722acf988adb7ee0b8dfd145372`，`GIT_STATUS_PORCELAIN` 为空）打印的实际计数是：

- 50%↔400% 极端往返（先到百分之五十再到百分之四百再回来）：`FLORETTA_FONT_CACHE_50_400 outbound miss=106 evict=0 count=106; round-trip miss=106 evict=0 count=106`
- 多 design 场景：`FLORETTA_FONT_CACHE_MULTI_DESIGN miss=1053 evict=797 count=256 cap=256`（1053 − 256 = 797）


## 测试（Asia/Shanghai）

- `swift test --package-path FlorettaCore --filter AppearanceModeTests`：4/0，2026-11-12 21:35:54 CST。
- `xcodebuild test`（Floretta-macOS）：`AppearanceSettingsTests` 4/0（含共享状态与立即同步、三模式切换、经典+非衬线跨重启持久化、标识前缀）。`ThemeFontCascadeTests` 在干净产品 tip `44723d0246b31722acf988adb7ee0b8dfd145372` 上是 14/0（2026-11-13 02:38:31–02:39:04 CST，日志 `/tmp/theme-modes-font-mac-44723d0.log`，`FONT_MAC_OFFICIAL_EXIT 0`，`** TEST SUCCEEDED **`，14 passed / 0 failed，`HEAD=44723d0246b31722acf988adb7ee0b8dfd145372`，`GIT_STATUS_PORCELAIN` 为空）。本轮新增 `testFontCacheCountsForFiftyToFourHundredPercentRoundTrip`、`testFontCacheCountsForMultiDesignScenario`、`testGlyphSampleTitleWidthAtSeventyPercentFitsPaintedCascade`，并保留相对步长量化与 LRU 用例。`eb-garamond` 的 “Hello” 仍是 `EBGaramond-Regular`，汉字仍是 `STSongti-SC-Regular`；`system-serif` 汉字同样仍是宋体。不得用 `ebe0874` / `30e2e91` 的 11/0 代替本 SHA 的 14/0。
- iOS `generic/platform=iOS` 跑在干净产品 tip `44723d0246b31722acf988adb7ee0b8dfd145372`：命令 `xcodebuild -project Floretta.xcodeproj -scheme Floretta-iOS -destination 'generic/platform=iOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/theme-modes-ios-44723d0-dd build`，日志 `/tmp/theme-modes-ios-44723d0.log`，START 2026-11-13 02:39:59 CST，END 02:40:24 CST，`IOS_GENERIC_EXIT 0`，`** BUILD SUCCEEDED **`，HEAD 即 `44723d0…`，`git status` 干净。不得用 `ebe0874`、`30e2e91` 或更早 tip 的 EXIT 0 代替。
