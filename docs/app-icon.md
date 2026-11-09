# App 图标

参考图是 `docs/design/app-icon-reference.png`：1254×1254，8-bit RGB，无 alpha，无 ICC。画面是一张已经带圆角和投影的纸，圆角外面是白边。系统还会再套一次圆角，所以不能把这张图直接当成 1024 图标。

## 做法

脚本是 `scripts/make-app-icon.py`。这台云机器没有 `sips`，也没有 CoreGraphics，脚本用 Pillow 把文件写出来。Pillow 只在生成时使用，不进 App，也不进 Xcode 工程。

1. 纸面和陶土水彩原样拷贝。浅纸纤维、笔触边缘都留着，不重绘、不对称化、不锐化。
2. 白边、投影，以及紧贴旧圆角的一圈浅边，不算纸面。它们连到正方形外缘，内部的浅色纤维不算。
3. 这圈以外的像素，用边界内侧的纸面沿法线反射补上。角上因此是同一张纸的颗粒，不是另一块白，也不会留下第二道圆角。
4. 反射采到墨色或采空时，才退回一块干净纸面。正常角上走不到这一步。
5. 用 Lanczos 缩到目录里的每个尺寸。Lanczos 偶尔会把纸色冲成偏白，这种过冲被拉回纸的色域（红通道比蓝通道至少高 20）。水彩本身离这条线很远，不会被改。
6. 写出不带 alpha 的 PNG，并写入 sRGB ICC（描述为 “sRGB built-in”）。

深色 / Tinted 变体没有另做。参考图只有这一张浅纸画，深色图标等于重画，任务书不允许。系统可以自己着色。浅纸加陶土在着色后仍然是一块纸上的记号，不另作一张。

## 放在哪

两个 target 原来的目录都填了，`ASSETCATALOG_COMPILER_APPICON_NAME` 仍是 `AppIcon`，没有改 target 名。

| 目录 | 内容 |
|---|---|
| `Floretta/macOS/Assets.xcassets/AppIcon.appiconset` | macOS 16 / 32 / 128 / 256 / 512 的 1x 和 2x |
| `Floretta/iOS/Assets.xcassets/AppIcon.appiconset` | iOS / iPadOS 通用 1024 |
| `Floretta/Resources/Assets.xcassets/AppIcon.appiconset` | 上面全部，再加 1024 主图 |

`Resources` 那份没有加进 `project.pbxproj`。两个 target 已经各有一份 App Icon，再编进同一份会重名。

重新生成：

```bash
python3 scripts/make-app-icon.py
```
