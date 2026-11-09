# 交接

给一起做这仓库的人。提交节奏见 `docs/WORKFLOW.md`。界面规矩见 `docs/DESIGN-RULES.md`。附件见 `docs/ATTACHMENTS.md`。性能预算见 `docs/PERF-BUDGET.md`。

## 29. 版本与安装

### 验收只走 TestFlight

- 验收只用 TestFlight 里的那一版。
- 不用 Xcode 直接安装到 `/Applications` 当作验收。
- 不在本机叠放 1.0 (3)、1.0 (4)、1.0 (5) 多份副本。

### 本机只留一套能跑的构建

- 本机同时只留一套可运行的构建。
- 旧的 archive 和 DerivedData 放进废纸篓。用废纸篓，不用 `rm`。

### TestFlight 每一轮只留最新构建

- 每一轮测试，测试组里只留最新的那一个构建。
- 旧构建从测试员分组里拿掉。不删除 App Store Connect 上的构建记录。
- `CURRENT_PROJECT_VERSION` 递增。`MARKETING_VERSION` 保持不动。

## 性能

新功能提案先按 `docs/PERF-BUDGET.md` 设计。不许「以后再优化」。

PR 描述里必须有三行「性能影响」，内存、帧率、包体各一行。缺一行，Censor 阻断。没有运行时影响就写「无变化」。
