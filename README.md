# Floretta

Native mind mapping for Mac, iPad and iPhone — one shared document model, three truly native
interfaces, local-first files you own. Watercolour on paper, not another web dashboard.

## 这个仓库是什么

- **目标**：Apple 平台原生思维导图应用（macOS / iPadOS / iOS 三个 target，同一个工程）。
- **不是**：网页套壳、Electron、跨平台壳、XMind 的 fork。
- **参考对象**（只借鉴思想与交互，不复制 GPL 代码）：Mindscape、Brainstorm、SwiftFlow、
  Freeplane、SimpleMindMap。详见 `docs/REFERENCES.md`。
- **开源**：目标是以开源方式发布；**当前仓库仍为私有**，许可证与公开时点待定
  （见 `docs/DECISIONS.md` D-7）。

## 硬规则

1. **原生优先**：Swift + SwiftUI 为主，画布等性能敏感处可用 AppKit / UIKit / Core Graphics。
   不允许 WebView 承载核心编辑体验。
2. **本地优先**：不登录也能创建、编辑、保存。默认不联网。
3. **文件可带走**：导图要能导出成通用格式；格式能力矩阵见 `docs/FORMATS.md`。
4. **每一步都要提交并推送**：完成一个可验收的步骤 → 本地 commit → push 到 `main`。
   不允许攒一大批再推。提交信息用 `P0-2: <做了什么>` 形式。详见 `docs/WORKFLOW.md`。

## 快速开始

```bash
# 需要 Xcode 26+ / macOS 26+
open Floretta.xcodeproj
```

## 文档

- `TASKBOOK-001.md` — 唯一权威任务书（P0 数据模型 → P1 Mac 画布/键盘 → P2 格式互通 → P3 图标）
- `docs/FORMATS.md` — 支持的导入/导出格式与验收方式
- `docs/REFERENCES.md` — 参考的开源实现与可借鉴/不可借鉴的边界
- `docs/WORKFLOW.md` — 分步提交推送规则、验收方式
- `docs/HANDOFF.md` — 协作交接；第 29 条是版本与安装
- `docs/DECISIONS.md` — 决策与理由（含命名）
- `docs/design/` — 设计素材（App 图标参考图）
- `docs/STATUS.md` — 当前进度

## 命名说明

产品名 **Floretta** 已定（2026-11-09）。GitHub 仓库与本地目录当前仍为 `Supernode`，
重命名由总指挥执行；执行者不要自行改仓库名或 target 名。
