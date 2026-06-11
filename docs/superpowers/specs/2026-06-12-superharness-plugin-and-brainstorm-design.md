# Superharness 插件化加载 + /superharness:brainstorm 脑图技能 — 设计文档

日期：2026-06-12
状态：已获用户批准的设计（待实施）

## 背景与目标

superharness 目前通过 `lib/install.ps1` 把 `template/` 复制到目标项目的
`.claude/skills/superharness/`，并假设它会被加载为 `superharness@skills-dir` 插件。
经验证该假设不成立：Claude Code 的项目技能目录要求 `.claude/skills/<技能名>/SKILL.md`
扁平结构，且不产生 `superharness:` 命名空间，因此 `/superharness:go` 实际不可用。

本设计完成两件事：

1. **插件化改造**：让 superharness CLI 初始化后的项目以真实插件方式加载，
   获得 `/superharness:go` 等命名空间技能，SessionStart hook 自动生效。
2. **新增 `/superharness:brainstorm` 技能**：仅用户手动触发；执行基于 superpowers
   brainstorming 的需求/设计澄清流程，全程伴随一个浏览器脑图（mind map）实时可视化，
   支持拖拽平移、滚轮缩放、节点点选回传。

## 非目标

- 不实现 brainstorm 的自动触发（模型不得自行调用该技能）。
- 不实现脑图节点的浏览器端编辑（增删改节点只由 Claude 完成）。
- v1 不支持浏览器端评论输入，反馈以终端文字为主、节点点选为辅。
- 不依赖任何 npm 包或 CDN 资源，完全离线可用。

## 已确认的决策

| 决策点 | 结论 |
|---|---|
| 触发方式 | 仅手动 `/superharness:brainstorm`，SKILL.md 设 `disable-model-invocation: true` |
| 脑图时机 | 实时伴随整个 brainstorm 流程，随问答增量生长 |
| 反向交互 | 支持节点点选回传（events 文件），拖拽/缩放为纯视图操作不回传 |
| 技术栈 | 单文件零依赖 Node 服务器（本机 Node v20）+ 前端原生 SVG 自绘脑图 |
| 消息通道 | 文件监听 + WebSocket 全量快照推送；**不使用 hook** |
| 流程终点 | 写设计文档到 `superharness/specs/`，提示用户可转 `/superharness:go`，不自动衔接 |

## 1. 插件化改造

### 1.1 目标项目结构（初始化后）

```
<project>/
  .claude/
    settings.json                        ← 合并写入 marketplace/插件启用配置
    superharness/                        ← marketplace 根目录
      .claude-plugin/marketplace.json    ← 目录型 marketplace 目录文件
      plugins/superharness/              ← 插件本体（即现有 template 内容 + 新增 brainstorm）
        .claude-plugin/plugin.json
        HARNESS.md
        hooks/hooks.json
        hooks/session-start.ps1
        skills/go/SKILL.md
        skills/brainstorm/SKILL.md
        skills/brainstorm/scripts/server.cjs
        skills/brainstorm/scripts/mindmap.html
        skills/brainstorm/scripts/start-server.ps1
        skills/brainstorm/scripts/stop-server.ps1
        skills/writing-plans/...
        skills/test-driven-development/...
        skills/systematic-debugging/...
        skills/requesting-code-review/...
        skills/verification-before-completion/...
```

### 1.2 marketplace.json

```json
{
  "name": "superharness",
  "owner": { "name": "wangzh" },
  "plugins": [
    {
      "name": "superharness",
      "source": "./plugins/superharness",
      "description": "Project-level autonomous engineering harness"
    }
  ]
}
```

### 1.3 settings.json 合并

安装器对 `<project>/.claude/settings.json` 做**保留性 JSON 合并**（已有键不丢失，
仅覆写下列两个键中属于 superharness 的条目）：

```json
{
  "extraKnownMarketplaces": {
    "superharness": {
      "source": { "source": "directory", "path": ".claude/superharness" }
    }
  },
  "enabledPlugins": { "superharness@superharness": true }
}
```

依据：官方 settings JSON schema 确认 `extraKnownMarketplaces` 支持
`{"source":"directory","path":...}`；`enabledPlugins` 为 `"插件名@marketplace名": true`。
效果：用户信任项目目录后自动注册并启用插件，得到 `/superharness:go`、
`/superharness:brainstorm`，插件 hooks 自动生效。

### 1.4 版本与更新

插件启用时会被复制到 `~/.claude/plugins/cache`，以 `plugin.json` 的 `version`
判断更新。因此 **安装器每次运行时将目标项目里 plugin.json 的 `version` 写为
本次安装的模板版本号**（模板源以 `template/.claude-plugin/plugin.json` 的 version
为准，发布新模板时人工递增）。重复安装同版本为幂等覆盖。

### 1.5 迁移与清理

- 安装器检测并删除旧路径 `.claude/skills/superharness/`（旧方式残留）。
- CLAUDE.md 托管段落（`SUPERHARNESS:BEGIN/END` 标记）改写：说明插件经
  `.claude/superharness` marketplace 加载；兜底指引改为读
  `.claude/superharness/plugins/superharness/HARNESS.md`。

## 2. /superharness:brainstorm 技能流程

SKILL.md frontmatter：`name: brainstorm`，`disable-model-invocation: true`，
`argument-hint: [主题]`。

流程：

1. **启动会话**：运行 `scripts/start-server.ps1 -ProjectDir <project>`。脚本用
   `Start-Process` 后台拉起 node、等待 `state/server-info` 出现后输出其内容并退出，
   因此普通前台工具调用即可。会话目录为
   `<project>/.superharness/brainstorm/<yyyyMMdd-HHmmss-pid>/`，含 `content/` 与
   `state/`。从输出（或 `state/server-info`）获取 URL，告知用户在浏览器打开。
   提醒用户将 `.superharness/` 加入 `.gitignore`。
2. **探索上下文**：读项目文件/文档/近期提交；写入首个快照（根节点 = 主题）。
3. **澄清问题**（一次一个）：每提出一个问题，把"问题 + 候选项"作为节点推送脑图；
   用户通过终端回答（可同时在浏览器点选节点）；Claude 读取 `state/events` 与终端
   文字，把选中项标 `chosen`、淘汰项标 `rejected`、问题标 `resolved`。
4. **方案阶段**：提出 2-3 个方案作为方案分支推送，含取舍说明，标注推荐项；
   确定后更新状态。
5. **设计呈现**：按节呈现设计，每节获认可后把要点固化为 `decision`/`requirement`
   节点；`status` 推进为 `designing`。
6. **收尾**：设计获批后 `status: approved`；写设计文档到
   `superharness/specs/YYYY-MM-DD-<topic>.md`；运行 `stop-server.ps1` 停止服务器；
   提示用户："可运行 `/superharness:go <目标>` 按此设计实施"。不自动衔接。

降级规则：服务器启动失败或中途不可用时，流程降级为纯终端继续，绝不阻塞。
每次写快照前检查 `state/server-info` 存在且无 `state/server-stopped` 标记，
否则先重启服务器。

## 3. 消息格式定义

### 3.1 Claude → 前端：脑图快照

文件：`<session>/content/mindmap.json`（Claude 用 Write 工具全量重写）。
服务器监听文件变化后经 WebSocket 原样推送；客户端连入/重连时立即收到最新快照。

```json
{
  "type": "mindmap:snapshot",
  "rev": 7,
  "topic": "用户登录功能",
  "status": "exploring",
  "root": {
    "id": "root",
    "label": "用户登录功能",
    "kind": "topic",
    "children": [
      {
        "id": "q1", "label": "认证方式？", "kind": "question", "state": "resolved",
        "children": [
          { "id": "q1-a", "label": "JWT", "kind": "option", "state": "chosen", "note": "无状态、易扩展" },
          { "id": "q1-b", "label": "Session", "kind": "option", "state": "rejected" }
        ]
      },
      { "id": "d1", "label": "决策：Node 零依赖", "kind": "decision", "state": "resolved" }
    ]
  }
}
```

字段约定：

- `rev`：单调递增整数，Claude 每次写快照时 +1；前端丢弃 `rev` 不大于当前值的消息。
- `status`：`exploring | designing | approved`，前端顶栏展示阶段。
- 节点 `id`：会话内唯一且稳定（同一节点跨快照保持同一 id）。
- `kind`：`topic | question | option | decision | requirement | risk | note`，决定配色/图标。
- `state`：`open | chosen | rejected | resolved`，决定高亮（chosen）、置灰删除线
  （rejected）、对勾（resolved）；缺省为 `open`。
- `note`：可选悬浮提示文本。
- `children`：可选子节点数组。

### 3.2 前端 → Claude：交互事件

文件：`<session>/state/events`（JSONL，追加写；服务器收到新快照时清空）。
浏览器通过 `POST /event` 上报，服务器落盘。

```json
{"type":"node:click","id":"q1-a","label":"JWT","kind":"option","timestamp":1760000000}
```

v1 仅定义 `node:click`。Claude 每轮先读 events 再结合终端文字理解用户意图；
events 不存在表示用户未在浏览器交互。

### 3.3 服务器启动信息

文件：`<session>/state/server-info`（JSON，服务器启动时写入）：

```json
{
  "type": "server-started",
  "port": 52341,
  "url": "http://localhost:52341",
  "pid": 12345,
  "content_dir": "<session>/content",
  "state_dir": "<session>/state"
}
```

服务器正常退出时写 `state/server-stopped`（空文件）并删除 `server-info`。

## 4. 服务器（server.cjs）

单文件零依赖 Node 脚本（参考 superpowers `server.cjs` 裁剪重写）：

- HTTP：`GET /` 返回 `mindmap.html`；`GET /mindmap.json` 返回当前快照（兜底）；
  `POST /event` 追加 JSONL 到 `state/events`。
- WebSocket（RFC 6455 手写实现）：客户端连入即推最新快照；之后每次
  `mindmap.json` 变化（500ms mtime 轮询）推送新快照并清空 events。
- 端口：环境变量指定或 49152-65535 随机；host 默认 `127.0.0.1`。
- 生命周期：30 分钟无活动（无文件变化且无客户端消息）自动退出；退出时写
  `server-stopped`。
- 启停脚本为 PowerShell（`start-server.ps1` / `stop-server.ps1`，Windows 优先），
  start 脚本创建会话目录、后台拉起 node、等待 `server-info` 出现后输出其内容。

## 5. 前端（mindmap.html）

单文件页面，原生 SVG/JS，无外部资源：

- **布局**：经典水平脑图——根节点居中，子树左右分布（按子树高度均衡），
  紧凑树布局算法（按子树包围盒高度自底向上累加），三次贝塞尔连线。
- **交互**：鼠标拖拽平移画布；滚轮以光标为中心缩放（0.2x–4x）；双击空白复位视图；
  点击节点 → 选中描边 + `POST /event` 上报 `node:click`。
- **渲染**：节点按 `kind` 着色，按 `state` 呈现（chosen 高亮、rejected 置灰删除线、
  resolved 加对勾）；`note` 悬浮显示。
- **顶栏**：主题、阶段（status）、rev、WebSocket 连接状态；断线每 2s 自动重连。
- 布局计算抽为纯函数（独立 `<script>` 块或可被 node 直接 require 的结构），便于测试。

## 6. 错误处理

| 故障 | 行为 |
|---|---|
| Node 不存在 / 服务器启动失败 | 技能降级为纯终端 brainstorm，告知用户原因 |
| 服务器中途退出 | 写快照前检查 server-info，缺失则重启后再写 |
| WebSocket 断连 | 前端自动重连，重连后收到最新快照（rev 幂等） |
| events 文件不存在 | 视为无浏览器交互，仅用终端文字 |
| settings.json 已有用户配置 | 保留性合并，仅增改 superharness 相关条目 |
| 旧版安装残留 | 安装器删除 `.claude/skills/superharness/` |

## 7. 测试策略（遵循 HARNESS TDD）

- **install.ps1**（PowerShell 测试，扩展 `tests/run-tests.ps1`）：
  - marketplace/plugin 文件落位正确；
  - settings.json：从无到有创建、与已有配置合并不丢键、重复安装幂等；
  - plugin.json version 随模板版本写入；
  - 旧路径清理；CLAUDE.md 托管段落创建/替换。
- **server.cjs**（`node --test`）：
  - 启动后 server-info 内容正确；
  - 写 mindmap.json → WS 客户端收到快照、events 被清空；
  - POST /event → events JSONL 追加；
  - 新客户端连入收到最新快照；rev 透传。
- **布局纯函数**（`node --test`）：给定树返回无重叠坐标、左右分布、确定性输出。

## 8. 验收标准

1. 在干净目录运行 superharness CLI 初始化后，启动 Claude Code 并信任目录，
   `/superharness:go` 与 `/superharness:brainstorm` 均出现在技能列表且可调用，
   SessionStart 注入 HARNESS.md。
2. 运行 `/superharness:brainstorm <主题>` 后浏览器打开本地 URL 能看到脑图；
   Claude 推送快照后脑图 1 秒内更新；拖拽、滚轮缩放正常。
3. 点击节点后，`state/events` 出现对应 `node:click` 行，Claude 下一轮能读到。
4. 流程结束生成 `superharness/specs/` 设计文档，服务器停止，无残留进程。
5. 全部测试通过（PowerShell 测试 + node --test）。
