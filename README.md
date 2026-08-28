# Superharness

给 Claude Code 与 flavor-code 的项目级工程纪律"线束"（harness）。一条命令初始化项目，之后在 Claude Code 中用
`/superharness:go <任务目标>` 即可让 AI 在严格约束（TDD、系统化调试、完成前验证、代码审查）下
自主完成开发任务；小改动可用轻量档 `/superharness:light <任务目标>`（保留核心纪律、砍掉重装备）；
用 `/superharness:brainstorm <主题>` 在浏览器实时脑图里梳理需求与设计。在 flavor-code 中技能无
命名空间前缀，直接 `/go <任务目标>`、`/light`、`/brainstorm` 调用。

加载方式：初始化时把插件安装为 **本地 marketplace**（`.claude/superharness`），并在
`.claude/settings.json` 中通过 `extraKnownMarketplaces` + `enabledPlugins` 自动启用——
信任项目目录后即获得 `/superharness:*` 命名空间技能与 SessionStart 钩子。
flavor-code 项目（`FLAVOR.md` / `.flavor` 标记）则安装为 `.flavor/plugins/superharness/`
原生插件，注册 8 个会话、计划和子代理生命周期钩子。flavor-code 1.2.20+ 还提供组合 `Skill`
工具与 Claude 风格参数展开，使 `go` 的必需子技能链和 SessionStart 规则注入真正按宿主协议执行。

支持 **Windows**（PowerShell）与 **macOS / Linux**（bash）双平台，两套实现功能等价。

核心技能内容移植自 [obra/superpowers](https://github.com/obra/superpowers)（MIT License），
并为自主工作流做了适配。

> 📐 想快速看懂整体设计（含架构图、安装/会话/脑图流程图）？见
> [技术方案文档.md](技术方案文档.md)。

## 安装

### 全局安装（推荐，一次性）

**Windows**：把 superharness 安装到 `%LOCALAPPDATA%\superharness\`，之后在任何目录都能直接使用——删掉 clone 仓库也不影响：

```cmd
powershell -NoProfile -ExecutionPolicy Bypass -File install-global.ps1
```

**macOS / Linux**：安装到 `~/.local/superharness/`，并按当前 shell（zsh/bash）自动把 `bin/` 写入对应 rc 文件的 PATH：

```bash
bash install-global.sh
```

打开**新终端**后，在任意项目目录执行 `superharness` 即可初始化。

> 更新：拉取新版 clone 后重新运行上述命令覆盖即可（旧路径会自动清理）。
> 卸载（Windows）：删除 `%LOCALAPPDATA%\superharness\`，并从用户环境变量 PATH 中移除对应的 `bin\` 路径。
> 卸载（macOS / Linux）：删除 `~/.local/superharness/`，并从 shell rc 文件中移除对应的 `bin/` PATH 行。

#### 在其他 CLI 中更新（推荐）

当 superharness 模板有更新（新 hook、新技能、`flavor-plugin.json` 清单变更等），在**任何项目目录**下运行：

```cmd
superharness self-update
```

这会重新执行全局安装脚本，把最新模板刷新到 `%LOCALAPPDATA%\superharness\`（Windows）或 `~/.local/superharness/`（macOS/Linux），全程无需手动重新运行 `install-global.ps1`。

子命令列表：

| 命令 | 作用 |
|------|------|
| `superharness` | 初始化当前项目（同项目级 `install`） |
| `superharness self-update` | 全局刷新，读取最新的 `template/` 并覆盖安装 |
| `superharness self-update --target-dir <path>` | 指定要刷新的项目目录 |
| `superharness --uninstall` | 卸载当前项目的插件和钩子注册 |

> flavor-code 项目中，`superharness self-update` 会把 `.flavor/plugins/superharness/` 也一并刷新（manifest 增加新 hook 时会自动生效）。

### 本地 PATH（轻量替代）

如果不想复制文件、希望始终用 clone 里的最新版，也可以直接把 clone 仓库的 `bin\` 加入 PATH：

```cmd
setup.cmd
```

macOS / Linux 等价做法：把 clone 仓库的 `bin/` 加入 PATH（如 `export PATH="$PWD/bin:$PATH"` 写入 rc 文件）。

> 缺点是 clone 仓库删掉后 `superharness` 命令会失效。切回全局安装只需再跑一次 `install-global.ps1`（或 `install-global.sh`），旧路径会自动清理。

## 使用方法

### 1. 初始化项目

安装完成后，在任意项目根目录下（Windows 用 cmd/PowerShell，macOS/Linux 用终端）：

```
superharness
```

安装器自动检测项目类型（也可同时存在、同时安装）：

- **Claude Code 项目**（存在 `CLAUDE.md` 或 `.claude/`）→ 安装为本地 marketplace 插件
- **flavor-code 项目**（存在 `FLAVOR.md` 或 `.flavor/`）→ 安装为 `.flavor/plugins/superharness/` 原生插件

Claude Code 侧会创建：

| 产物 | 作用 |
|------|------|
| `.claude\superharness\` | 本地 marketplace 目录（`.claude-plugin\marketplace.json` + `plugins\superharness\` 插件本体，含全部技能） |
| `.claude\settings.json` 中的 `extraKnownMarketplaces` + `enabledPlugins` | 自动注册并启用该 marketplace 的插件（保留性合并，不破坏已有配置） |
| `CLAUDE.md` 中的 SUPERHARNESS 标记段 | Claude Code 自动读取的兜底指引（已有内容会被保留，重复执行不会重复追加） |

flavor-code 侧会创建：

| 产物 | 作用 |
|------|------|
| `.flavor/plugins/superharness/` | 插件本体：`flavor-plugin.json`（清单，声明 8 个生命周期钩子）+ `index.js`（注册 skillRoot 与钩子）+ `skills/` + `scripts/ralph-lib.*` + `HARNESS.md` |
| `FLAVOR.md` 中的 SUPERHARNESS 标记段 | flavor-code 自动读取的兜底指引（同样保留性合并、幂等） |
| 目标项目 `.gitignore` | 追加运行时态目录（flavor-code 侧为 `.flavor/superharness/ralph/`，Claude Code 侧为 `.claude/superharness/ralph/` 等） |

#### 技术栈模板（可选）

初始化时可附带 `--template` 为项目注入对应技术栈的工程纪律指引（经 SessionStart 钩子每会话注入）：

```cmd
superharness --template=frontend                :: 默认 React
superharness --template=frontend --stack=vue
superharness --template=backend                 :: 默认 Python
superharness --template=backend --stack=java
superharness --template=backend --stack=node
superharness --template=fullstack               :: 默认 React + Python
superharness --template=fullstack --frontend=vue                :: Vue + Python
superharness --template=fullstack --backend=node                :: React + Node
superharness --template=fullstack --frontend=vue --backend=node :: 自由组合
```

合法 `--stack`：前端 `react|vue`，后端 `python|java|node`；`fullstack` 用
`--frontend=react|vue` + `--backend=python|java|node` 自由组合（默认 React + Python），
不接受 `--stack`。指引文档随插件下发于 `plugins\superharness\stacks\*.md`：单栈复制
选中的一份；全栈拼接前后端两份指引 + 框架无关的接缝规则 `fullstack-seam.md`
（API 契约、CORS、dev proxy、e2e），结果写入 `.claude\superharness\STACK.md`；
不带 `--template` 的普通初始化不写该文件（已有的会被移除）。

### 1.1 卸载项目安装

在项目根目录运行：

```cmd
superharness --uninstall
```

只移除安装器自己添加的内容，其余项目配置原样保留：

- 删除 `.claude\superharness\`（Claude Code）与 `.flavor\plugins\superharness\`（flavor-code）插件目录
- 从 `.claude\settings.json` 移除 `extraKnownMarketplaces.superharness` 与
  `enabledPlugins["superharness@superharness"]`（其他键不动）
- 移除 `CLAUDE.md` / `FLAVOR.md` 中的 SUPERHARNESS 标记段（原有内容保留）
- 清理 `.gitignore` 中安装器追加的运行时目录条目

未安装过时安全无操作（退出 0）。全局安装（`%LOCALAPPDATA%\superharness\` 或
`~/.local/superharness/`）不在此命令范围内，仍按上文手动步骤卸载。

### 2. 启动 Claude Code / flavor-code

在该项目目录运行 `claude`（或 flavor-code 的 `flavor`；首次需在信任弹窗中信任工作区）。此后：

- Claude Code：插件经 `.claude/superharness` 本地 marketplace 自动加载 —— 无需任何安装命令；
- flavor-code：插件经 `.flavor/plugins/superharness/` 自动加载，启动时注册 skillRoot 与 8 个生命周期钩子；
- 两侧的 **SessionStart 钩子**都会自动把 `HARNESS.md`（约束规则）注入每个会话上下文；
- 各技能以 `/superharness:*` 命名空间注册（flavor-code 侧无前缀，直接 `/go` 等）。`go` 等会按 description 自动触发；
  `brainstorm` 设了 `disable-model-invocation`，仅在你手动运行时启动。

> flavor-code 完整兼容要求 **1.2.20+**。旧版仍能发现并显式运行单个 Skill，但不会展开
> `$ARGUMENTS`，也无法在 `/go` 运行中继续加载必需子 Skill，SessionStart 返回的完整规则上下文也不会生效。

### 3. 执行任务

```
/superharness:go 给登录接口增加验证码校验
```

`go` 技能驱动八阶段自主工作流：

1. **理解** —— 探索代码、确认目标，必要时一轮澄清
2. **隔离** —— `using-git-worktrees`：git 项目默认建 worktree/分支隔离，非 git 则原地，绝不阻塞
3. **计划** —— `writing-plans`：拆成 2-5 分钟的 TDD 小任务，存到 `.claude/superharness/plans/`；计划末尾强制产出 **Analysis Findings** 块（spec 覆盖矩阵 + 矛盾 + 模糊点），未 READY 不得进入实现
4. **实现** —— 多任务计划委托 `subagent-driven-development`（每任务派新子代理，主上下文只留计划与协调），琐碎/紧耦合任务主代理内联 `test-driven-development`；均严格红-绿-重构-提交，出问题转 `systematic-debugging`
5. **验证** —— `verification-before-completion`：跑完整测试套件，贴出真实输出
6. **审查** —— `requesting-code-review`：派子代理审查 diff，严重问题阻塞收尾；处置评审意见走 `receiving-code-review`（先验证再实施、有理则据证据反驳）
7. **收敛** —— `converge`：对照 spec/计划逐条审计实现（done/partial/missing/divergent），未收敛的追加为新任务回到实现（共享 Ralph 重试封顶）；收敛后把"系统当前行为"沉淀为 living spec（`.claude/superharness/specs/`，与 brainstorm 产物同目录、就地更新）
8. **收尾** —— `finishing-a-development-branch`：合并 worktree 分支、移除 worktree、删除分支（非 git/原地则跳过；不自动 push）

### 3.1 轻量任务（light）

觉得 `go` 对当前任务太重？用轻量档：

```
/superharness:light 修一下登录页的按钮样式
```

`light` 保留核心纪律（TDD + 明确豁免、真实输出验证、根因调试），砍掉重装备：

| go 的装备 | light 的处理 |
|-----------|--------------|
| worktree/分支隔离 | 默认原地工作，仅大改动才建一次性分支 |
| 计划文件 `.claude/superharness/plans/` | 不写，任务清单用 TodoWrite 管理 |
| 子代理实现 + 子代理审查 | 全部内联完成，收尾用自查清单 |
| Ralph 跟踪（`.current-task` / `task.json` / `trace.jsonl`） | 不启动，零记账负担，中断重跑即可 |

适用：小 bug 修复、小功能、配置/文案调整、原型验证。任务变大时它自己会建议切换回
`/superharness:go`。注意：`light` 不接管、不结束已有的 go 任务（若 `.current-task` 存在会先提醒你）。

### 4. 任务过程跟踪与自动重试

`go` 的任务跟踪**直接构建在下文的 Ralph 状态机制之上**（Claude Code 为 `.claude/superharness/ralph/`，
flavor-code 为 `.flavor/superharness/ralph/`，下文统称 ralph 状态目录），不再使用旧的
`superharness/trace/<slug>.json` + `outcome.json` 机制，也不再需要手动的 `resume` 技能。

跟踪采用**混合式**，既可靠又有细粒度：

- **UserPromptSubmit 钩子自动起跑**：用户一提交 `/superharness:go <目标>`（flavor-code 侧为 `/go <目标>`）,钩子就识别出这是
  go 调用,自动 `Start-RalphTask` —— 写 `.current-task`(slug 由目标派生)、播下空的 `task.json`、
  并向 `trace.jsonl` 追加 `task:started`。**四个运行时文件在任务一开始就自动出现,无需主代理手动 bootstrap。**
  换一个新目标会自动重指到新任务;重复提交同一任务则空操作。
- **go 工作流（主代理）充实并写执行事件**:Phase 1 用 `Initialize-RalphTasks` 把空清单替换成真实
  计划任务列表;在各阶段边界用 `Add-RalphTrace` 向 `trace.jsonl` 追加 `red/green/commit/verify:*`
  等事件,并用 `Set-RalphTaskStatus` 翻子任务状态。
- **Stop 钩子兜底**：每当 Claude 交还控制权，只要 `.current-task` 存在，钩子就向 `trace.jsonl`
  追加一条 `round` 心跳（query 来自 UserPromptSubmit 暂存的 `.pending-prompt.json`），保证
  "每一轮都被记录"——即便该轮主代理没写任何执行事件。

**失败即在同一次 go 内自动重试**（不再等人确认）：跑完全量测试后，全绿则记 `verify:success`、
把子任务标 `done`、`Reset-RalphRetry`；有失败则记 `verify:failure` 并 `Add-RalphRetry`。只要
`Test-RalphRetryExhausted` 未触顶（`.ralph-state.json` 计数**上限 5**），就自动回到 Phase 2 走
**复现 → 定位根因（systematic-debugging）→ 改码（TDD）→ 验证**闭环，把出问题的代码真正修好而非
盲目重跑；触顶则停下来汇报。中断后由新 agent 冷启动续跑，靠 `Get-RalphResumeContext` 读回上下文。

> 约束：每个项目同一时间只跟踪 **一个活跃 go 任务**（`.current-task` 是单一活跃标记）。
> 不要在同一项目里并发跑多个 `go` 任务，否则轮次会被记到错误的 trace。`.claude/superharness/ralph/`
> 整个目录是运行时态，已由安装器加入目标项目的 `.gitignore`。

### 5. Ralph 状态机制（可续跑的自治任务循环）

为支持"原 agent 中断、新 agent 冷启动续跑"，提供一套零依赖的状态库，双平台实现：
Windows 侧 `scripts/ralph-lib.ps1`（dot-source 即用），macOS/Linux 侧 `scripts/ralph-lib.sh`
（source 即用，JSON 处理优先用 node、缺失时 python3 兜底）。状态目录跟随宿主：Claude Code 安装在
`<项目>/.claude/superharness/`，运行时文件落在 `.claude/superharness/ralph/`；flavor-code 安装在
`<项目>/.flavor/plugins/superharness/`，运行时文件落在 `.flavor/superharness/ralph/`（ralph-lib 按自身安装位置自动识别，
也可用环境变量 `SUPERHARNESS_STATE_ROOT` 强制指定）。管理该目录下四个运行时文件：

| 文件 | 作用 | 写入规则 |
|------|------|----------|
| `.current-task` | 一张纸条，记当前在忙哪个任务 | 换任务**只重写这一行** |
| `task.json` | 任务清单快照 `{status,phase,sprint,tasks[],updated_at}`，每个子任务独立带 `status`（`pending`/`in_progress`/`done`） | 原子覆盖；每次写盘刷新 `updated_at` |
| `trace.jsonl` | 流水账，每行一条 `{ts,phase,event,detail}` | **只追加**，从不改写前面的行——崩溃最多坏最后一行，可逐行倒查 |
| `.ralph-state.json` | 重试计数器 `{retries,max,updated_at}` | 原子覆盖，上限 **5** 次封顶 |

库函数一览（PowerShell 命名；bash 版为对应的 snake_case 函数，如 `ralph_add_trace`、`ralph_get_resume_context`）：

- `.current-task`：`Set-RalphCurrentTask` / `Get-RalphCurrentTask`
- `task.json`：`Initialize-RalphTasks` / `Get-RalphTasks` / `Get-RalphNextTask`（取第一个未完成的子任务，跳过 `done`）/ `Set-RalphTaskStatus`（幂等改单个子任务状态）
- `trace.jsonl`：`Add-RalphTrace`（追加一行）/ `Get-RalphTraceTail`（读末尾 N 条）
- `.ralph-state.json`：`Get-RalphRetryState` / `Add-RalphRetry`（自增并封顶）/ `Test-RalphRetryExhausted` / `Reset-RalphRetry`
- 冷启动：`Get-RalphResumeContext`

**冷启动恢复流程**（新 agent 脑子空白时照此续跑）：

1. 读 `.current-task` —— 知道在忙哪个任务（`Get-RalphCurrentTask`）
2. 读 `task.json` —— 看 `tasks[]` 哪些还没打钩（`Get-RalphTasks` / `Get-RalphNextTask`）
3. 翻 `trace.jsonl` 末尾 —— 上次最后干了啥（`Get-RalphTraceTail`）
4. 瞄一眼 `git diff` —— 代码实际改了没
5. **记录 vs 代码对账**：对得上 → 从第一个没打钩的子任务接着干；对不上 → **以代码为准**修正
   `task.json`（`Set-RalphTaskStatus`）
6. 干活，每步都：改 `task.json` + 追加 `trace.jsonl`

前 1～3 步与重试状态由 `Get-RalphResumeContext` 一次性装配成结构化事实；第 4～5 步的"对账/以代码为准"
是 agent 的判断（跑 `git diff` 后用 `Set-RalphTaskStatus` 修正）。`task.json` 是"现在长啥样"的快照，
`trace.jsonl` 是"怎么变成这样的"，二者互补。运行时文件位于 ralph 状态目录（Claude Code 为
`.claude/superharness/ralph/`，flavor-code 为 `.flavor/superharness/ralph/`；已加入 `.gitignore`）。

### 6. 脑图脑暴（手动触发）

```
/superharness:brainstorm 给登录接口设计验证码方案
```

`brainstorm` 技能启动一个零依赖 Node 本地服务器并在浏览器打开**实时脑图**，全程伴随
需求澄清与方案讨论：每提一个问题/确定一个决策，Claude 就把脑图结构推送到页面。脑图支持
**拖拽平移、滚轮缩放、双击复位**；节点按类型着色、按状态高亮（已选/淘汰/已定）；点击节点可
把选择反馈给 Claude。**双击节点**可弹出编辑面板修改 `label`/`note`，保存后界面即时更新（乐观
更新），点顶栏「提交」按钮把修改批量发回 Claude 并入设计。流程结束生成设计文档到
`.claude/superharness/specs/`，并提示你可转 `/superharness:go` 实施。

消息协议（详见
[设计文档](docs/superpowers/specs/2026-06-12-superharness-plugin-and-brainstorm-design.md)）：

- **Claude → 前端**：把全量快照写入 `<session>/content/mindmap.json`（`mindmap:snapshot`，
  含 `rev`/`status`/树形 `root`），服务器监听文件变化后经 WebSocket 推送。
- **前端 → Claude**：节点点击经 `POST /event` 落盘 `<session>/state/events`（JSONL，
  `node:click`），Claude 下一轮读取并结合终端文字理解意图；节点编辑与提交经
  `POST /event` 落盘 `<session>/state/edits`（JSONL，`node:edit` / `submit`），
  与点击管道分离，不随快照推送清空——等 Claude 合并后才清。

脑图不可用时（如无 Node）流程自动降级为纯终端，绝不阻塞脑暴。会话产物落在
`.superharness/`（已加入 `.gitignore`）。

## 内含技能

| 技能 | 来源 | 触发时机 |
|------|------|----------|
| `superharness:go` | 本项目 | 用户给出端到端任务目标（含 Ralph 跟踪与同一次运行内自动重试） |
| `superharness:light` | 本项目 | 小任务/快速改动，go 的轻量档：豁免式 TDD + 真实输出验证，无 worktree/计划文件/子代理/Ralph 记账 |
| `superharness:brainstorm` | 本项目（流程参考 superpowers） | **仅手动** `/superharness:brainstorm`，实时脑图梳理需求设计 |
| `superharness:writing-plans` | superpowers（适配） | 多步任务动代码之前 |
| `superharness:using-git-worktrees` | superpowers（适配） | 动代码前需要隔离工作区（go Phase 0.5） |
| `superharness:finishing-a-development-branch` | 本项目 | worktree/分支任务完成并验证后：合并回主干、清理隔离工作区（go Phase 5） |
| `superharness:subagent-driven-development` | superpowers（适配） | 执行多任务计划、任务相互独立时（go Phase 2） |
| `superharness:test-driven-development` | superpowers | 实现任何功能/修复之前 |
| `superharness:systematic-debugging` | superpowers | 任何 bug、测试失败、异常行为 |
| `superharness:verification-before-completion` | superpowers | 声称"完成/修好/通过"之前 |
| `superharness:requesting-code-review` | superpowers | 任务完成、合并之前 |
| `superharness:receiving-code-review` | superpowers（适配） | 收到评审反馈之后、实施修改之前——先验证再实施，拒绝表演式同意 |
| `superharness:converge` | 本项目（概念参考 spec-kit converge / OpenSpec 规格沉淀） | go 审查通过后、收尾之前：实现 vs spec 逐条对账 + living spec 沉淀（go Phase 4.5） |

## 仓库结构

```
superharness\
├── bin\superharness.cmd     # Windows CLI 入口（PATH 上可直接调用）
├── bin\superharness         # macOS/Linux CLI 入口（bash）
├── lib\install.ps1          # Windows 安装器逻辑（可测试）
├── lib\install.sh           # macOS/Linux 安装器（功能等价，bash）
├── template\                # 被复制进项目的 .claude/superharness（本地 marketplace）
│   ├── .claude-plugin\marketplace.json   # marketplace 目录文件
│   └── plugins\superharness\             # 插件本体
│       ├── .claude-plugin\plugin.json    # 插件清单（提供 superharness: 命名空间）
│       ├── HARNESS.md                    # 会话启动时注入的约束规则
│       ├── hooks\hooks.json              # SessionStart + UserPromptSubmit + Stop 钩子注册（node 内联调度器按平台选 .ps1/.sh）
│       ├── hooks\session-start.ps1|.sh   # 注入 HARNESS.md 的钩子（双平台）
│       ├── hooks\user-prompt-submit.ps1|.sh  # go 调用自动起跑 + 暂存每轮 query（双平台）
│       ├── hooks\stop.ps1|.sh            # 向 trace.jsonl 追加 round 心跳的钩子（双平台）
│       ├── plugin\flavor-plugin.json     # flavor-code 插件清单（声明 8 个生命周期钩子）
│       ├── plugin\index.js               # flavor-code 插件入口（registerHook + skillRoot）
│       ├── scripts\ralph-lib.ps1|.sh     # Ralph 状态库（go 跟踪 + 重试，钩子引用它；双平台）
│       └── skills\...                    # go + light + brainstorm + onboarding + worktree/subagent + 7 个核心工程技能（1.0.4 新增 receiving-code-review、converge）
│           └── brainstorm\scripts\       # server.cjs / mindmap.html / layout.js / start|stop-server.ps1
├── tests\run-tests.ps1      # 安装器/钩子测试套件（PowerShell，TDD）
├── tests\*.test.mjs         # 脑图服务器、布局与 flavor 插件钩子测试（node --test）
├── setup.cmd / setup.ps1    # Windows PATH 一次性配置
├── install-global.ps1       # Windows 全局安装器
├── install-global.sh        # macOS/Linux 全局安装器（安装到 ~/.local/superharness）
└── README.md
```

## 开发与测试

本项目自身按 TDD 构建，两套测试：

```cmd
:: 安装器 + 钩子（PowerShell，零依赖，Windows 侧）
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1

:: 脑图服务器 + 布局纯函数 + flavor 插件钩子（需 Node ≥ 18，跨平台）
node --test tests\
```

PowerShell 套件覆盖：安装产物完整性、marketplace.json/plugin.json/hooks.json 合法性、
`.claude/settings.json` 保留性合并与幂等、旧路径清理、CLAUDE.md 追加与幂等、命名空间替换
无残留、SessionStart 钩子的 JSON 输出与容错、brainstorm 技能与脚本就位、start/stop 服务器脚本、
任务追踪钩子（UserPromptSubmit 暂存 query、Stop 向 trace.jsonl 追加 round 心跳与容错、无活跃任务时 no-op）、
go 技能驱动 Ralph 跟踪与自动重试、安装器把 `.claude/superharness/ralph/` 写入目标 `.gitignore`、Ralph 状态库行为。
Node 套件覆盖：脑图树布局（确定性、无重叠、左右分布）、服务器 HTTP 端点与 server-info、
事件落盘、WebSocket 快照推送与文件监听、空闲自动退出、节点编辑协议（node:edit/submit 分流
至 state/edits、乐观更新清空时机、编辑面板 UI 就位）、flavor 插件钩子（模拟 flavor-code
HookBus 驱动 `index.js`：清单声明与注册一致性、SessionStart 注入 HARNESS.md/STACK.md、
UserPromptSubmit 对 `/go` 自动 bootstrap ralph 状态、Stop 心跳、SessionEnd 续跑指针保留、
SubagentStop 真实状态载荷与非法事件容错）、技能与模板内容断言（`skills-content.test.mjs`：receiving-code-review/converge 技能就位、
Analysis Findings 门禁、go Phase 4.5 收敛接线、stacks 三新节与 seam 强化）。

修改 `template\` 后无需重新安装本仓库——下次在项目里运行 `superharness` 即覆盖更新（安装器会
把插件 `version` 写为当前模板版本，确保 Claude Code 重新拉取缓存）；已初始化项目中改动插件文件后，
在 Claude Code 里执行 `/reload-plugins` 生效。

## 环境要求

- **Windows**（安装器与钩子为 PowerShell 实现）或 **macOS / Linux**（bash 实现；钩子 JSON 处理优先用 node，缺失时 python3 兜底）
- Node ≥ 18（`/superharness:brainstorm` 脑图服务器需要；bash 侧钩子 JSON 处理优先用它；其余功能不依赖）
- Claude Code ≥ 2.1.x（本地 marketplace 插件机制；本机验证版本 2.1.173）；或 flavor-code（插件系统：`flavor-plugin.json` + `registerHook` API）
