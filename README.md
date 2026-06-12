# Superharness

给 Claude Code 的项目级工程纪律"线束"（harness）。一条命令初始化项目，之后在 Claude Code 中用
`/superharness:go <任务目标>` 即可让 AI 在严格约束（TDD、系统化调试、完成前验证、代码审查）下
自主完成开发任务；用 `/superharness:brainstorm <主题>` 在浏览器实时脑图里梳理需求与设计。

加载方式：初始化时把插件安装为 **本地 marketplace**（`.claude/superharness`），并在
`.claude/settings.json` 中通过 `extraKnownMarketplaces` + `enabledPlugins` 自动启用——
信任项目目录后即获得 `/superharness:*` 命名空间技能与 SessionStart 钩子。

核心技能内容移植自 [obra/superpowers](https://github.com/obra/superpowers)（MIT License），
并为自主工作流做了适配。

> 📐 想快速看懂整体设计（含架构图、安装/会话/脑图流程图）？见
> [技术方案文档.md](技术方案文档.md)。

这会把 `bin\` 目录加入用户 PATH（幂等、追加式，不会截断已有 PATH）。**打开新终端后生效。**

> 卸载：从用户环境变量 PATH 中删除该 bin 路径即可；已初始化的项目删除
> `.claude\superharness\`、`.claude\settings.json` 中的 superharness marketplace/插件条目，
> 以及 CLAUDE.md 中的 SUPERHARNESS 标记段。

## 使用方法

### 1. 初始化项目（命令行）

在任意项目根目录下（cmd 或 PowerShell 均可）：

```cmd
superharness
```

这会创建：

| 产物 | 作用 |
|------|------|
| `.claude\superharness\` | 本地 marketplace 目录（`.claude-plugin\marketplace.json` + `plugins\superharness\` 插件本体，含全部技能） |
| `.claude\settings.json` 中的 `extraKnownMarketplaces` + `enabledPlugins` | 自动注册并启用该 marketplace 的插件（保留性合并，不破坏已有配置） |
| `CLAUDE.md` 中的 SUPERHARNESS 标记段 | Claude Code 自动读取的兜底指引（已有内容会被保留，重复执行不会重复追加） |

#### 技术栈模板（可选）

初始化时可附带 `--template` 为项目注入对应技术栈的工程纪律指引（经 SessionStart 钩子每会话注入）：

```cmd
superharness --template=frontend            :: 默认 React
superharness --template=frontend --stack=vue
superharness --template=backend             :: 默认 Python
superharness --template=backend --stack=java
superharness --template=backend --stack=node
superharness --template=fullstack           :: 固定 React + Python（不接受 --stack）
```

合法 `--stack`：前端 `react|vue`，后端 `python|java|node`。指引文档随插件下发于
`plugins\superharness\stacks\*.md`，选中的一份会被写入 `.claude\superharness\STACK.md`；
不带 `--template` 的普通初始化不写该文件（已有的会被移除）。

### 2. 启动 Claude Code

在该项目目录运行 `claude`（首次需在信任弹窗中信任工作区）。此后：

- 插件经 `.claude/superharness` 本地 marketplace 自动加载 —— 无需任何安装命令；
- 插件的 **SessionStart 钩子**自动把 `HARNESS.md`（约束规则）注入每个会话上下文；
- 各技能以 `/superharness:*` 命名空间注册。`go` 等会按 description 自动触发；
  `brainstorm` 设了 `disable-model-invocation`，仅在你手动运行时启动。

### 3. 执行任务

```
/superharness:go 给登录接口增加验证码校验
```

`go` 技能驱动五阶段自主工作流：

1. **理解** —— 探索代码、确认目标，必要时一轮澄清
2. **计划** —— `writing-plans`：拆成 2-5 分钟的 TDD 小任务，存到 `superharness/plans/`
3. **实现** —— `test-driven-development`：每个任务严格红-绿-重构-提交；出问题转 `systematic-debugging`
4. **验证** —— `verification-before-completion`：跑完整测试套件，贴出真实输出
5. **审查** —— `requesting-code-review`：派子代理审查 diff，严重问题阻塞收尾

### 4. 任务过程跟踪与恢复（resume）

`go` 执行过程中，**每一轮需要用户介入的对话都会被自动记录**到每任务一个的单行最小化 JSON：
`superharness/trace/<YYYY-MM-DD-slug>.json`。记录由两个钩子负责，不依赖 Claude 记忆：

- **UserPromptSubmit 钩子**无条件捕获该轮的用户 query 与时间戳；
- **Stop 钩子**在 Claude 交还控制权时合成该轮记录并追加进 trace 文件，随后消费临时标记。

成败主要看 **test case**（由 `go` 在跑完测试后写的 `outcome.json` 标记决定）：

| 该轮情况 | 记录内容 |
|----------|----------|
| 跑了测试且全绿 | `outcome:"success"`，仅记 `task completed` |
| 跑了测试且有失败 | `outcome:"failure"`，记失败用例（名称/文件/消息）+ query + 时间 + `test_command` |
| 该轮没跑测试 / 标记缺失 | `outcome:"in_progress"`，记 query + 时间 + 一句话摘要（确保"每轮都被记录"无条件成立） |

恢复一个未完成的任务：

```
/superharness:resume                 :: 取最近一个 status≠completed 的 trace
/superharness:resume 2026-06-12-xxx  :: 指定 slug
```

`resume`（仅手动触发）会读回 trace、向你汇报失败用例并**等你确认**，随后走完整的
**复现 → 定位根因（systematic-debugging）→ 改码（TDD）→ 验证**闭环，把出问题的代码真正修好，
而非盲目重跑；每次尝试都累积进 trace。临时标记位于 `superharness/trace/.state/`（已加入 `.gitignore`）。

### 5. 脑图脑暴（手动触发）

```
/superharness:brainstorm 给登录接口设计验证码方案
```

`brainstorm` 技能启动一个零依赖 Node 本地服务器并在浏览器打开**实时脑图**，全程伴随
需求澄清与方案讨论：每提一个问题/确定一个决策，Claude 就把脑图结构推送到页面。脑图支持
**拖拽平移、滚轮缩放、双击复位**；节点按类型着色、按状态高亮（已选/淘汰/已定）；点击节点可
把选择反馈给 Claude。流程结束生成设计文档到 `superharness/specs/`，并提示你可转
`/superharness:go` 实施。

消息协议（详见
[设计文档](docs/superpowers/specs/2026-06-12-superharness-plugin-and-brainstorm-design.md)）：

- **Claude → 前端**：把全量快照写入 `<session>/content/mindmap.json`（`mindmap:snapshot`，
  含 `rev`/`status`/树形 `root`），服务器监听文件变化后经 WebSocket 推送。
- **前端 → Claude**：节点点击经 `POST /event` 落盘 `<session>/state/events`（JSONL，
  `node:click`），Claude 下一轮读取并结合终端文字理解意图。

脑图不可用时（如无 Node）流程自动降级为纯终端，绝不阻塞脑暴。会话产物落在
`.superharness/`（已加入 `.gitignore`）。

## 内含技能

| 技能 | 来源 | 触发时机 |
|------|------|----------|
| `superharness:go` | 本项目 | 用户给出端到端任务目标 |
| `superharness:resume` | 本项目 | **仅手动** `/superharness:resume`，从 trace 复现并修复失败的任务 |
| `superharness:brainstorm` | 本项目（流程参考 superpowers） | **仅手动** `/superharness:brainstorm`，实时脑图梳理需求设计 |
| `superharness:writing-plans` | superpowers（适配） | 多步任务动代码之前 |
| `superharness:test-driven-development` | superpowers | 实现任何功能/修复之前 |
| `superharness:systematic-debugging` | superpowers | 任何 bug、测试失败、异常行为 |
| `superharness:verification-before-completion` | superpowers | 声称"完成/修好/通过"之前 |
| `superharness:requesting-code-review` | superpowers | 任务完成、合并之前 |

## 仓库结构

```
superharness\
├── bin\superharness.cmd     # CLI 入口（PATH 上可直接调用）
├── lib\install.ps1          # 安装器逻辑（可测试）
├── template\                # 被复制进项目的 .claude/superharness（本地 marketplace）
│   ├── .claude-plugin\marketplace.json   # marketplace 目录文件
│   └── plugins\superharness\             # 插件本体
│       ├── .claude-plugin\plugin.json    # 插件清单（提供 superharness: 命名空间）
│       ├── HARNESS.md                    # 会话启动时注入的约束规则
│       ├── hooks\hooks.json              # SessionStart + UserPromptSubmit + Stop 钩子注册
│       ├── hooks\session-start.ps1       # 注入 HARNESS.md 的脚本
│       ├── hooks\trace-lib.ps1           # 追踪钩子共享辅助（最小化 JSON 读写）
│       ├── hooks\user-prompt-submit.ps1  # 捕获每轮 query 的钩子
│       ├── hooks\stop.ps1                # 合成并落盘每轮记录的钩子
│       └── skills\...                    # go + resume + brainstorm + 5 个核心技能
│           └── brainstorm\scripts\       # server.cjs / mindmap.html / layout.js / start|stop-server.ps1
├── tests\run-tests.ps1      # 安装器/钩子测试套件（PowerShell，TDD）
├── tests\*.test.mjs         # 脑图服务器与布局测试（node --test）
├── setup.cmd / setup.ps1    # PATH 一次性配置
└── README.md
```

## 开发与测试

本项目自身按 TDD 构建，两套测试：

```cmd
:: 安装器 + 钩子（PowerShell，零依赖，158 个断言）
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1

:: 脑图服务器 + 布局纯函数（需 Node ≥ 18，17 个用例）
node --test tests\
```

PowerShell 套件覆盖：安装产物完整性、marketplace.json/plugin.json/hooks.json 合法性、
`.claude/settings.json` 保留性合并与幂等、旧路径清理、CLAUDE.md 追加与幂等、命名空间替换
无残留、SessionStart 钩子的 JSON 输出与容错、brainstorm 技能与脚本就位、start/stop 服务器脚本、
任务追踪钩子（UserPromptSubmit 捕获、Stop 的成功/失败/in_progress 落盘与容错）、resume 技能就位。
Node 套件覆盖：脑图树布局（确定性、无重叠、左右分布）、服务器 HTTP 端点与 server-info、
事件落盘、WebSocket 快照推送与文件监听、空闲自动退出。

修改 `template\` 后无需重新安装本仓库——下次在项目里运行 `superharness` 即覆盖更新（安装器会
把插件 `version` 写为当前模板版本，确保 Claude Code 重新拉取缓存）；已初始化项目中改动插件文件后，
在 Claude Code 里执行 `/reload-plugins` 生效。

## 环境要求

- Windows（安装器与钩子为 PowerShell 实现）
- Node ≥ 18（仅 `/superharness:brainstorm` 脑图服务器需要；其余功能不依赖 Node）
- Claude Code ≥ 2.1.x（本地 marketplace 插件机制；本机验证版本 2.1.173）