# 首页项目管理器（G3–G7）

- 日期：2026-11-15
- 对象：Floretta 首页 / 项目管理器。
- 变更：以系统大标题「项目」替换「最近」抬头；将 prominent「新建导图」与直接文件选择入口放入 iOS/macOS 首页工具栏；本地化目录与运行时表同步；更新 HomeSmoke 和原生控件契约测试。既有 TabView、macOS 侧栏/设置菜单、最近导图网格、空态和文件筛选继续使用。
- 数据保护：没有改动 RecentMapsStore 的 UI-test 产物过滤；`testRecentMapsKeepUserDocumentNamedUntitled`、`testRecentMapsKeepCurrentUITestRootVisible`、`testRecentMapsExcludeOtherUITestRoots` 保留。
- 验证：macOS generic build exit 0；iOS generic build exit 0；iOS `build-for-testing` exit 0；macOS `FlorettaTests` 共 472 tests、1 skipped、0 failures，exit 0。UI 测试未执行（SSH 图形会话限制），视觉未验证，待 CUA。
- GitHub：分支 `feat/home-shell`，commit `0d9a08b`；PR #13 已推送，未合并。
- 资源收尾：本任务未启动模拟器；booted simulator 数量为 0；未创建临时 DerivedData 目录。
