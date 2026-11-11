# E1 文档、E4 体积门禁、F3 平台协议核实

日期：2026-11-11

## 变更

- 新增 `docs/FORMAT-FOR-AI.md`：记录 ZIP 容器、Codable 字段与默认值、ID/路径规则、示例和未知键保真边界。
- `docs/PERF-BUDGET.md` 标记包体与 Node/Python 依赖门禁已由 CI 强制。CI 原有 `Packaged app size` job 调用 `scripts/check-packaged-app-size.sh`，其中阈值超限退出失败并扫描运行时/依赖。
- 在 ADR-021 增加五项 Port 的源码核实结果与未贯通缺口。

## 验证

- `swift test`：344 项通过，0 失败。
- `bash -n scripts/check-packaged-app-size.sh scripts/check-floretta-core-imports.sh`：语法通过；`git diff --check`：通过。
- 查验 `.github/workflows/floretta-core.yml` 的 `Packaged app size` job 会执行门禁自测及实际门禁；脚本分别对 iOS 15 MiB、macOS 25 MiB 以上（含等于）返回失败，并扫描打包目录及 `Package.swift` 依赖声明。
- 未运行模拟器或后台服务；没有创建临时 DerivedData。
