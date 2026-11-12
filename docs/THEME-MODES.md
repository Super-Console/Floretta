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

中文衬线走系统宋体，不假装拉丁衬线能覆盖汉字。本机（2026-11-12）查询：`Songti SC` → `STSongti-SC-Regular`；`STSong` → `STSong`。

衬线级联顺序：所选拉丁面或系统衬线（New York / Georgia）→ `STSongti-SC-Regular` / `STSong` / `STSongti-TC-Regular` → `Hiragino Mincho ProN`（`HiraMinProN-W3` 在本机可解析）→ `AppleMyungjo`。非衬线：所选拉丁面或系统无衬线（SF）→ `PingFangSC-Regular` → `HiraginoSans-W3` → `AppleSDGothicNeo-Regular`。

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

## 包体（Release + strip，1024 进制 MiB）

门禁仍是 iOS < 15 MB、macOS < 25 MB。

- 加字体前（同一分支、无字体 tip）：iOS 11.4 MB（11,993,182 bytes，2026-11-12 20:33:33 CST）；macOS 17.6 MB（18,419,929 bytes）。
- 加字体后：iOS 12.3 MB（12,901,611 bytes，2026-11-12 20:48:15 CST 前）；macOS 18.4 MB（19,336,424 bytes，`platform=macOS` arm64，2026-11-12 20:51:09 CST）。

## 性能影响

- 内存：本轮按与 `docs/reviews/CANVAS-PERF-BASELINE.md` 相同的协议测量（macOS Release、命令行覆盖 `CODE_SIGN_IDENTITY="Apple Development"` `DEVELOPMENT_TEAM=JY5U4D6JD3`、启动参数 `-FlorettaUITest -FlorettaPerfNodes <N>`、`task_vm_info.phys_footprint`、夹具 50/200/500）。**没有写出可用的峰值内存数字，未编造。** Release 构建本身成功：`/tmp/theme-modes-perf-build.log`，START 2026-11-12 21:57:49 CST，END 21:59:01 CST，EXIT 0；产物 `/tmp/theme-modes-perf-dd/Build/Products/Release/Floretta-macOS.app`。启动后进程存在且 System Events 记为 frontmost/visible，但 **windows=0**，没有 `FLORETTA_PERF_RESULT`，容器内 `~/Library/Containers/net.timhuang.floretta/Data/tmp/canvas-perf-50.json` 仍是 2026-11-12 18:28:18 CST 的旧文件。直接执行二进制出现 `sandbox_extension_issue_file_to_process failed for <app>: 1 (Operation not permitted)`（`/tmp/theme-modes-perf/trial-50.out`，22:03:48–22:04:28 CST，timeout 退出 124）。随后用 entitlements 完整的拷贝 + `open -n -W`（Terminal.app `do script`，`/tmp/theme-modes-perf/open-50.out`，22:15:50 CST）以及今早测通过的 `/tmp/canvasperf/mac-D2.app` 复跑，同样是 0 窗口、无新 JSON。详见 `docs/reviews/theme-modes/PERF-ATTEMPT.md`。不得用包体数字代替本行。
- 帧率：同一协议、同一批启动，**没有写出可用的平均/最低 FPS 数字，未编造。** 失败原因与内存一行相同（无窗口则 `CADisplayLink` 协议无法跑完）。不得用包体数字代替本行。
- 包体：加字体后 iOS 12.3 MB（12,901,611 bytes，2026-11-12 20:48:15 CST）/ macOS 18.4 MB（19,336,424 bytes，`platform=macOS` arm64，2026-11-12 20:51:09 CST），Release+strip，与 `scripts/check-size.sh` 同一口径，1024 进制 MiB，门禁 iOS < 15 / macOS < 25。一次出现过的 macOS 33.0 MB 是 universal `generic/platform=macOS` 二进制，不是门禁数字。

## 截图

在 iPad 模拟器 `ASC-iPadPro13-M5`（UDID `330B63B2-5EE7-477E-B564-EE7C02161EE5`，iOS 27.2）上拍摄。先 `xcrun simctl boot`（BOOT_READY 2026-11-12 22:00:57 CST），再 `xcrun simctl ui … appearance light`，最后用 `xcrun simctl io booted screenshot` 直接抓帧。原图在 `docs/reviews/theme-modes/`。未编造、未从别处复用。

| 文件 | 内容 | 拍摄时间（CST） | 字节 |
| --- | --- | --- | ---: |
| `settings-appearance.png` | 设置页「外观模式」段：经典模式、系统衬线、色值与预览 | 2026-11-12 22:13:31 | 332,993 |
| `inspector-appearance.png` | 编辑器右侧检查器「外观模式」段，画布为经典奶油纸 | 2026-11-12 22:13:46 | 426,389 |
| `classic.png` | 经典模式 + 系统衬线。与上一张在同一界面状态下紧接着拍摄，文件内容相同 | 2026-11-12 22:13:48 | 426,389 |
| `modern.png` | 现代模式：白纸、字体族「跟随系统」、行高 1.20、圆角 8 | 2026-11-12 22:13:55 | 414,650 |
| `custom.png` | 自定义（默认从经典复制）：奶油纸、系统衬线、行高 1.25、圆角 12 | 2026-11-12 22:14:02 | 424,626 |
| `classic-sans.png` | 经典模式把字体族改成 Inter（非衬线） | 2026-11-12 22:14:18 | 420,484 |

日志：`/tmp/theme-modes-shot-poller.log`、`/tmp/theme-modes-shot-test3.log`（`** TEST SUCCEEDED **`，TEST3_EXIT 0）。

## 测试（Asia/Shanghai）

- `swift test --package-path FlorettaCore --filter AppearanceModeTests`：4/0，2026-11-12 21:35:54 CST。
- `xcodebuild test`（Floretta-macOS）：`AppearanceSettingsTests` 4/0（含共享状态与立即同步、三模式切换、经典+非衬线跨重启持久化、标识前缀）、`ThemeFontCascadeTests` 6/0、`ShellTests` 相关 2/0，合计 12/0，2026-11-12 21:37:44 CST，`** TEST SUCCEEDED **`。
- iOS `generic/platform=iOS` 构建（在 tip `88e664048f63c30521e459e6a7194dd9822f26e9` 上重跑，`CODE_SIGNING_ALLOWED=NO`，scheme `Floretta-iOS`，configuration Debug，derivedData `/tmp/theme-modes-ios-88e6640-dd`）：日志 `/tmp/theme-modes-ios-88e6640.log`，START 2026-11-12 21:56:21 CST，END 21:56:48 CST，**EXIT 0**，`** BUILD SUCCEEDED **`。不得把此前声称的 21:39:32 退出码 0 当作已核（那份 `/tmp/theme-modes-step3-ios.log` 是 destination 找不到设备）。
