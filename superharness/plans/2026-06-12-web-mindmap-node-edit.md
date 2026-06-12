# Web 脑图节点编辑 Implementation Plan

> **For agentic workers:** Execute this plan task-by-task under the superharness:go workflow, Phase 2 (strict TDD per task). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 brainstorm 脑图加节点 `label`/`note` 的查看与编辑，编辑经"逐节点保存 + 全局提交"落入 `state/edits`，再同步回 agent 上下文。

**Architecture:** 服务端 `server.cjs` 的 `/event` 按 JSON `type` 分流——`node:edit`/`submit` 写 `state/edits`（不随快照清空），`node:click` 维持写 `state/events`（随快照清空）。前端 `mindmap.html` 双击节点弹编辑面板、逐节点保存、顶栏全局提交。`SKILL.md` 记录新协议与 agent 同步回合（Monitor 阻塞等 submit → 合并 → 分歧当面问 → 重写快照 → 清空 edits）。

**Tech Stack:** 零依赖 Node 20（`node:test` + `node:assert`），原生 HTTP / WebSocket，纯 HTML/JS 前端。

**源码真身在 `template/`**（测试引用它）；改完用 `lib/install.ps1` 同步到 `.claude/superharness/`。

**测试命令:** `node --test tests/`（从项目根运行）。

---

### Task 1: 服务端 `/event` 把 `node:edit` 路由到 state/edits

**Files:**
- Modify: `template/plugins/superharness/skills/brainstorm/scripts/server.cjs`（新增 `EDITS_FILE` 常量；`/event` 处理 18-31 行附近按 type 分流）
- Test: `tests/server.test.mjs`（新增用例）

- [ ] **Step 1: 写失败测试**

在 `tests/server.test.mjs` 末尾追加：

```javascript
test('POST node:edit appends to state/edits, not state/events', async t => {
  const { info, session } = await startServer(t);
  const evt = { type: 'node:edit', id: 'q1-a', label: '新标签', note: '新备注', timestamp: 1760000001 };
  const res = await fetch(info.url + '/event', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(evt),
  });
  assert.equal(res.status, 204);
  const editsPath = path.join(session, 'state', 'edits');
  const lines = fs.readFileSync(editsPath, 'utf-8').trim().split('\n');
  assert.equal(lines.length, 1);
  assert.deepEqual(JSON.parse(lines[0]), evt);
  // must NOT have leaked into events
  assert.ok(!fs.existsSync(path.join(session, 'state', 'events'))
    || fs.readFileSync(path.join(session, 'state', 'events'), 'utf-8') === '');
});
```

- [ ] **Step 2: 跑测试确认 RED**

Run: `node --test tests/server.test.mjs`
Expected: FAIL —— `node:edit` 当前落进 events，`state/edits` 不存在 → readFileSync 抛 ENOENT。

- [ ] **Step 3: 最小实现**

在 `server.cjs` 的常量区（`EVENTS_FILE` 那行下面，约第 18 行）新增：

```javascript
const EDITS_FILE = path.join(STATE_DIR, 'edits');
```

把 `/event` 处理体（当前 122-130 行）改为按 type 分流：

```javascript
      try {
        const msg = JSON.parse(body);
        const file = (msg.type === 'node:edit' || msg.type === 'submit') ? EDITS_FILE : EVENTS_FILE;
        fs.appendFileSync(file, body.trim() + '\n');
        res.writeHead(204);
        res.end();
      } catch {
        res.writeHead(400);
        res.end('invalid JSON');
      }
```

- [ ] **Step 4: 跑测试确认 GREEN**

Run: `node --test tests/server.test.mjs`
Expected: PASS（含既有 17 个用例仍绿）。

- [ ] **Step 5: 提交**

```bash
git add template/plugins/superharness/skills/brainstorm/scripts/server.cjs tests/server.test.mjs
git commit -m "feat(brainstorm): route node:edit events to state/edits"
```

---

### Task 2: `submit` 也进 state/edits；快照推送不清空 state/edits

**Files:**
- Modify: `template/plugins/superharness/skills/brainstorm/scripts/server.cjs`（分流已在 Task 1 覆盖 submit；本任务验证快照清空只动 events）
- Test: `tests/server.test.mjs`

- [ ] **Step 1: 写失败测试**

追加：

```javascript
test('POST submit goes to state/edits and survives a snapshot push', async t => {
  const { info, session } = await startServer(t);
  const ws = await wsConnect(info.port);
  t.after(() => ws.socket.destroy());
  await ws.nextMessage(); // initial snapshot

  // a saved edit + a submit marker
  await fetch(info.url + '/event', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ type: 'node:edit', id: 'n1', label: 'L', note: 'N', timestamp: 1 }),
  });
  await fetch(info.url + '/event', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ type: 'submit', timestamp: 2 }),
  });

  // push a snapshot — this clears events but must NOT clear edits
  const snapshot = { type: 'mindmap:snapshot', rev: 1, topic: 't', status: 'exploring',
    root: { id: 'root', label: 't', kind: 'topic' } };
  fs.writeFileSync(path.join(session, 'content', 'mindmap.json'), JSON.stringify(snapshot));
  const pushed = JSON.parse(await ws.nextMessage());
  assert.equal(pushed.rev, 1);

  const edits = fs.readFileSync(path.join(session, 'state', 'edits'), 'utf-8').trim().split('\n');
  assert.equal(edits.length, 2);
  assert.equal(JSON.parse(edits[1]).type, 'submit');
});
```

- [ ] **Step 2: 跑测试确认 RED 或 GREEN**

Run: `node --test tests/server.test.mjs`
Expected: 大概率直接 PASS —— Task 1 的分流已让 submit 进 edits，且现有快照监听只 `writeFileSync(EVENTS_FILE, '')`（不碰 edits）。若意外 FAIL，定位是否有别处清空了 edits。这一步是**回归护栏**，锁定"快照不清 edits"这个不变量。

- [ ] **Step 3: 实现（若 Step 2 已绿则跳过）**

确认 `server.cjs` 快照监听段（约 170-178 行）只清 `EVENTS_FILE`，不引入对 `EDITS_FILE` 的清空。无需改动。

- [ ] **Step 4: 跑全量确认 GREEN**

Run: `node --test tests/`
Expected: 全绿。

- [ ] **Step 5: 提交**

```bash
git add tests/server.test.mjs
git commit -m "test(brainstorm): submit survives snapshot push in state/edits"
```

---

### Task 3: 前端编辑面板 + 双击编辑 + 保存 + 全局提交

**Files:**
- Modify: `template/plugins/superharness/skills/brainstorm/scripts/mindmap.html`
- Test: `tests/server.test.mjs`（沿用既有"HTML 内容断言"模式，如第 167 行用例）

- [ ] **Step 1: 写失败测试**

追加（断言 HTML 含编辑面板与提交接线，与既有 grep 风格一致）：

```javascript
test('mind map page wires node editing and submit', async t => {
  const { info } = await startServer(t);
  const html = await (await fetch(info.url + '/')).text();
  assert.match(html, /id="editPanel"/);     // 编辑面板存在
  assert.match(html, /id="editLabel"/);      // label 输入框
  assert.match(html, /id="editNote"/);       // note 文本框
  assert.match(html, /id="submitBtn"/);      // 全局提交按钮
  assert.match(html, /node:edit/);           // 保存发 node:edit
  assert.match(html, /"submit"|'submit'/);   // 提交发 submit
  assert.match(html, /dblclick/);            // 双击触发
});
```

- [ ] **Step 2: 跑测试确认 RED**

Run: `node --test tests/server.test.mjs`
Expected: FAIL —— HTML 尚无 editPanel 等。

- [ ] **Step 3: 实现 mindmap.html**

(1) 顶栏 `#topbar`（当前 27-32 行）末尾、`#conn` 之后加一个全局提交按钮：

```html
  <button id="submitBtn" disabled style="margin-left:auto; background:#3d5afe; color:#fff; border:0; padding:6px 14px; border-radius:6px; cursor:pointer; font-size:13px;">提交 (0)</button>
```

(2) 在 `</body>` 前、`<script>` 之外加编辑面板浮层：

```html
<div id="editPanel" style="display:none; position:fixed; z-index:20; top:50%; left:50%; transform:translate(-50%,-50%); background:var(--panel); border:1px solid #3a3d4a; border-radius:10px; padding:16px; width:320px; box-shadow:0 8px 30px rgba(0,0,0,.5);">
  <div style="font-size:13px; color:var(--muted); margin-bottom:6px;">编辑节点</div>
  <input id="editLabel" type="text" placeholder="标签" style="width:100%; margin-bottom:8px; padding:6px 8px; background:var(--bg); color:var(--text); border:1px solid #3a3d4a; border-radius:6px;">
  <textarea id="editNote" rows="4" placeholder="备注 (note)" style="width:100%; padding:6px 8px; background:var(--bg); color:var(--text); border:1px solid #3a3d4a; border-radius:6px; resize:vertical;"></textarea>
  <div style="margin-top:10px; text-align:right;">
    <button id="editCancel" style="background:#3a3d4a; color:var(--text); border:0; padding:6px 12px; border-radius:6px; cursor:pointer;">取消</button>
    <button id="editSave" style="background:#2a9d8f; color:#fff; border:0; padding:6px 12px; border-radius:6px; cursor:pointer;">保存</button>
  </div>
</div>
```

(3) 在 `<script>` 内加编辑状态与逻辑。`pendingEdits` 暂存已保存未提交的编辑（`id -> {label,note}`），双击节点打开面板，保存 POST `node:edit` 并乐观更新，提交 POST `submit` 并清空暂存。

在 `let selectedId = null;`（约 47 行）后加：

```javascript
const pendingEdits = {};   // id -> { label, note }
let editingId = null;
const panel = document.getElementById('editPanel');
const submitBtn = document.getElementById('submitBtn');

function refreshSubmit() {
  const n = Object.keys(pendingEdits).length;
  submitBtn.textContent = '提交 (' + n + ')';
  submitBtn.disabled = n === 0;
}
function openEditor(n) {
  editingId = n.id;
  const pend = pendingEdits[n.id];
  document.getElementById('editLabel').value = pend ? pend.label : n.label;
  document.getElementById('editNote').value = pend ? (pend.note || '') : (n.note || '');
  panel.style.display = 'block';
}
function closeEditor() { panel.style.display = 'none'; editingId = null; }
document.getElementById('editCancel').addEventListener('click', closeEditor);
document.getElementById('editSave').addEventListener('click', () => {
  if (!editingId) return;
  const label = document.getElementById('editLabel').value;
  const note = document.getElementById('editNote').value;
  pendingEdits[editingId] = { label, note };
  fetch('/event', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ type: 'node:edit', id: editingId, label, note,
      timestamp: Math.floor(Date.now() / 1000) }),
  }).catch(() => {});
  closeEditor();
  refreshSubmit();
  if (lastSnap) render(lastSnap);
});
submitBtn.addEventListener('click', () => {
  fetch('/event', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ type: 'submit', timestamp: Math.floor(Date.now() / 1000) }),
  }).catch(() => {});
  for (const k of Object.keys(pendingEdits)) delete pendingEdits[k];
  refreshSubmit();
});
```

(4) 在 `render()` 里让节点显示 pending 编辑并支持双击。在 `render` 中构造 `label` 处（约 137 行 `const label = ...`）之前，用 pending 覆盖显示值；并给节点 `g` 加 dblclick。找到节点循环里 `g.addEventListener('click', () => sendClick(n));`（约 157 行），在其后加：

```javascript
    g.addEventListener('dblclick', e => { e.stopPropagation(); openEditor(n); });
```

并把该循环顶部的 `const label = (n.state === 'resolved' ? '✓ ' : '') + n.label;` 改为优先用 pending：

```javascript
    const pend = pendingEdits[n.id];
    const shownLabel = pend ? pend.label : n.label;
    const label = (n.state === 'resolved' ? '✓ ' : '') + shownLabel;
```

(5) 双击空白复位的 handler（约 73 行 `svg.addEventListener('dblclick', ...)`）已用 `!e.target.closest('.node')` 排除节点，节点上的 dblclick 不会触发复位——无需改，但确认节点 dblclick 的 `stopPropagation` 防冒泡到 svg。

- [ ] **Step 4: 跑测试确认 GREEN**

Run: `node --test tests/server.test.mjs`
Expected: 新用例 PASS，既有用例仍绿。

- [ ] **Step 5: 提交**

```bash
git add template/plugins/superharness/skills/brainstorm/scripts/mindmap.html tests/server.test.mjs
git commit -m "feat(brainstorm): node edit panel with save and global submit"
```

---

### Task 4: SKILL.md 记录编辑协议与 agent 同步回合

**Files:**
- Modify: `template/plugins/superharness/skills/brainstorm/SKILL.md`

无自动化测试（agent 面向的协议文档）。验收 = 内容审阅。

- [ ] **Step 1: 在 "Message protocol" 段补充 edits 协议**

在 `### Browser → Claude: read <state_dir>/events (JSONL)` 段之后，新增一节：

```markdown
### Browser → Claude: read `<state_dir>/edits` (JSONL)

Node label/note edits and the submit marker land here. Unlike `events`, this file is
**NOT cleared on snapshot push** — it persists until you merge and clear it.

\`\`\`json
{"type":"node:edit","id":"q1-a","label":"新标签","note":"新备注","timestamp":1760000000}
{"type":"submit","timestamp":1760000005}
\`\`\`

Only `label` and `note` are editable. Same `id` later in the file wins.
```

- [ ] **Step 2: 新增 "编辑回合" 说明**

在 Phase 5 内或作为协议补充，加入：

```markdown
### Edit round — pull browser edits into the design

When you invite the user to edit node text:

1. Tell them: 去浏览器双击节点改 label/note，逐个保存，改完点顶栏「提交」。
2. Do NOT end the turn. Block-wait for a `{"type":"submit"}` line in
   `<state_dir>/edits` using `Monitor` (fall back to `ScheduleWakeup`, ≤60s, if
   `Monitor` is unavailable). This only works while you are parked in this wait.
3. On submit: read `<state_dir>/edits`, take all `node:edit` lines (same `id` later
   wins), apply each `label`/`note` onto the current snapshot tree by `id`; ignore
   ids no longer present.
4. If a browser edit conflicts with what the terminal dialogue concluded for that
   node, ask in the terminal which wins.
5. Rewrite `<content_dir>/mindmap.json` (rev + 1), then clear `<state_dir>/edits`.
```

- [ ] **Step 3: 更新 Red Flags 表（可选一行）**

```markdown
| "用户在浏览器改了就直接采纳" | label/note 编辑要等「提交」，且与终端结论冲突时当面确认。 |
```

- [ ] **Step 4: 提交**

```bash
git add template/plugins/superharness/skills/brainstorm/SKILL.md
git commit -m "docs(brainstorm): document node-edit protocol and agent sync round"
```

---

### Task 5: 同步到 .claude 安装副本并全量验证

**Files:**
- Generated: `.claude/superharness/plugins/superharness/skills/brainstorm/scripts/*`、`SKILL.md`

- [ ] **Step 1: 跑全量测试**

Run: `node --test tests/`
Expected: 全绿，打印实际通过数。

- [ ] **Step 2: 同步 template → .claude**

Run:
```
powershell -NoProfile -ExecutionPolicy Bypass -File lib/install.ps1 -TargetDir .
```
Expected: 打印 "Superharness installed into ..."。

- [ ] **Step 3: 校验副本一致**

Run:
```bash
diff template/plugins/superharness/skills/brainstorm/scripts/server.cjs .claude/superharness/plugins/superharness/skills/brainstorm/scripts/server.cjs && echo SYNCED
```
Expected: `SYNCED`。

- [ ] **Step 4: 提交同步副本与计划/spec 勾选**

```bash
git add -A
git commit -m "chore(brainstorm): sync node-edit feature into local marketplace copy"
```

---

## Self-Review

- **Spec 覆盖**：D1 只编辑 label/note（Task 1/3）、D2 逐节点保存+全局提交（Task 3）、D3 state/edits 不随快照清空+合并后清空（Task 1/2 + SKILL Task 4 step2.5）、D4 冲突当面问（Task 4）、D5/D7 Monitor 轮询等待（Task 4）、D6 复用 /event 按 type 路由（Task 1）。全部有任务对应。
- **占位符扫描**：无 TBD；每个代码步给出实际代码。
- **类型一致**：`EDITS_FILE`、`pendingEdits`、`openEditor`、`refreshSubmit`、`editingId` 跨步骤命名一致；事件 `type` 值 `node:edit` / `submit` 全程一致。
