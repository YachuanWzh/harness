# 设计：新人上手分析能力（onboarding skill）

日期：2026-08-28
状态：已批准（brainstorm 会话 20260828-084508-32608）

## 目标

给 Claude Code 和 flavor code 两个宿主增加一个能力：深度分析所在工作区的代码与业务逻辑，重点是**模块之间的业务关联**，帮助新人快速理解并上手项目。

## 已确认的决策

| 决策点 | 结论 |
|--------|------|
| 产出物 | Markdown 上手文档（进仓库、团队共享）+ 交互式浏览器导图（实时下钻）结合 |
| 触发方式 | 手动 skill（`/onboarding`）为主；SessionStart hook 仅在"仓库无上手文档且无缓存"时提示一行，绝不自动重分析 |
| 分析维度 | 全部维度分层呈现：总览层=模块职责+依赖图；下钻层=端到端业务流调用链 + 数据模型/状态流转 |
| 规模与时效 | 缓存 + 按需下钻：首轮只建模块级总览缓存（含 git hash）；用户下钻某模块/业务流时才深挖；再运行只重析变更模块 |
| 产物存放 | 分析索引/缓存 → `<state-root>/superharness/onboarding/`（不提交）；成品文档 → 仓库 `ONBOARDING.md` + `docs/onboarding/*.md`（提交） |
| 实现路线 | 混合（C）：agent 负责业务语义深挖；机械检索**完全委托已有的 astgraph 插件**，不自研 AST 脚本 |

## astgraph 协同与回退（强制要求）

- **可用性双检测**：① 当前会话存在 `ast_search/ast_callers/ast_callees/ast_impact/ast_context` 工具；② `.flavor/astgraph/index.db` 存在。
- 工具在但索引缺失 → 提示用户先运行 `/ast init`（构建全量代码图）。
- **未安装 astgraph 插件（含 Claude Code 宿主）、或非 TS/JS/TSX 项目、或 ast_* 工具不可用时，必须回退**：改用 Glob/Grep/Read + LSP（LspFindRefs/LspHover）做静态分析，流程与产出物不变，仅深度与速度下降；并在生成的文档头部标注"分析引擎：fallback"。
- 回退路径是主设计的一部分，不允许出现"无 astgraph 即功能不可用"的实现。

## 架构

### 1. 新 skill：`onboarding`

位置：`template/plugins/superharness/skills/onboarding/SKILL.md`（双宿主经现有安装机制分发）。

**Phase A — 总览索引（每次运行，浅分析）**
1. 探测宿主与状态根（`.claude/superharness/` 或 `.flavor/superharness/`），确定分析引擎（astgraph / fallback）。
2. 读缓存 `<state-root>/superharness/onboarding/cache.json`（模块清单、git hash、各模块分析时间戳与文档路径）。
3. `git rev-parse HEAD` + 工作区脏文件 → 与缓存 diff，得出变更模块集；无缓存则全模块待分析。
4. 模块发现：目录结构 + 包清单 + 入口文件 + import/调用边（astgraph：`ast_search` + 文件聚合；fallback：Grep import 语句）。按目录/包聚成模块，构建模块级依赖边。
5. 对"待深挖"模块（新缓存未命中或用户指定），agent 阅读关键文件，产出：一句话职责、核心实体、对外接口、与其他模块的业务关联（谁在什么场景调用谁、传递什么数据）。
6. 写缓存，渲染总览导图（kind: `module` 节点 + 依赖边 `note`），生成/更新 `ONBOARDING.md`：项目一句话简介、模块地图（Mermaid 图）、推荐上手路径（先读哪个模块→哪个）、术语表。

**Phase B — 按需下钻（交互式）**
- 触发两种：① flavor-code + 浏览器模式下用户在导图点击节点（events 文件回传，协议同 brainstorm）；② 终端对话指定（"深入分析 install 模块"/"一次 go 任务的完整链路"）。Claude Code 无浏览器通道时仅 ②。
- agent 以选中对象为锚，用 `ast_callers/ast_callees/ast_impact/ast_context`（或 fallback 的 LspFindRefs/Grep）追端到端调用链：入口 → 各层 → 数据落地，识别跨模块交互、事件、共享数据结构与状态流转。
- 产物：`docs/onboarding/<topic>.md`（含 `file:line` 引用的调用链、数据流说明、"改动影响面"清单），推送到导图对应分支下钻一层，更新缓存。

**Phase C — 收尾**
- 全量/增量分析完成后运行一次自查：文档中的文件路径与关键符号仍存在（Grep 验证），失效条目标 `stale` 并在导图标灰。
- 提示用户提交生成的文档；文档由用户决定是否入库。

### 2. 导图服务端

复用 brainstorm 的 `start-server.ps1` / `stop-server.ps1` / `mindmap.json` 快照 + `events`/`edits` JSONL 协议，扩展：
- 新节点 `kind`：`module`、`flow`、`entity`；`state` 增加 `stale`（灰显）。
- 下钻循环：push 快照 → 阻塞等待 click（Monitor/wakeup ≤60s，同 brainstorm edit round）→ 分析 → rev+1 重推。
- viewer 前端增加按 kind 的图标/配色区分（改动限制在 brainstorm 的静态资源派生副本或共享 viewer，实现阶段定）。

### 3. SessionStart 提醒

扩展现有 superharness SessionStart hook：仓库根无 `ONBOARDING.md` 且状态目录无 onboarding 缓存时，注入一行"检测到本仓库尚无新人上手文档，可运行 /onboarding 生成"。存在任一者则静默。不做自动分析。

## 缓存结构（cache.json）

```json
{
  "engine": "astgraph | fallback",
  "gitHash": "…",
  "modules": {
    "lib": { "doc": "docs/onboarding/lib.md", "summary": "…", "analyzedAt": "…", "stale": false, "deps": ["…"] }
  },
  "flows": {
    "install-flow": { "doc": "docs/onboarding/install-flow.md", "anchors": ["lib/install.ps1#Install"] }
  }
}
```

## 测试策略（TDD，遵循 HARNESS.md）

- skill 的确定性部分（模块发现聚合、缓存 diff、stale 自查、引擎探测）以 Node/PowerShell 单测覆盖于 `tests/`（沿用现有 tests 布局与安装脚本测试模式）。
- agent 指令部分（SKILL.md 文案）以 dogfood 方式在超小 fixture 仓库上人工走查：astgraph 可用 / 插件缺失 / 索引缺失 / 非 git 仓库 四条路径。
- 回退路径为必测项。

## 已知风险

1. **大仓库首轮成本**：模块多时 Phase A 仍可能偏慢 → 首轮限制只深挖 Top-N 高连接度模块，其余标注"待下钻"。
2. **文档过期**：靠 git hash + stale 自查缓解，但不能保证语义级新鲜度。
3. **Claude Code 侧无点击回传**：下钻体验降级为终端驱动，属预期行为。
4. **viewer 扩展可能与 brainstorm 分支渲染耦合**：实现时若发现共享成本高于收益，则 onboarding 复制一份 viewer 静态资源（允许局部重复）。

## 非目标

- 不自研 AST 解析/索引引擎（委托 astgraph）。
- 不做 IDE 内实时联动、不做 CI 集成。
- 不自动提交生成的文档（由用户决定）。
