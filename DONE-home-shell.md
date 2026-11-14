STATUS: DONE

# Home shell · 项目管理器（G3–G7）

## 改动与对应文件

1. **首页项目管理器抬头与操作**
   - `Floretta/Shared/Shell/AppSettings.swift:105-106`：标题改为「项目」。
   - `Floretta/Shared/Shell/LibraryHome.swift:5-35,37-78,80-109`：系统大标题；iOS/macOS 工具栏显示 prominent「新建导图」及「从文件应用打开」；最近导图继续使用 `LazyVGrid`、文件名、修改时间和 Quick Look 缩略图；空态保留原生引导。
   - `Floretta/Shared/Shell/FlorettaL10n.swift:44-56`、`Floretta/Shared/Localizable.xcstrings:939-956`：加入项目标题的运行时与中英文目录文案。
   - `FlorettaTests/ShellTests.swift:883-900,940-979,1028-1053`、`Tests/FlorettaCoreTests/HomeChromeContractTests.swift:7-35`、`FlorettaUITests/HomeSmokeTests.swift:11-60,184-213,229-232`：同步标题、工具栏和契约测试。
2. **iOS Tab / macOS 导航**：本次未改；既有 `Floretta/Shared/ContentView.swift:120-163` 使用系统 `TabView`（首页/设置）与 macOS `NavigationSplitView`；编辑器 root 在 `:94-117` 接管内容，因此编辑时不显示 Tab。
3. **设置入口**：本次未改；iOS 设置 Tab 位于 `ContentView.swift:130-135`；macOS 侧栏设置入口在 `:138-163`，原生设置菜单在 `Floretta/Shared/FlorettaApp.swift:193-198`。
4. **从文件应用打开**
   - `Floretta/Shared/Shell/LibraryHome.swift:51-55,90-93`：新增直接文件入口 `home.openFiles`。
   - `Floretta/Shared/ContentView.swift:78-90`：复用系统 `.fileImporter`，选中后调用 `library.openFile`。
   - `Floretta/Shared/Shell/AppSettings.swift:185-229`：保留项目现有支持格式与 UTType 筛选（包括 `.floretta`、`.mm`、`.opml`、`.md`、`.xmind` 及文本类型）。
   - `FlorettaUITests/HomeSmokeTests.swift:552-558`：导入冒烟路径改为点击新直接入口。
5. **打开文件后进入编辑页 / 冷启动首页**：`ContentView.swift:94-117,220-250` 仅在 library 有活动文档时呈现编辑器，否则显示首页；本次没有加入最近文档自动恢复。冷启动视觉行为待 CUA 实机/模拟器复核。
6. **原生控件**：本次使用原生 `Button`、`Label`、导航栏工具项、现有 `LazyVGrid`、`ContentUnavailableView`、`.fileImporter`；没有新增依赖、手绘卡片边框或自定义导航/Tab 控件。

## 标识与保护逻辑

- 保留：`home.newMap`、`home.recent.row`、`home.toolbarMenu`、`home.open`、`home.templates`。
- 新增：`home.openFiles`。
- Recents 排除 UI 测试产物逻辑未改；三条相关测试仍在 `FlorettaTests/ShellTests.swift:339-399`（用户文件名 `未命名` 可见、当前 UI-test root 可见、其他 UI-test root 排除）。
- 未修改 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`，未新增依赖。

## 验证

- `Floretta-macOS` generic build：**BUILD SUCCEEDED**，exit code `0`。
- `Floretta-iOS` generic build：**BUILD SUCCEEDED**，exit code `0`。
- `Floretta-iOS build-for-testing`：exit code `0`，HomeSmokeTests 等完成编译；未运行模拟器 UI 测试。
- `Floretta-macOS` / `-only-testing:FlorettaTests`：`Executed 472 tests, with 1 test skipped and 0 failures`；**TEST SUCCEEDED**，exit code `0`。
- **视觉未验证，待 CUA**。当前为 SSH 会话；未启动模拟器，结束时 booted simulator 数量为 `0`。

## CUA 复现路径与预期

1. iPhone/iPad 冷启动 Floretta：显示「项目」系统大标题、最近导图网格与缩略图/修改时间；无最近文件时显示明确空态。
2. 检查导航栏右侧「新建导图」主操作与「从文件应用打开」；点文件入口，系统文件选择器只允许现有支持格式；选择 `.floretta`、`.xmind`、`.mm`、`.opml` 或 `.md` 后进入对应导图编辑页，编辑时底部 Tab 不显示。
3. 关闭编辑器回到首页；点「设置」Tab，检查语言设置；回到「首页」Tab。
4. macOS 检查侧边栏首页/设置、工具栏新建/文件打开，以及菜单栏「设置…」入口。

## 交付

- 分支：`feat/home-shell`，基于任务开始时已核实的最新 `origin/main`（`e5202c121af4269715955d6997a46fc5f8f0ebe6`）。
- Commit：`0d9a08b`（首页项目管理器动作与测试）。
- PR：[#13](https://github.com/Super-Console/Floretta/pull/13)，已推送，**未合并**。
- PR 必需的性能三项未做数值实测：本次不触及画布渲染或资源数据，包体也未实测；见 PR 描述。
