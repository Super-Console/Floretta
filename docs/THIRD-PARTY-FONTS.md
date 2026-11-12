# 第三方字体

本仓库随 App 分发的开源字体、体积、PostScript 名与许可。系统字体（Songti SC / STSong、PingFang、New York / Georgia、SF）不随包分发，只在运行时按实际 PostScript 名级联。

门禁仍是 `scripts/check-size.sh`：iOS 严格小于 15 MB，macOS 严格小于 25 MB（1024 进制 MiB，Release + strip）。

## 随包分发（拉丁 Regular 子集，OFL）

七个 Regular 面合计 **842,556 bytes（约 0.80 MiB）**。路径：`Floretta/Resources/Fonts/`。许可原文在 `Floretta/Resources/Fonts/licenses/`。

| 目录 id | 显示名 | 文件 | 字节 | PostScript 名 | 许可 |
| --- | --- | --- | --- | --- | --- |
| `eb-garamond` | EB Garamond | `EBGaramond-Regular.otf` | 208,892 | `EBGaramond-Regular` | SIL OFL 1.1（`licenses/EBGaramond-OFL.txt`） |
| `crimson-pro` | Crimson Pro | `CrimsonPro-Regular.otf` | 64,384 | `CrimsonPro-Regular` | SIL OFL 1.1（`licenses/CrimsonPro-OFL.txt`） |
| `libre-baskerville` | Libre Baskerville | `LibreBaskerville-Regular.otf` | 110,872 | `LibreBaskerville-Regular` | SIL OFL 1.1（`licenses/LibreBaskerville-OFL.txt`） |
| `noto-serif` | Noto Serif | `NotoSerif-Regular.otf` | 80,940 | `NotoSerif-Regular` | SIL OFL 1.1（`licenses/NotoSerif-OFL.txt`） |
| `inter` | Inter | `Inter-Regular.otf` | 222,940 | `Inter-Regular` | SIL OFL 1.1（`licenses/Inter-LICENSE.txt`） |
| `ibm-plex-sans` | IBM Plex Sans | `IBMPlexSans-Regular.otf` | 80,656 | `IBMPlexSans` | SIL OFL 1.1（`licenses/IBMPlex-LICENSE.txt`） |
| `noto-sans` | Noto Sans | `NotoSans-Regular.otf` | 73,872 | `NotoSans-Regular` | SIL OFL 1.1（`licenses/NotoSans-OFL.txt`） |

这些面只覆盖拉丁（及各自子集里的符号）。**不得把它们当成中文衬线。** 中文衬线走系统宋体，本机实测 PostScript 名：

- 查询 `Songti SC` → `STSongti-SC-Regular`（家族 `Songti SC`）
- 查询 `STSong` → `STSong`（家族 `STSong`）

衬线级联顺序：所选拉丁面（或系统衬线 New York / Georgia）→ `STSongti-SC-Regular` / `STSong` / `STSongti-TC-Regular` → `Hiragino Mincho ProN`（实测 `HiraMinProN-W3`）→ `AppleMyungjo`。非衬线：所选拉丁面或系统无衬线（「跟随系统」，SF）→ `PingFangSC-Regular` → `HiraginoSans-W3` → `AppleSDGothicNeo-Regular`。

目录里的 `system-serif`（系统衬线）与 `system-sans`（显示名「跟随系统」）没有随包字体文件。

## 未随包：思源宋体 / Source Han Serif / Noto Serif CJK

Noto Serif CJK 与思源宋体是同一套设计，不得再打包一份完整 TTC（完整 `NotoSerifCJK.ttc` 解压约 163 MB）。按批准条件，仅当 GB2312+拉丁子集 ≤ 3,145,728 bytes（3 MB）时才加入思源宋体。

实测：从 `NotoSerifCJKsc-Regular` 做成 GB2312+拉丁子集（8,087 个码位）后，文件 `SourceHanSerifSC-Regular.otf` 为 **4,876,368 bytes（4.65 MiB）**，超过上限，**因此未加入仓库、也未加入 App 包**。该子集的 PostScript 名仍是 `NotoSerifCJKsc-Regular`。不要把它拷进 `Floretta/Resources/Fonts/`。

## 本轮包体（Release + strip，与 `scripts/check-size.sh` 相同口径）

在分支 `feat/theme-modes`、加入上述七个拉丁面之后实测（2026-11-12，Asia/Shanghai）：

- 加字体前（同一分支、当时 tip 仅有骨架与路线图，无字体）：iOS **11.4 MB**（11,993,182 bytes，2026-11-12 20:33:33 CST）；macOS **17.6 MB**（18,419,929 bytes，同一时刻）。
- 加字体后：iOS **12.3 MB**（12,901,611 bytes，`generic/platform=iOS`，2026-11-12 20:48:15 CST 前测完）；macOS **18.4 MB**（19,336,424 bytes，`platform=macOS` arm64，2026-11-12 20:51:09 CST）。
- 均低于门禁 iOS < 15 MB、macOS < 25 MB。未把思源宋体子集打进包。
