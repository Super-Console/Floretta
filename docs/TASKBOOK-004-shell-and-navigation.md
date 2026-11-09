# TASKBOOK-004 — 外壳与导航（首页 / Tab / 整数缩放 / Zen 模式）

来源：Timmy 2026-11-09 口述需求。以下为**验收标准**，不是建议。

## P5-1 启动进入首页（Library），不是画布

现状问题：App 一打开就是导图画布。不对。

要求：

- 启动进入**首页**，没有任何文档时显示空状态；**只有打开/新建了文档才进画布**。
- 首页顶部是大标题 `Floretta`（iOS 用 `.navigationTitle` + `.navigationBarTitleDisplayMode(.large)`；
  macOS 用窗口标题 + 工具栏标题），风格对齐系统 App，**不自绘标题**。
- 首页主体是**用户最近打开的导图**（像达芬奇的项目管理器）：文件名、修改时间，至少两列网格或列表，
  用系统 `List` / `LazyVGrid`，禁止自绘卡片阴影和自定义行。
- 右上角两个系统按钮：**新建（+）**、**设置（齿轮）**，用 `Button` + SF Symbol。
- 首页必须有 **「从文件 App 打开」** 按钮：`.fileImporter`，`allowedContentTypes` 只列我们支持的格式
  （`.floretta`、`.mm`、`.opml`、`.md`），选择后进入画布。
- 「最近打开」用系统持久化（`NSDocumentController` 的最近文档或自建 `UserDefaults` 记录 + security-scoped bookmark），
  **不要**扫描用户整个磁盘。

## P5-2 Tab 栏：首页 / 设置

- iOS/iPadOS 用系统 `TabView`，两个 tab：`首页`、`设置`；外观由系统决定（iOS 26 自动液态玻璃），
  **不许自定义 tab bar 背景、圆角、模糊**。
- macOS 不做 tab 栏，用 `Settings` scene（⌘,）+ 主窗口，符合 Mac 习惯。

## P5-3 设置页（第一批）

用系统 `Form` + `Section`：

| 项 | 控件 |
|---|---|
| 语言 | `Picker`（跟随系统 / 简体中文 / English） |
| 外观 | `Picker`（跟随系统 / 浅色 / 深色） |
| 新建时默认视图 | `Picker`（地图模式 / 聚焦模式） |
| PNG 导出倍率 | `Picker`（1x / 2x / 3x） |
| PNG 背景 | `Picker`（白色 / 透明） |
| 关于 | 版本号、`NOTICE` 开源致谢入口 |

设置项要真正生效（写入 `UserDefaults` 并被子系统读取），不许只做 UI。

## P5-4 缩放必须是整数倍

现状问题：「放大缩小不是整数倍」，出现 137% 这类数字。

要求：

- 缩放档位固定为 **50% / 75% / 100% / 125% / 150% / 200% / 300% / 400%**。
- 手势缩放结束后**吸附到最近档位**；显示百分比必须取整，**任何界面都不出现非整数百分比**。
- 100% 必须是"1 个逻辑点 = 1 个渲染点"的真实比例，不许叠加额外系数。
- 单测覆盖：档位枚举、吸附函数（任意输入 → 合法档位）、100% 的实际 scale 值。

## P5-5 Zen / 全屏模式（三端都要）

- 进入后**隐藏所有按钮**：工具栏、tab 栏、状态栏、侧栏、检查器全部消失，只剩画布内容。
- iOS：`.toolbar(.hidden, for: .navigationBar/.tabBar)` + `.statusBarHidden`；
  macOS：隐藏工具栏与侧栏，可选 `toggleFullScreen`。
- 退出方式必须存在且不打扰：**Esc 键**、**双击画布空白**、或四角/边缘轻扫任选其一（实现两个以上）。
- 进入 Zen 不能改变文档内容、不能丢失选中状态。
- 有 UI 测试或至少单测覆盖"进入/退出后状态恢复"。

## 通用约束（不变）

- 只用系统控件；任何自绘控件必须先报批。
- 每批 push 前必须 macOS `xcodebuild test` + iOS Simulator `xcodebuild build` 双编通过。
- 现有 74+ 测试不能掉；新增行为必须有测试。
- bundle id 已统一为 `net.timhuang.floretta`（Universal Purchase）。

## 验收

1. 冷启动 → 首页（空状态）→ 从文件打开 `.mm` → 进入画布。
2. 关闭文档 → 回首页 → 最近打开列表里有它。
3. 缩放捏合后停在 100%/200% 这类整数档，界面无 137%。
4. Zen 模式三端可用，Esc 与双击可退出。
5. 双编通过，测试全绿。
