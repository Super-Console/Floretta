# Supernode

Native mind mapping for Mac, iPad and iPhone — one shared document model, three truly native
interfaces, local-first files you own.

> 产品名 **Supernode** 目前是工作代号（working name）。App Store 与商标最终确认前不改 bundle ID、
> 不改对外文案。名称决策记录见 `docs/DECISIONS.md`。

## 这个仓库是什么

- **目标**：一个 Apple 平台原生思维导图应用（macOS / iPadOS / iOS 三个目标，同一份工程）。
- **不是**：网页套壳、Electron、跨平台壳、XMind 的 fork。
- **参考对象**（只借鉴思想与交互，不复制 GPL 代码）：Mindscape、Brainstorm、SwiftFlow、
  Freeplane、SimpleMindMap。详见 `docs/REFERENCES.md`。

## 硬规则

1. **原生优先**：Swift + SwiftUI 为主，画布等性能敏感处可用 AppKit / UIKit / Core Graphics。
   不允许 WebView 承载核心编辑体验。
2. **本地优先**：不登录也能创建、编辑、保存。默认不联网。
3. **文件可带走**：导图要能导出成通用格式；格式能力矩阵见 `docs/FORMATS.md`。
4. **每一步都要提交并推送**：完成一个可验收的步骤 → 本地 commit → push 到 `main`。
   不允许攒一大批再推。提交信息用 `P0-2: <做了什么>` 形式。
   详见 `docs/WORKFLOW.md`。

## 快速开始

```bash
# 需要 Xcode 26+ / macOS 26+
open Supernode.xcodeproj
```

## 文档

- `TASKBOOK-001.md` — 当前阶段任务书（总指挥写的规格，执行者按批次做）
- `docs/FORMATS.md` — 支持的导入/导出格式与验收方式
- `docs/REFERENCES.md` — 参考的开源实现与可借鉴/不可借鉴的边界
- `docs/WORKFLOW.md` — 分步提交推送规则、验收方式
- `docs/DECISIONS.md` — 决策与理由（含命名）

## 许可

私有仓库，暂未选定开源许可证。发布或公开前必须先在 `docs/DECISIONS.md` 定义。
