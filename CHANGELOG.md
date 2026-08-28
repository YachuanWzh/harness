# Changelog

本文件记录 Superharness 的用户可见变化，版本号与 Claude Code、flavor-code 两侧插件清单保持一致。

## [2.3.0] - 2026-08-28

### 新增
- 新 Skill `onboarding`（`/superharness:onboarding`、`/onboarding`）：深度分析工作区业务逻辑，产出 `ONBOARDING.md` + `docs/onboarding/*.md` 与浏览器交互式模块导图，帮助新人快速上手
- 分析维度分层：总览层（模块职责 + 依赖图）→ 下钻层（端到端业务流调用链、数据模型与状态流转），浏览器点击或终端对话按需下钻
- astgraph 插件协同：检测到 `ast_*` 工具与代码图索引时优先用其做模块关联挖掘；未安装、非 TS/JS 项目或索引未建时**必须降级**为 Grep/LSP 静态分析并提示 `/ast init`，绝不阻塞
- 缓存 + 按需下钻：分析索引存 `<state-root>/superharness/onboarding/cache.json`（git hash 键），增量只重析变更模块；文档失效条目自动标 stale
- SessionStart 轻提醒：工作区既无 `ONBOARDING.md` 又无缓存时注入一行 `/onboarding` 提示，不自动分析
- 思维导图 viewer 新增 `module` / `flow` / `entity` 节点配色
- 新增确定性辅助库 `skills/onboarding/scripts/onboarding-lib.cjs`（引擎判定/增量规划/stale 自查，含 CLI）与 `tests/onboarding-lib.test.mjs`

## [2.2.0] - 2026-08-24

### 新增
- flavor-code 1.2.20+ 原生支持组合 Skill：`go` 可以通过宿主 `Skill` 工具加载 `writing-plans`、`test-driven-development`、`systematic-debugging` 等完整子 Skill
- flavor-code 侧支持 Claude 风格 `$ARGUMENTS` 参数展开，`/go <目标>` 与 `/light <目标>` 不再在 Skill 正文中保留未展开宏
- Flavor 插件清单与 Claude Code 插件版本统一为 2.2.0

### 修复
- SessionEnd 改为仅记录 checkpoint，保留 `.current-task`，使跨会话冷启动续跑成立
- SubagentStop 按 flavor-code 的 `status`/`error` 载荷记录真实失败、取消和错误详情
- Flavor trace 改为操作系统追加写，不再读取并整体覆盖历史流水；原子状态写入使用唯一临时文件并清理残留
- 修正 Hook 数量、Flavor 兼容要求和 Skill 组合语义的 README/安装器说明
- 修正 PowerShell 测试中“禁止派发子代理”规则的自相矛盾文本断言
- 脑图服务器默认交由操作系统分配空闲端口，消除随机高端口碰撞导致的间歇性启动超时

### 测试
- 新增 SessionEnd 续跑指针保留、SubagentStop 失败载荷和 Flavor Hook 常量更新测试

## [2.1.0] - 2026-08-10

- 引入 `light` 轻量工作流、Ralph 可续跑状态、双宿主安装和跨平台脚本。
