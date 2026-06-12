# Spec — Web 脑图节点查看与编辑，并同步回 agent 上下文

- **日期**: 2026-06-12
- **状态**: approved（经 `/superharness:brainstorm` 协作设计）
- **目标技能**: `superharness:brainstorm`（脑图前端 + 服务端 + skill 协议）
- **实现入口**: `/superharness:go 在 brainstorm 脑图里支持节点 label/note 的查看与编辑，并把编辑同步回 agent 上下文`

## 1. 背景与问题

当前 `superharness:brainstorm` 的脑图是**内容单向流动**：

```
Claude ──写 content/mindmap.json──> server ──WebSocket──> 浏览器   (内容，单向)
浏览器 ──POST /event──────────────> state/events (JSONL) ──Claude 读取   (仅 node:click 点击信号)
```

浏览器对内容**只读**：节点详情只有 `note` 的 hover tooltip（`mindmap.html` 的 `<title>`），无详情/编辑面板；浏览器→Claude 只有 `node:click` 一种事件，且"终端答案永远覆盖浏览器"。因此用户无法在 web 上修改节点内容并让改动指导后续任务。

本 spec 为脑图增加**节点内容编辑**能力，并把编辑**同步回 agent 上下文**。

## 2. 范围

- **可编辑字段**: 仅 `label` + `note`。不改节点结构（增删节点）、不改 `kind` / `state`。
- 仅作用于 `superharness:brainstorm` 会话；普通 `/superharness:go` 任务不在范围内（见风险 R1）。

## 3. 已确认的需求决策

| # | 决策 | 说明 |
|---|------|------|
| D1 | 只编辑 `label` + `note` | 不动结构 / kind / state |
| D2 | 逐节点保存 + 全局提交 | 面板「保存」只本地暂存；改完统一点「提交」才唤醒 agent |
| D3 | 编辑存 `state/edits` 独立文件 | **不**随快照清空；合并进权威快照后才清空 |
| D4 | 冲突时 agent 当面问 | 合并时若某节点浏览器编辑与终端结论分歧，在终端确认以谁为准 |
| D5 | 提交触发唤醒 = 轮询等待 | agent 编辑期间不结束回合，阻塞轮询 `state/edits` 的 `submit` 标记；仅脑暴等待循环内有效 |
| D6 | 服务端复用 `/event` 按 `type` 路由 | 最小改动，保留现有点击语义 |
| D7 | 轮询原语优先 `Monitor` | 比 `ScheduleWakeup`（≥60s 下限）快；submit 出现即返回。`ScheduleWakeup` 为回退 |

## 4. 设计

### ① 前端编辑 UI（`scripts/mindmap.html`）

- **双击节点** → 弹出 HTML 浮层编辑面板（非 SVG）：
  - `label` 输入框（预填当前 label）
  - `note` 文本框（预填当前 note）
  - 「保存」「取消」按钮
  - 双击空白仍复位视图——现有 `dblclick` 已用 `.node` 判断隔开，二者不冲突。
- **「保存」** → `POST /event` body `{type:"node:edit", id, label, note, timestamp}`：
  - 节点立刻**乐观更新**（本地 `lastSnap` 内存改），并显示 pending 视觉标记（如虚线框 / 角标）。
  - **不**唤醒 agent。
- **顶栏「提交」按钮**：
  - 显示当前待交编辑数量；无待交时禁用。
  - 点击 → `POST /event` body `{type:"submit", timestamp}`。
- 注意：服务器推新快照（WebSocket）时前端会重渲染并 `selectedId=null`；pending 编辑的乐观显示在被权威快照覆盖前应保留——以本地暂存的编辑集合为准叠加渲染。

### ② 服务端路由（`scripts/server.cjs`）

- 新增常量 `const EDITS_FILE = path.join(STATE_DIR, 'edits');`
- `POST /event` 处理里，`JSON.parse(body)` 成功后按 `type` 分流：
  - `node:edit` / `submit` → `appendFileSync(EDITS_FILE, ...)`（**不**随快照清空）
  - 其它（`node:click`）→ `appendFileSync(EVENTS_FILE, ...)`（保持现状）
- 快照监听 interval（清空 `EVENTS_FILE` 的那段）**只清 `EVENTS_FILE`，不碰 `EDITS_FILE`** —— 现有代码已只清 events，无需改动。
- 现有点击流、WebSocket、快照广播逻辑零改动。

### ③ agent 同步逻辑（`skills/brainstorm/SKILL.md` 协议）

新增"编辑回合"约定（建议落在 Phase 5 设计验证环节，或作为可随时进入的独立步骤）：

1. agent 提示用户："去浏览器改 `label`/`note`，逐个保存，改完点提交。"
2. agent **不结束回合**，用 `Monitor` 阻塞等待 `state/edits` 中出现 `{type:"submit"}` 行（`Monitor` 不可用时回退 `ScheduleWakeup`，延迟 ≤60s）。
3. 探到 submit 后读取 `state/edits`：解析所有 `node:edit` 行，**同 `id` 后写覆盖**，按 `id` 把 `label`/`note` 合并进当前快照树；`id` 已不存在的编辑忽略。
4. 合并时若某节点浏览器编辑与终端讨论结论**分歧**，在终端询问以谁为准（D4）。
5. 重写 `content/mindmap.json`（`rev` + 1）→ **清空 `state/edits`**。

### 协议补充（写进 SKILL.md 的 Message protocol）

```json
// 浏览器 → Claude，写入 state/edits（不随快照清空）
{"type":"node:edit","id":"q1-a","label":"新标签","note":"新备注","timestamp":1760000000}
{"type":"submit","timestamp":1760000005}
```

## 5. 风险

| # | 风险 | 处置 |
|---|------|------|
| R1 | 即时响应仅限脑暴等待循环内 | 普通 `/go` 任务无常驻轮询；超出本次范围，文档说明即可 |
| R2 | `Monitor` 不可用回退 `ScheduleWakeup` 时延迟 ≤60s | 可接受；文档标注 |
| R3 | 未点提交就结束会话 = 编辑丢弃 | 可接受（`state/edits` 仅在合并后清空，会话结束随 `.superharness/` 丢弃） |

## 6. 实现提示（TDD）

- 服务端路由：对 `server.cjs` 的 `/event` 写测试——POST `node:edit` 应只落 `EDITS_FILE`、不落 `EVENTS_FILE`；POST `node:click` 反之；快照推送后 `EDITS_FILE` 内容保留、`EVENTS_FILE` 被清空。
- 前端：可对编辑面板的 DOM 行为 / POST payload 构造做轻量测试（或以服务端契约测试为主）。
- 合并逻辑：以"同 id 后写覆盖"、"不存在 id 忽略"、"分歧触发询问"为用例。
