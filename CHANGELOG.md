# Changelog

本文件记录 Superharness 的用户可见变化，版本号与 Claude Code、flavor-code 两侧插件清单保持一致。

## [1.0.4] - 2026-08-28

### 新增
- 新 Skill `receiving-code-review`（移植自 superpowers，适配）：收到评审反馈后**先验证再实施**——禁止表演式同意、多条目先澄清再按 Critical→简单→复杂顺序逐项 TDD、对站不住脚的评审意见凭证据反驳、保留 YAGNI 检查
- 新 Skill `converge`（go Phase 4.5，概念参考 spec-kit `/converge` 与 OpenSpec 规格沉淀）：审查通过后、收尾之前，对照 spec/计划把每条需求判定为 done/partial/missing/divergent（done 必须引用文件+测试证据）；未收敛项**追加为新任务**回 Phase 2 重做，共享 Ralph 重试封顶（5 次）防死循环
- **Living spec 沉淀**：收敛达成后，将"系统当前行为"以 Requirement + WHEN/THEN Scenario 格式写入 `<state-root>/superharness/specs/`（brainstorm 产物存在则就地更新不另写一份），让意图跨会话累积，成为下次冷启动/续跑的可对账真相
- `go` 工作流由七阶段扩展为八阶段（审查与收尾之间加入收敛）；trace 新增 `converge:pass` / `converge:gap` 事件
- **模板优化（stacks）**：5 份栈文档（React/Vue/Python/Node/Java）各新增三节——`Verify commands against the project`（先读 package.json/pyproject/构建文件确认命令，杜绝写死命令假阳性）、`Test boundaries & mocking`（栈专属 mock 边界：React 不 mock 被测树、msw/respx/Testcontainers 等）、`Key libraries`（常用库 + 版本锚定提示）
- `fullstack-seam` 强化：contract-first 演进（OpenAPI/codegen + CI 校验）、seam 变更的 TDD 顺序（契约测试先行）、API 版本化与幂等要求、e2e 明确推荐 Playwright
- 新增内容断言测试 `tests/skills-content.test.mjs`（11 项，node:test）

### 变更
- `writing-plans` 的 Self-Review 升级为强制产出的 **Analysis Findings** 块（需求覆盖矩阵 + 矛盾 + 模糊点 + READY 判定），随计划文件保存；`go` Phase 1 设门禁：存在未解决矛盾或覆盖缺口不得进入实现阶段

## [1.0.3] - 2026-08-28

### 新增
- 新 Skill `onboarding`（`/superharness:onboarding`、`/onboarding`）：深度分析工作区业务逻辑，产出 `ONBOARDING.md` + `docs/onboarding/*.md` 与浏览器交互式模块导图，帮助新人快速上手
- 分析维度分层：总览层（模块职责 + 依赖图）→ 下钻层（端到端业务流调用链、数据模型与状态流转），浏览器点击或终端对话按需下钻
- astgraph 插件协同：检测到 `ast_*` 工具与代码图索引时优先用其做模块关联挖掘；未安装、非 TS/JS 项目或索引未建时**必须降级**为 Grep/LSP 静态分析并提示 `/ast init`，绝不阻塞
- 缓存 + 按需下钻：分析索引存 `<state-root>/superharness/onboarding/cache.json`（git hash 键），增量只重析变更模块；文档失效条目自动标 stale
- SessionStart 轻提醒：工作区既无 `ONBOARDING.md` 又无缓存时注入一行 `/onboarding` 提示，不自动分析
- 思维导图 viewer 新增 `module` / `flow` / `entity` 节点配色
- 新增确定性辅助库 `skills/onboarding/scripts/onboarding-lib.cjs`（引擎判定/增量规划/stale 自查，含 CLI）与 `tests/onboarding-lib.test.mjs`

## [1.0.2] - 2026-08-24

### 新增
- flavor-code 1.2.20+ 原生支持组合 Skill：`go` 可以通过宿主 `Skill` 工具加载 `writing-plans`、`test-driven-development`、`systematic-debugging` 等完整子 Skill
- flavor-code 侧支持 Claude 风格 `$ARGUMENTS` 参数展开，`/go <目标>` 与 `/light <目标>` 不再在 Skill 正文中保留未展开宏
- Flavor 插件清单与 Claude Code 插件版本统一为 1.0.2

### 修复
- SessionEnd 改为仅记录 checkpoint，保留 `.current-task`，使跨会话冷启动续跑成立
- SubagentStop 按 flavor-code 的 `status`/`error` 载荷记录真实失败、取消和错误详情
- Flavor trace 改为操作系统追加写，不再读取并整体覆盖历史流水；原子状态写入使用唯一临时文件并清理残留
- 修正 Hook 数量、Flavor 兼容要求和 Skill 组合语义的 README/安装器说明
- 修正 PowerShell 测试中“禁止派发子代理”规则的自相矛盾文本断言
- 脑图服务器默认交由操作系统分配空闲端口，消除随机高端口碰撞导致的间歇性启动超时

### 测试
- 新增 SessionEnd 续跑指针保留、SubagentStop 失败载荷和 Flavor Hook 常量更新测试

## [1.0.1] - 2026-08-10

- 引入 `light` 轻量工作流、Ralph 可续跑状态、双宿主安装和跨平台脚本。
