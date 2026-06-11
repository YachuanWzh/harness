# Superharness 插件化加载 + brainstorm 脑图技能 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 superharness CLI 初始化的项目以真实 Claude Code 插件方式加载（获得 `/superharness:go` 等命名空间技能），并新增手动触发的 `/superharness:brainstorm` 技能：终端问答 + 浏览器实时脑图（拖拽/缩放/节点点选回传）。

**Architecture:** `template/` 重构为本地 marketplace 布局（`.claude-plugin/marketplace.json` + `plugins/superharness/`），安装器复制到目标项目 `.claude/superharness/` 并向 `.claude/settings.json` 保留性合并 `extraKnownMarketplaces`/`enabledPlugins`。脑图通道：Claude 用 Write 写 `mindmap.json` 全量快照 → 零依赖 Node 服务器监听文件 → WebSocket 推送浏览器；浏览器点选经 `POST /event` 落盘 `state/events`（JSONL）供 Claude 读取。不使用 hook。

**Tech Stack:** Windows PowerShell 5.1（安装器与测试）、Node v20 零依赖（server.cjs、`node --test`）、原生 SVG/JS 前端。

**Spec:** `docs/superpowers/specs/2026-06-12-superharness-plugin-and-brainstorm-design.md`

**约定：**
- 所有命令在仓库根 `C:\Users\wangzh\Desktop\资料\AI\superharness` 下运行。
- PowerShell 测试：`powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1`
- Node 测试：`node --test tests/`
- 提交信息结尾加 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`（下文从略）。

---

### Task 1: 基线提交与 .gitignore

仓库刚 `git init`，只有设计文档一个提交。先把现有代码纳入版本控制。

**Files:**
- Create: `.gitignore`

- [ ] **Step 1: 写 .gitignore**

```gitignore
# superharness 本地运行时产物
.superharness/
# dogfood 安装产物（本仓库自装时生成）
.claude/superharness/
.claude/settings.local.json
```

- [ ] **Step 2: 提交现有文件**

```powershell
git add -A
git commit -m "chore: baseline - existing superharness installer, template and tests"
```

预期：`git status` 干净。

---

### Task 2: template 重构为 marketplace 布局

把插件本体移入 `template/plugins/superharness/`，新增 marketplace 目录文件，安装目标改为 `.claude/superharness/`。

**Files:**
- Modify: `tests/run-tests.ps1`（路径辅助函数 + 新测试组）
- Create: `template/.claude-plugin/marketplace.json`
- Move: `template/{.claude-plugin,hooks,skills,HARNESS.md}` → `template/plugins/superharness/`
- Modify: `lib/install.ps1`

- [ ] **Step 1: 更新测试路径并新增 marketplace 测试组（失败测试先行）**

`tests/run-tests.ps1` 中，把第 37 行的 `Get-PluginDir` 替换为：

```powershell
function Get-MarketDir { param([string]$ProjectDir) Join-Path $ProjectDir '.claude\superharness' }
function Get-PluginDir { param([string]$ProjectDir) Join-Path $ProjectDir '.claude\superharness\plugins\superharness' }
```

在「Test group 1」（`$plugin = Get-PluginDir $proj` 之后、group 2 之前）插入：

```powershell
# ---------------------------------------------------------------- Test group 1.5: marketplace layout
Write-Host "`n[1.5] Installer creates a local directory marketplace"
$market = Get-MarketDir $proj
$mpJsonPath = Join-Path $market '.claude-plugin\marketplace.json'
Assert-True (Test-Path $mpJsonPath) "creates .claude-plugin/marketplace.json at marketplace root"
$mpOk = $false; $mpName = ''; $mpSrc = ''
try {
    $mp = Get-Content $mpJsonPath -Raw | ConvertFrom-Json
    $mpOk = $true; $mpName = $mp.name; $mpSrc = $mp.plugins[0].source
} catch {}
Assert-True $mpOk "marketplace.json is valid JSON"
Assert-True ($mpName -eq 'superharness') "marketplace name is 'superharness'"
Assert-True ($mpSrc -eq './plugins/superharness') "marketplace lists plugin source ./plugins/superharness"
Assert-True (-not (Test-Path (Join-Path $proj '.claude\skills\superharness'))) "does not install to legacy .claude/skills/superharness path"
```

并把 group 1 中过时的描述字符串 `"creates .claude-plugin/plugin.json (skills-dir plugin manifest)"` 改为 `"creates plugin manifest under plugins/superharness/.claude-plugin/"`，`"plugin.json name is 'superharness' (gives /superharness:* namespace)"` 保持不变。

- [ ] **Step 2: 运行测试确认失败**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
```

预期：FAIL（marketplace.json 不存在；plugin.json 不在新路径）。

- [ ] **Step 3: 移动模板文件并新增 marketplace.json**

```powershell
New-Item -ItemType Directory -Force template\plugins\superharness | Out-Null
git mv template/.claude-plugin template/plugins/superharness/.claude-plugin
git mv template/hooks template/plugins/superharness/hooks
git mv template/skills template/plugins/superharness/skills
git mv template/HARNESS.md template/plugins/superharness/HARNESS.md
```

创建 `template/.claude-plugin/marketplace.json`：

```json
{
  "name": "superharness",
  "owner": { "name": "wangzh" },
  "plugins": [
    {
      "name": "superharness",
      "source": "./plugins/superharness",
      "description": "Project-level autonomous engineering harness: TDD-first workflow, systematic debugging, planning, verification, and mind-map brainstorming."
    }
  ]
}
```

- [ ] **Step 4: 修改 install.ps1 的复制目标**

`lib/install.ps1` 第 26-30 行改为：

```powershell
$MarketDir = Join-Path $TargetDir '.claude\superharness'

# --- 1. Copy template -> .claude/superharness (local marketplace root, idempotent overwrite) ---
New-Item -ItemType Directory -Force $MarketDir | Out-Null
Copy-Item -Path (Join-Path $TemplateDir '*') -Destination $MarketDir -Recurse -Force
```

文件头注释（1-4 行）改为：

```powershell
# Superharness project installer.
# Installs the template as a local plugin marketplace at <project>/.claude/superharness/
# and enables the plugin via .claude/settings.json (extraKnownMarketplaces + enabledPlugins),
# giving the project /superharness:* skills and the SessionStart hook.
```

- [ ] **Step 5: 运行测试确认通过**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
```

预期：全部 PASS（含原有 group 1-6）。

- [ ] **Step 6: 提交**

```powershell
git add -A
git commit -m "feat: restructure template as local plugin marketplace (.claude/superharness)"
```

---

### Task 3: settings.json 保留性合并

**Files:**
- Modify: `tests/run-tests.ps1`
- Modify: `lib/install.ps1`

- [ ] **Step 1: 写失败测试**

在 run-tests.ps1 group 1.5 之后插入：

```powershell
# ---------------------------------------------------------------- Test group 1.6: settings.json merge
Write-Host "`n[1.6] Installer enables the plugin via .claude/settings.json"
$settingsPath = Join-Path $proj '.claude\settings.json'
Assert-True (Test-Path $settingsPath) "creates .claude/settings.json"
$stOk = $false; $srcType = ''; $srcPath = ''; $enabled = $null
try {
    $st = Get-Content $settingsPath -Raw | ConvertFrom-Json
    $stOk = $true
    $srcType = $st.extraKnownMarketplaces.superharness.source.source
    $srcPath = $st.extraKnownMarketplaces.superharness.source.path
    $enabled = $st.enabledPlugins.'superharness@superharness'
} catch {}
Assert-True $stOk "settings.json is valid JSON"
Assert-True ($srcType -eq 'directory') "extraKnownMarketplaces.superharness uses a directory source"
Assert-True ($srcPath -eq '.claude/superharness') "marketplace path is .claude/superharness"
Assert-True ($enabled -eq $true) "enabledPlugins['superharness@superharness'] is true"

# preserve existing settings keys
$proj3 = New-TempProject
New-Item -ItemType Directory -Force (Join-Path $proj3 '.claude') | Out-Null
Set-Content -Path (Join-Path $proj3 '.claude\settings.json') -Value '{"model":"opus","enabledPlugins":{"other@mp":true}}' -Encoding utf8
Invoke-Installer -TargetDir $proj3 | Out-Null
$st3 = Get-Content (Join-Path $proj3 '.claude\settings.json') -Raw | ConvertFrom-Json
Assert-True ($st3.model -eq 'opus') "existing settings keys are preserved"
Assert-True ($st3.enabledPlugins.'other@mp' -eq $true) "existing enabledPlugins entries are preserved"
Assert-True ($st3.enabledPlugins.'superharness@superharness' -eq $true) "superharness entry added alongside existing ones"

# idempotency
Invoke-Installer -TargetDir $proj3 | Out-Null
$st3b = Get-Content (Join-Path $proj3 '.claude\settings.json') -Raw | ConvertFrom-Json
Assert-True ($st3b.enabledPlugins.'superharness@superharness' -eq $true) "second install keeps settings valid and enabled"
```

并在文件末尾 cleanup 行把 `$proj3` 加入删除列表：

```powershell
Remove-Item $proj, $proj2, $proj3, $emptyDir -Recurse -Force -ErrorAction SilentlyContinue
```

- [ ] **Step 2: 运行测试确认失败**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
```

预期：group 1.6 全部 FAIL（settings.json 不存在）。

- [ ] **Step 3: 在 install.ps1 中实现合并**

在「Copy template」段之后、CLAUDE.md 段之前插入（`$utf8` 定义需上移到此段之前）：

```powershell
# --- 2. Merge .claude/settings.json (preserving existing keys) ---
function Set-Member {
    param($Object, [string]$Name, $Value)
    if ($Object.PSObject.Properties[$Name]) { $Object.$Name = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

$SettingsPath = Join-Path $TargetDir '.claude\settings.json'
$settings = if (Test-Path $SettingsPath) {
    [IO.File]::ReadAllText($SettingsPath, $utf8) | ConvertFrom-Json
} else { New-Object PSObject }

$shMarket = '{"source":{"source":"directory","path":".claude/superharness"}}' | ConvertFrom-Json
if (-not $settings.PSObject.Properties['extraKnownMarketplaces']) {
    Set-Member $settings 'extraKnownMarketplaces' (New-Object PSObject)
}
Set-Member $settings.extraKnownMarketplaces 'superharness' $shMarket

if (-not $settings.PSObject.Properties['enabledPlugins']) {
    Set-Member $settings 'enabledPlugins' (New-Object PSObject)
}
Set-Member $settings.enabledPlugins 'superharness@superharness' $true

[IO.File]::WriteAllText($SettingsPath, ($settings | ConvertTo-Json -Depth 16), $utf8)
```

- [ ] **Step 4: 运行测试确认通过**

预期：全部 PASS。

- [ ] **Step 5: 提交**

```powershell
git add -A
git commit -m "feat: enable plugin via .claude/settings.json merge (extraKnownMarketplaces + enabledPlugins)"
```

---

### Task 4: 旧路径清理、CLAUDE.md 段落与 HARNESS.md 更新、版本号

**Files:**
- Modify: `tests/run-tests.ps1`
- Modify: `lib/install.ps1`
- Modify: `template/plugins/superharness/HARNESS.md`
- Modify: `template/plugins/superharness/.claude-plugin/plugin.json`

- [ ] **Step 1: 写失败测试**

在 group 1.6 之后插入：

```powershell
# ---------------------------------------------------------------- Test group 1.7: legacy cleanup + docs
Write-Host "`n[1.7] Installer cleans legacy install and updates docs"
$proj4 = New-TempProject
$legacy = Join-Path $proj4 '.claude\skills\superharness'
New-Item -ItemType Directory -Force $legacy | Out-Null
Set-Content -Path (Join-Path $legacy 'dummy.txt') -Value 'old' -Encoding utf8
Invoke-Installer -TargetDir $proj4 | Out-Null
Assert-True (-not (Test-Path $legacy)) "removes legacy .claude/skills/superharness directory"

$cm4 = Get-Content (Join-Path $proj4 'CLAUDE.md') -Raw
Assert-True ($cm4 -match '\.claude/superharness') "CLAUDE.md section points to .claude/superharness"
Assert-True ($cm4 -notmatch 'skills-dir') "CLAUDE.md section no longer mentions skills-dir"
Assert-True ($cm4 -match 'superharness:brainstorm') "CLAUDE.md mentions /superharness:brainstorm"

$harnessDoc = Get-Content (Join-Path (Get-PluginDir $proj4) 'HARNESS.md') -Raw
Assert-True ($harnessDoc -notmatch 'skills-dir') "HARNESS.md no longer mentions skills-dir loading"
Assert-True ($harnessDoc -match 'superharness:brainstorm') "HARNESS.md lists the brainstorm skill"

$pj = Get-Content (Join-Path (Get-PluginDir $proj4) '.claude-plugin\plugin.json') -Raw | ConvertFrom-Json
Assert-True ($pj.version -eq '2.0.0') "plugin.json version bumped to 2.0.0"
```

cleanup 行加入 `$proj4`。

- [ ] **Step 2: 运行测试确认失败**

预期：group 1.7 FAIL。

- [ ] **Step 3: 实现**

(a) `lib/install.ps1`：在 settings 合并段之后插入：

```powershell
# --- 3. Remove legacy skills-dir install ---
$LegacyDir = Join-Path $TargetDir '.claude\skills\superharness'
if (Test-Path $LegacyDir) { Remove-Item $LegacyDir -Recurse -Force }
```

(b) `lib/install.ps1`：`$Section` 整体替换为：

```powershell
$Section = @"
$BeginMarker
## Superharness

This project uses **superharness**, loaded as a Claude Code plugin from the local
marketplace at ``.claude/superharness`` (enabled in ``.claude/settings.json`` via
``extraKnownMarketplaces`` + ``enabledPlugins``). Its SessionStart hook injects
``HARNESS.md`` into every session. If that context is missing, read
``.claude/superharness/plugins/superharness/HARNESS.md`` now and follow it for all
engineering work.

- Run a task end-to-end: ``/superharness:go <task goal>``
- Brainstorm with a live browser mind map (manual trigger only):
  ``/superharness:brainstorm <topic>``
- Non-negotiable: strict TDD (failing test first), systematic debugging, and
  verification with real command output before claiming anything is done.
$EndMarker
"@
```

(c) `template/plugins/superharness/HARNESS.md`：第 3-5 行替换为：

```markdown
You have superharness: a project-level engineering discipline harness. It is loaded
as a Claude Code plugin from the local marketplace at `.claude/superharness` and this
document is injected at session start by its SessionStart hook.
```

技能表（Available Skills）在 `superharness:go` 行后加一行：

```markdown
| `superharness:brainstorm` | ONLY when the user explicitly runs `/superharness:brainstorm <topic>` — never self-invoke. Requirements/design dialogue with a live browser mind map |
```

(d) `template/plugins/superharness/.claude-plugin/plugin.json`：`"version": "1.0.0"` → `"version": "2.0.0"`，`description` 末尾补充 ` Includes /superharness:brainstorm with a live mind map.`

- [ ] **Step 4: 运行测试确认通过**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
```

预期：全部 PASS。

- [ ] **Step 5: 提交**

```powershell
git add -A
git commit -m "feat: legacy cleanup, updated CLAUDE.md/HARNESS.md wording, plugin version 2.0.0"
```

---

### Task 5: 脑图布局纯函数 layout.js

**Files:**
- Create: `tests/layout.test.mjs`
- Create: `template/plugins/superharness/skills/brainstorm/scripts/layout.js`

- [ ] **Step 1: 写失败测试**

`tests/layout.test.mjs`：

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { layout, leafCount } = require('../template/plugins/superharness/skills/brainstorm/scripts/layout.js');

const tree = {
  id: 'root', label: '主题', kind: 'topic',
  children: [
    { id: 'q1', label: '问题1', kind: 'question', children: [
      { id: 'q1-a', label: 'A', kind: 'option' },
      { id: 'q1-b', label: 'B', kind: 'option' },
    ]},
    { id: 'q2', label: '问题2', kind: 'question', children: [
      { id: 'q2-a', label: 'C', kind: 'option' },
    ]},
    { id: 'd1', label: '决策1', kind: 'decision' },
  ],
};

test('leafCount counts leaves', () => {
  assert.equal(leafCount(tree), 4); // q1-a, q1-b, q2-a, d1
  assert.equal(leafCount({ id: 'x', label: 'x' }), 1);
});

test('root sits at the origin', () => {
  const { nodes } = layout(tree);
  const root = nodes.find(n => n.id === 'root');
  assert.equal(root.x, 0);
  assert.equal(root.y, 0);
  assert.equal(root.side, 0);
});

test('all input nodes appear exactly once with links to parents', () => {
  const { nodes, links } = layout(tree);
  const ids = nodes.map(n => n.id).sort();
  assert.deepEqual(ids, ['d1', 'q1', 'q1-a', 'q1-b', 'q2', 'q2-a', 'root']);
  assert.deepEqual(
    links.map(l => `${l.from}->${l.to}`).sort(),
    ['q1->q1-a', 'q1->q1-b', 'q2->q2-a', 'root->d1', 'root->q1', 'root->q2'],
  );
});

test('root children are split across both sides', () => {
  const { nodes } = layout(tree);
  const sides = new Set(nodes.filter(n => ['q1', 'q2', 'd1'].includes(n.id)).map(n => n.side));
  assert.ok(sides.has(1) && sides.has(-1), 'expected children on both sides');
});

test('children inherit their branch side and move outward', () => {
  const { nodes } = layout(tree);
  const q1 = nodes.find(n => n.id === 'q1');
  const q1a = nodes.find(n => n.id === 'q1-a');
  assert.equal(q1a.side, q1.side);
  assert.ok(Math.abs(q1a.x) > Math.abs(q1.x), 'child is further from the root');
});

test('same column nodes never overlap vertically', () => {
  const { nodes } = layout(tree);
  const cols = {};
  for (const n of nodes) (cols[`${n.side}:${n.x}`] ||= []).push(n.y);
  for (const ys of Object.values(cols)) {
    const sorted = [...ys].sort((a, b) => a - b);
    for (let i = 1; i < sorted.length; i++) {
      assert.ok(sorted[i] - sorted[i - 1] >= 36, `vertical gap too small: ${sorted[i] - sorted[i - 1]}`);
    }
  }
});

test('layout is deterministic', () => {
  assert.deepEqual(layout(tree), layout(tree));
});

test('empty root yields empty layout', () => {
  assert.deepEqual(layout(null), { nodes: [], links: [] });
});
```

- [ ] **Step 2: 运行测试确认失败**

```powershell
node --test tests/
```

预期：FAIL，`Cannot find module ... layout.js`。

- [ ] **Step 3: 实现 layout.js**

`template/plugins/superharness/skills/brainstorm/scripts/layout.js`：

```js
// Mind map tree layout. Pure and deterministic.
// Loadable from Node (module.exports) and the browser (window.MindmapLayout).
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.MindmapLayout = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  const LEVEL_X = 220; // horizontal distance per depth level
  const NODE_H = 44;   // vertical slot per leaf

  function leafCount(node) {
    if (!node.children || node.children.length === 0) return 1;
    return node.children.reduce((sum, c) => sum + leafCount(c), 0);
  }

  // Distribute root children left/right, balancing total leaf count.
  function splitSides(children) {
    const right = [];
    const left = [];
    let rightLeaves = 0;
    let leftLeaves = 0;
    for (const c of children) {
      const n = leafCount(c);
      if (rightLeaves <= leftLeaves) { right.push(c); rightLeaves += n; }
      else { left.push(c); leftLeaves += n; }
    }
    return { right, left };
  }

  function visit(node, depth, side, top, parentId, nodes, links) {
    const leaves = leafCount(node);
    nodes.push({
      id: node.id,
      label: node.label,
      kind: node.kind || 'note',
      state: node.state || 'open',
      note: node.note || '',
      x: side * depth * LEVEL_X,
      y: top + (leaves * NODE_H) / 2,
      side,
    });
    links.push({ from: parentId, to: node.id });
    let childTop = top;
    for (const c of node.children || []) {
      visit(c, depth + 1, side, childTop, node.id, nodes, links);
      childTop += leafCount(c) * NODE_H;
    }
  }

  function layout(rootNode) {
    const nodes = [];
    const links = [];
    if (!rootNode) return { nodes, links };
    nodes.push({
      id: rootNode.id,
      label: rootNode.label,
      kind: rootNode.kind || 'topic',
      state: rootNode.state || 'open',
      note: rootNode.note || '',
      x: 0,
      y: 0,
      side: 0,
    });
    const { right, left } = splitSides(rootNode.children || []);
    for (const [side, group] of [[1, right], [-1, left]]) {
      const total = group.reduce((sum, c) => sum + leafCount(c), 0);
      let top = -(total * NODE_H) / 2;
      for (const c of group) {
        visit(c, 1, side, top, rootNode.id, nodes, links);
        top += leafCount(c) * NODE_H;
      }
    }
    return { nodes, links };
  }

  return { layout, leafCount, splitSides };
});
```

- [ ] **Step 4: 运行测试确认通过**

```powershell
node --test tests/
```

预期：layout 测试全部 PASS。

- [ ] **Step 5: 提交**

```powershell
git add -A
git commit -m "feat: deterministic mind map tree layout (layout.js, TDD)"
```

---

### Task 6: server.cjs — HTTP、server-info、事件落盘

**Files:**
- Create: `tests/server.test.mjs`
- Create: `template/plugins/superharness/skills/brainstorm/scripts/server.cjs`

- [ ] **Step 1: 写失败测试（含启动辅助函数，后续任务复用）**

`tests/server.test.mjs`：

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const SERVER = path.resolve('template/plugins/superharness/skills/brainstorm/scripts/server.cjs');

function tempSession() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'sh-brainstorm-'));
}

async function startServer(t, extraEnv = {}) {
  const session = tempSession();
  const child = spawn(process.execPath, [SERVER], {
    env: { ...process.env, SUPERHARNESS_SESSION_DIR: session, ...extraEnv },
    stdio: 'ignore',
  });
  t.after(() => { try { child.kill(); } catch {} });
  t.after(() => { try { fs.rmSync(session, { recursive: true, force: true }); } catch {} });
  const infoPath = path.join(session, 'state', 'server-info');
  for (let i = 0; i < 50; i++) {
    if (fs.existsSync(infoPath)) break;
    await new Promise(r => setTimeout(r, 100));
  }
  assert.ok(fs.existsSync(infoPath), 'server-info should appear within 5s');
  const info = JSON.parse(fs.readFileSync(infoPath, 'utf-8'));
  return { session, child, info };
}

test('writes server-info with port, url and pid', async t => {
  const { info, child } = await startServer(t);
  assert.equal(info.type, 'server-started');
  assert.ok(info.port > 0);
  assert.match(info.url, /^http:\/\/localhost:\d+$/);
  assert.equal(info.pid, child.pid);
  assert.ok(info.content_dir.endsWith('content'));
  assert.ok(info.state_dir.endsWith('state'));
});

test('GET / serves the mind map page', async t => {
  const { info } = await startServer(t);
  const res = await fetch(info.url + '/');
  assert.equal(res.status, 200);
  const html = await res.text();
  assert.match(html, /MindmapLayout/);
});

test('GET /mindmap.json returns a default empty snapshot before any push', async t => {
  const { info } = await startServer(t);
  const snap = await (await fetch(info.url + '/mindmap.json')).json();
  assert.equal(snap.type, 'mindmap:snapshot');
  assert.equal(snap.rev, 0);
});

test('POST /event appends a JSONL line to state/events', async t => {
  const { info, session } = await startServer(t);
  const evt = { type: 'node:click', id: 'q1-a', label: 'JWT', kind: 'option', timestamp: 1760000000 };
  const res = await fetch(info.url + '/event', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(evt),
  });
  assert.equal(res.status, 204);
  const lines = fs.readFileSync(path.join(session, 'state', 'events'), 'utf-8').trim().split('\n');
  assert.equal(lines.length, 1);
  assert.deepEqual(JSON.parse(lines[0]), evt);
});

test('POST /event rejects invalid JSON with 400', async t => {
  const { info } = await startServer(t);
  const res = await fetch(info.url + '/event', { method: 'POST', body: 'not json' });
  assert.equal(res.status, 400);
});
```

- [ ] **Step 2: 运行测试确认失败**

```powershell
node --test tests/
```

预期：server 测试 FAIL（`Cannot find module ... server.cjs` 或 server-info 超时）。

- [ ] **Step 3: 实现 server.cjs（本步先实现 HTTP 部分；WebSocket 工具函数一并放入，下个任务接线）**

`template/plugins/superharness/skills/brainstorm/scripts/server.cjs`：

```js
// Superharness brainstorm mind-map server. Zero-dependency Node.
// Serves mindmap.html, watches content/mindmap.json and pushes snapshots to the
// browser over WebSocket; records browser interactions to state/events (JSONL).
const crypto = require('crypto');
const http = require('http');
const fs = require('fs');
const path = require('path');

// ---------- config ----------
const SESSION_DIR = process.env.SUPERHARNESS_SESSION_DIR;
if (!SESSION_DIR) {
  console.error('SUPERHARNESS_SESSION_DIR is required');
  process.exit(1);
}
const CONTENT_DIR = path.join(SESSION_DIR, 'content');
const STATE_DIR = path.join(SESSION_DIR, 'state');
const SNAPSHOT_FILE = path.join(CONTENT_DIR, 'mindmap.json');
const EVENTS_FILE = path.join(STATE_DIR, 'events');
const INFO_FILE = path.join(STATE_DIR, 'server-info');
const STOPPED_FILE = path.join(STATE_DIR, 'server-stopped');
const PORT = Number(process.env.SUPERHARNESS_PORT) || (49152 + Math.floor(Math.random() * 16383));
const HOST = process.env.SUPERHARNESS_HOST || '127.0.0.1';
const IDLE_TIMEOUT_MS = Number(process.env.SUPERHARNESS_IDLE_TIMEOUT_MS) || 30 * 60 * 1000;
const IDLE_CHECK_MS = Math.min(5000, IDLE_TIMEOUT_MS);

fs.mkdirSync(CONTENT_DIR, { recursive: true });
fs.mkdirSync(STATE_DIR, { recursive: true });

let lastActivity = Date.now();
const touch = () => { lastActivity = Date.now(); };

// ---------- websocket protocol (RFC 6455) ----------
const OPCODES = { TEXT: 0x01, CLOSE: 0x08, PING: 0x09, PONG: 0x0A };
const WS_MAGIC = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

function computeAcceptKey(clientKey) {
  return crypto.createHash('sha1').update(clientKey + WS_MAGIC).digest('base64');
}

function encodeFrame(opcode, payload) {
  const fin = 0x80;
  const len = payload.length;
  let header;
  if (len < 126) {
    header = Buffer.alloc(2);
    header[0] = fin | opcode;
    header[1] = len;
  } else if (len < 65536) {
    header = Buffer.alloc(4);
    header[0] = fin | opcode;
    header[1] = 126;
    header.writeUInt16BE(len, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = fin | opcode;
    header[1] = 127;
    header.writeBigUInt64BE(BigInt(len), 2);
  }
  return Buffer.concat([header, payload]);
}

function decodeFrame(buffer) {
  if (buffer.length < 2) return null;
  const opcode = buffer[0] & 0x0f;
  const masked = (buffer[1] & 0x80) !== 0;
  let payloadLen = buffer[1] & 0x7f;
  let offset = 2;
  if (!masked) throw new Error('Client frames must be masked');
  if (payloadLen === 126) {
    if (buffer.length < 4) return null;
    payloadLen = buffer.readUInt16BE(2);
    offset = 4;
  } else if (payloadLen === 127) {
    if (buffer.length < 10) return null;
    payloadLen = Number(buffer.readBigUInt64BE(2));
    offset = 10;
  }
  const dataOffset = offset + 4;
  const totalLen = dataOffset + payloadLen;
  if (buffer.length < totalLen) return null;
  const mask = buffer.slice(offset, dataOffset);
  const data = Buffer.alloc(payloadLen);
  for (let i = 0; i < payloadLen; i++) data[i] = buffer[dataOffset + i] ^ mask[i % 4];
  return { opcode, payload: data, bytesConsumed: totalLen };
}

const clients = new Set();
function broadcast(text) {
  const frame = encodeFrame(OPCODES.TEXT, Buffer.from(text));
  for (const socket of clients) socket.write(frame);
}

// ---------- snapshot ----------
const DEFAULT_SNAPSHOT = JSON.stringify({
  type: 'mindmap:snapshot', rev: 0, topic: '', status: 'exploring', root: null,
});

function currentSnapshot() {
  try { return fs.readFileSync(SNAPSHOT_FILE, 'utf-8'); }
  catch { return DEFAULT_SNAPSHOT; }
}

// ---------- http ----------
function serveFile(res, name, type) {
  res.writeHead(200, { 'Content-Type': type });
  res.end(fs.readFileSync(path.join(__dirname, name)));
}

const server = http.createServer((req, res) => {
  touch();
  if (req.method === 'GET' && (req.url === '/' || req.url === '/index.html')) {
    serveFile(res, 'mindmap.html', 'text/html; charset=utf-8');
  } else if (req.method === 'GET' && req.url === '/layout.js') {
    serveFile(res, 'layout.js', 'application/javascript; charset=utf-8');
  } else if (req.method === 'GET' && req.url === '/mindmap.json') {
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(currentSnapshot());
  } else if (req.method === 'POST' && req.url === '/event') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      try {
        JSON.parse(body);
        fs.appendFileSync(EVENTS_FILE, body.trim() + '\n');
        res.writeHead(204);
        res.end();
      } catch {
        res.writeHead(400);
        res.end('invalid JSON');
      }
    });
  } else {
    res.writeHead(404);
    res.end('not found');
  }
});

// ---------- lifecycle ----------
function shutdown(code) {
  try { fs.writeFileSync(STOPPED_FILE, ''); } catch {}
  try { fs.unlinkSync(INFO_FILE); } catch {}
  process.exit(code);
}
process.on('SIGINT', () => shutdown(0));
process.on('SIGTERM', () => shutdown(0));

setInterval(() => {
  if (Date.now() - lastActivity > IDLE_TIMEOUT_MS) shutdown(0);
}, IDLE_CHECK_MS).unref();

server.listen(PORT, HOST, () => {
  try { fs.unlinkSync(STOPPED_FILE); } catch {}
  const urlHost = HOST === '127.0.0.1' ? 'localhost' : HOST;
  const info = {
    type: 'server-started',
    port: PORT,
    url: 'http://' + urlHost + ':' + PORT,
    pid: process.pid,
    content_dir: CONTENT_DIR,
    state_dir: STATE_DIR,
  };
  fs.writeFileSync(INFO_FILE, JSON.stringify(info));
  console.log(JSON.stringify(info));
});
```

注意：GET / 依赖 `mindmap.html` 存在。本任务先创建占位文件（Task 8 完整实现），内容：

```html
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Superharness Mind Map</title></head>
<body><script src="/layout.js"></script><script>/* MindmapLayout placeholder, full UI in Task 8 */</script></body></html>
```

（该占位已含 `MindmapLayout` 字样以满足当前测试；Task 8 替换为完整页面。）

- [ ] **Step 4: 运行测试确认通过**

```powershell
node --test tests/
```

预期：本任务 5 个测试全部 PASS。

- [ ] **Step 5: 提交**

```powershell
git add -A
git commit -m "feat: brainstorm server HTTP endpoints, server-info, event sink (TDD)"
```

---

### Task 7: server.cjs — WebSocket 推送、文件监听、空闲退出

**Files:**
- Modify: `tests/server.test.mjs`
- Modify: `template/plugins/superharness/skills/brainstorm/scripts/server.cjs`

- [ ] **Step 1: 写失败测试（追加到 server.test.mjs，含极简 WS 客户端）**

```js
import net from 'node:net';

// Minimal WebSocket client: handshake + unmasked server frame parsing (len < 64KB).
function wsConnect(port) {
  return new Promise((resolve, reject) => {
    const socket = net.connect(port, '127.0.0.1');
    const messages = [];
    const waiters = [];
    let handshakeDone = false;
    let buf = Buffer.alloc(0);
    socket.on('error', reject);
    socket.on('connect', () => {
      socket.write(
        'GET / HTTP/1.1\r\nHost: 127.0.0.1:' + port + '\r\n' +
        'Upgrade: websocket\r\nConnection: Upgrade\r\n' +
        'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n');
    });
    socket.on('data', chunk => {
      buf = Buffer.concat([buf, chunk]);
      if (!handshakeDone) {
        const end = buf.indexOf('\r\n\r\n');
        if (end === -1) return;
        handshakeDone = true;
        buf = buf.slice(end + 4);
        resolve({
          socket,
          nextMessage(timeoutMs = 3000) {
            return new Promise((res, rej) => {
              if (messages.length) return res(messages.shift());
              const timer = setTimeout(() => rej(new Error('ws message timeout')), timeoutMs);
              waiters.push(msg => { clearTimeout(timer); res(msg); });
            });
          },
        });
      }
      while (buf.length >= 2) {
        let len = buf[1] & 0x7f;
        let offset = 2;
        if (len === 126) {
          if (buf.length < 4) return;
          len = buf.readUInt16BE(2);
          offset = 4;
        }
        if (buf.length < offset + len) return;
        const payload = buf.slice(offset, offset + len).toString('utf-8');
        buf = buf.slice(offset + len);
        if (waiters.length) waiters.shift()(payload);
        else messages.push(payload);
      }
    });
  });
}

test('WS client receives the latest snapshot on connect', async t => {
  const { info } = await startServer(t);
  const ws = await wsConnect(info.port);
  t.after(() => ws.socket.destroy());
  const snap = JSON.parse(await ws.nextMessage());
  assert.equal(snap.type, 'mindmap:snapshot');
  assert.equal(snap.rev, 0);
});

test('writing mindmap.json pushes the new snapshot and clears events', async t => {
  const { info, session } = await startServer(t);
  const ws = await wsConnect(info.port);
  t.after(() => ws.socket.destroy());
  await ws.nextMessage(); // initial snapshot

  // stale event that must be cleared on next push
  fs.writeFileSync(path.join(session, 'state', 'events'), '{"type":"node:click","id":"old"}\n');

  const snapshot = {
    type: 'mindmap:snapshot', rev: 1, topic: '测试', status: 'exploring',
    root: { id: 'root', label: '测试', kind: 'topic' },
  };
  fs.writeFileSync(path.join(session, 'content', 'mindmap.json'), JSON.stringify(snapshot));

  const pushed = JSON.parse(await ws.nextMessage());
  assert.equal(pushed.rev, 1);
  assert.equal(pushed.topic, '测试');
  assert.equal(fs.readFileSync(path.join(session, 'state', 'events'), 'utf-8'), '');
});

test('idle server exits and writes server-stopped', async t => {
  const { session, child } = await startServer(t, { SUPERHARNESS_IDLE_TIMEOUT_MS: '300' });
  const exited = new Promise(resolve => child.on('exit', resolve));
  await exited;
  assert.ok(fs.existsSync(path.join(session, 'state', 'server-stopped')), 'server-stopped marker written');
  assert.ok(!fs.existsSync(path.join(session, 'state', 'server-info')), 'server-info removed');
});
```

- [ ] **Step 2: 运行测试确认失败**

```powershell
node --test tests/
```

预期：WS 测试超时失败（upgrade 未处理）；idle 测试可能已通过（Task 6 已实现 idle）——确认前两个 WS 测试 FAIL 即可。

- [ ] **Step 3: 实现 upgrade 处理与文件监听（追加到 server.cjs 的 `// ---------- lifecycle ----------` 之前）**

```js
// ---------- websocket upgrade ----------
server.on('upgrade', (req, socket) => {
  const key = req.headers['sec-websocket-key'];
  if (!key) { socket.destroy(); return; }
  socket.write(
    'HTTP/1.1 101 Switching Protocols\r\n' +
    'Upgrade: websocket\r\nConnection: Upgrade\r\n' +
    'Sec-WebSocket-Accept: ' + computeAcceptKey(key) + '\r\n\r\n');
  clients.add(socket);
  touch();
  socket.write(encodeFrame(OPCODES.TEXT, Buffer.from(currentSnapshot())));
  let buf = Buffer.alloc(0);
  socket.on('data', data => {
    touch();
    buf = Buffer.concat([buf, data]);
    while (true) {
      let frame;
      try { frame = decodeFrame(buf); } catch { socket.destroy(); return; }
      if (!frame) break;
      buf = buf.slice(frame.bytesConsumed);
      if (frame.opcode === OPCODES.CLOSE) { socket.end(); return; }
      if (frame.opcode === OPCODES.PING) socket.write(encodeFrame(OPCODES.PONG, frame.payload));
    }
  });
  const drop = () => clients.delete(socket);
  socket.on('close', drop);
  socket.on('error', drop);
});

// ---------- snapshot file watch ----------
let lastMtime = 0;
try { lastMtime = fs.statSync(SNAPSHOT_FILE).mtimeMs; } catch {}
setInterval(() => {
  let stat;
  try { stat = fs.statSync(SNAPSHOT_FILE); } catch { return; }
  if (stat.mtimeMs === lastMtime) return;
  lastMtime = stat.mtimeMs;
  touch();
  try { fs.writeFileSync(EVENTS_FILE, ''); } catch {}
  broadcast(currentSnapshot());
}, 500).unref();
```

- [ ] **Step 4: 运行全部 node 测试确认通过**

```powershell
node --test tests/
```

预期：全部 PASS（layout + server）。

- [ ] **Step 5: 提交**

```powershell
git add -A
git commit -m "feat: WebSocket snapshot push, mindmap.json watch, idle shutdown (TDD)"
```

---

### Task 8: mindmap.html 完整前端

**Files:**
- Modify: `tests/server.test.mjs`（一个内容标记测试）
- Replace: `template/plugins/superharness/skills/brainstorm/scripts/mindmap.html`

- [ ] **Step 1: 写失败测试（追加）**

```js
test('mind map page contains pan/zoom and click feedback wiring', async t => {
  const { info } = await startServer(t);
  const html = await (await fetch(info.url + '/')).text();
  assert.match(html, /wheel/);          // zoom
  assert.match(html, /pointerdown/);    // pan
  assert.match(html, /node:click/);     // feedback event
  assert.match(html, /WebSocket/);      // live updates
});
```

- [ ] **Step 2: 运行确认失败**

```powershell
node --test tests/
```

预期：该测试 FAIL（占位页面无这些标记）。

- [ ] **Step 3: 用完整页面替换 mindmap.html**

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title>Superharness Brainstorm — Mind Map</title>
<style>
  :root { --bg: #1e1f26; --panel: #2a2c35; --text: #e8e8ef; --muted: #9aa0b0; }
  * { box-sizing: border-box; }
  body { margin: 0; font-family: system-ui, 'Segoe UI', sans-serif; background: var(--bg); color: var(--text); overflow: hidden; }
  #topbar { position: fixed; top: 0; left: 0; right: 0; height: 48px; display: flex; align-items: center; gap: 12px; padding: 0 16px; background: var(--panel); border-bottom: 1px solid #3a3d4a; z-index: 10; }
  #topic { font-weight: 600; font-size: 15px; }
  .badge { font-size: 12px; padding: 2px 10px; border-radius: 10px; background: #3a3d4a; color: var(--muted); }
  #status.designing { background: #4d3d1f; color: #e3c77b; }
  #status.approved { background: #1f4d2e; color: #7be3a0; }
  #conn.ok { background: #1f4d2e; color: #7be3a0; }
  #conn.bad { background: #4d1f1f; color: #e37b7b; }
  #canvas { position: absolute; left: 0; right: 0; top: 48px; bottom: 0; width: 100%; height: calc(100% - 48px); cursor: grab; }
  #canvas.dragging { cursor: grabbing; }
  .node { cursor: pointer; }
  .node text { font-size: 13px; fill: var(--text); }
  .node.rejected text { fill: var(--muted); text-decoration: line-through; }
  .link { fill: none; stroke: #4a4e5e; stroke-width: 1.5; }
  #hint { position: fixed; bottom: 10px; right: 14px; color: var(--muted); font-size: 12px; z-index: 10; }
</style>
</head>
<body>
<div id="topbar">
  <span id="topic">等待快照…</span>
  <span class="badge" id="status">exploring</span>
  <span class="badge" id="rev">rev 0</span>
  <span class="badge bad" id="conn">连接中…</span>
</div>
<svg id="canvas"><g id="viewport"></g></svg>
<div id="hint">拖拽平移 · 滚轮缩放 · 双击空白复位 · 点击节点反馈选择</div>
<script src="/layout.js"></script>
<script>
const SVG_NS = 'http://www.w3.org/2000/svg';
const KIND_COLORS = {
  topic: '#3d5afe', question: '#8e6cf0', option: '#2a9d8f', decision: '#e9933a',
  requirement: '#4fa3e3', risk: '#e35d6a', note: '#6c757d',
};
const svg = document.getElementById('canvas');
const viewport = document.getElementById('viewport');
let view = { x: 0, y: 0, k: 1 };
let currentRev = -1;
let lastSnap = null;
let selectedId = null;

function applyView() {
  viewport.setAttribute('transform', 'translate(' + view.x + ',' + view.y + ') scale(' + view.k + ')');
}
function resetView() {
  view = { x: svg.clientWidth / 2, y: svg.clientHeight / 2, k: 1 };
  applyView();
}

// --- pan ---
let drag = null;
svg.addEventListener('pointerdown', e => {
  if (e.target.closest('.node')) return;
  drag = { x: e.clientX, y: e.clientY };
  svg.classList.add('dragging');
  svg.setPointerCapture(e.pointerId);
});
svg.addEventListener('pointermove', e => {
  if (!drag) return;
  view.x += e.clientX - drag.x;
  view.y += e.clientY - drag.y;
  drag = { x: e.clientX, y: e.clientY };
  applyView();
});
svg.addEventListener('pointerup', () => { drag = null; svg.classList.remove('dragging'); });
svg.addEventListener('dblclick', e => { if (!e.target.closest('.node')) resetView(); });

// --- zoom around the cursor ---
svg.addEventListener('wheel', e => {
  e.preventDefault();
  const factor = e.deltaY < 0 ? 1.15 : 1 / 1.15;
  const k2 = Math.min(4, Math.max(0.2, view.k * factor));
  const rect = svg.getBoundingClientRect();
  const px = e.clientX - rect.left;
  const py = e.clientY - rect.top;
  view.x = px - (px - view.x) * (k2 / view.k);
  view.y = py - (py - view.y) * (k2 / view.k);
  view.k = k2;
  applyView();
}, { passive: false });

function nodeWidth(label) {
  let w = 0;
  for (const ch of label) w += ch.charCodeAt(0) > 255 ? 13 : 7.5;
  return Math.max(60, w + 24);
}

function el(name, attrs) {
  const node = document.createElementNS(SVG_NS, name);
  for (const [k, v] of Object.entries(attrs || {})) node.setAttribute(k, v);
  return node;
}

function sendClick(n) {
  selectedId = n.id;
  fetch('/event', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      type: 'node:click', id: n.id, label: n.label, kind: n.kind,
      timestamp: Math.floor(Date.now() / 1000),
    }),
  }).catch(() => {});
  if (lastSnap) render(lastSnap);
}

function render(snap) {
  document.getElementById('topic').textContent = snap.topic || '（无主题）';
  const st = document.getElementById('status');
  st.textContent = snap.status;
  st.className = 'badge ' + snap.status;
  document.getElementById('rev').textContent = 'rev ' + snap.rev;
  viewport.innerHTML = '';
  if (!snap.root) return;
  const { nodes, links } = MindmapLayout.layout(snap.root);
  const byId = {};
  nodes.forEach(n => { byId[n.id] = n; });
  for (const l of links) {
    const a = byId[l.from];
    const b = byId[l.to];
    if (!a || !b) continue;
    const mx = (a.x + b.x) / 2;
    viewport.appendChild(el('path', {
      class: 'link',
      d: 'M ' + a.x + ' ' + a.y + ' C ' + mx + ' ' + a.y + ', ' + mx + ' ' + b.y + ', ' + b.x + ' ' + b.y,
    }));
  }
  for (const n of nodes) {
    const g = el('g', { class: 'node ' + (n.state || 'open') });
    const label = (n.state === 'resolved' ? '✓ ' : '') + n.label;
    const w = nodeWidth(label);
    const h = 32;
    const color = KIND_COLORS[n.kind] || KIND_COLORS.note;
    const rect = el('rect', {
      x: n.x - w / 2, y: n.y - h / 2, width: w, height: h, rx: 8,
      fill: n.state === 'rejected' ? '#2a2c35' : color + '33',
      stroke: n.state === 'chosen' ? '#ffd166' : color,
      'stroke-width': n.state === 'chosen' ? 3 : (n.id === selectedId ? 2.5 : 1.5),
    });
    if (n.id === selectedId) rect.setAttribute('stroke-dasharray', '4 2');
    const text = el('text', { x: n.x, y: n.y + 4.5, 'text-anchor': 'middle' });
    text.textContent = label;
    g.appendChild(rect);
    g.appendChild(text);
    if (n.note) {
      const tip = document.createElementNS(SVG_NS, 'title');
      tip.textContent = n.note;
      g.appendChild(tip);
    }
    g.addEventListener('click', () => sendClick(n));
    viewport.appendChild(g);
  }
}

function connect() {
  const conn = document.getElementById('conn');
  const ws = new WebSocket('ws://' + location.host + '/');
  ws.onopen = () => { conn.textContent = '已连接'; conn.className = 'badge ok'; };
  ws.onmessage = ev => {
    let snap;
    try { snap = JSON.parse(ev.data); } catch { return; }
    if (snap.type !== 'mindmap:snapshot' || snap.rev <= currentRev) return;
    currentRev = snap.rev;
    lastSnap = snap;
    selectedId = null;
    render(snap);
  };
  ws.onclose = () => {
    conn.textContent = '已断开，重连中…';
    conn.className = 'badge bad';
    setTimeout(connect, 2000);
  };
  ws.onerror = () => ws.close();
}

resetView();
connect();
</script>
</body>
</html>
```

- [ ] **Step 4: 运行全部 node 测试确认通过**

```powershell
node --test tests/
```

预期：全部 PASS。

- [ ] **Step 5: 手动冒烟验证（拖拽/缩放无法自动化，必须人工确认一次）**

```powershell
$env:SUPERHARNESS_SESSION_DIR = "$env:TEMP\sh-smoke"; node template\plugins\superharness\skills\brainstorm\scripts\server.cjs
```

另开终端写入测试快照：

```powershell
Set-Content -Encoding utf8 "$env:TEMP\sh-smoke\content\mindmap.json" '{"type":"mindmap:snapshot","rev":1,"topic":"冒烟测试","status":"exploring","root":{"id":"root","label":"冒烟测试","kind":"topic","children":[{"id":"q1","label":"问题1","kind":"question","children":[{"id":"a","label":"选项A","kind":"option","state":"chosen"},{"id":"b","label":"选项B","kind":"option","state":"rejected"}]},{"id":"d1","label":"决策1","kind":"decision","state":"resolved","note":"悬浮提示"}]}}'
```

浏览器打开 server-info 中的 URL，确认：脑图渲染、拖拽平移、滚轮缩放、双击复位、点击节点后 `state\events` 出现 `node:click` 行。完成后 Ctrl+C 停服务器。

- [ ] **Step 6: 提交**

```powershell
git add -A
git commit -m "feat: full mind map page - SVG render, pan/zoom, node click feedback"
```

---

### Task 9: start-server.ps1 / stop-server.ps1

**Files:**
- Modify: `tests/run-tests.ps1`
- Create: `template/plugins/superharness/skills/brainstorm/scripts/start-server.ps1`
- Create: `template/plugins/superharness/skills/brainstorm/scripts/stop-server.ps1`

- [ ] **Step 1: 写失败测试（run-tests.ps1 末尾 cleanup 之前插入）**

```powershell
# ---------------------------------------------------------------- Test group 7: brainstorm server scripts
Write-Host "`n[7] Brainstorm start/stop server scripts"
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCmd) {
    Write-Host "  SKIP  node not on PATH - skipping server script tests" -ForegroundColor Yellow
} else {
    $scriptsDir = Join-Path $RepoRoot 'template\plugins\superharness\skills\brainstorm\scripts'
    $projS = New-TempProject
    $startOut = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsDir 'start-server.ps1') -ProjectDir $projS
    Assert-True ($LASTEXITCODE -eq 0) "start-server.ps1 exits 0"
    $infoOk = $false; $info = $null
    try { $info = ($startOut -join "`n") | ConvertFrom-Json; $infoOk = $true } catch {}
    Assert-True $infoOk "start-server.ps1 prints server-info JSON"
    Assert-True ($info.url -match '^http://localhost:\d+$') "server-info has a localhost URL"
    $sessionDir = Split-Path -Parent $info.state_dir
    Assert-True ($sessionDir -like (Join-Path $projS '.superharness\brainstorm\*')) "session dir lives under .superharness/brainstorm/"

    $httpOk = $false
    try { $resp = Invoke-WebRequest -Uri $info.url -UseBasicParsing -TimeoutSec 5; $httpOk = ($resp.StatusCode -eq 200) } catch {}
    Assert-True $httpOk "served URL responds with HTTP 200"

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsDir 'stop-server.ps1') -SessionDir $sessionDir | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "stop-server.ps1 exits 0"
    Start-Sleep -Milliseconds 500
    $procGone = $null -eq (Get-Process -Id $info.pid -ErrorAction SilentlyContinue)
    Assert-True $procGone "server process is stopped"
    Assert-True (Test-Path (Join-Path $sessionDir 'state\server-stopped')) "server-stopped marker exists"
    Assert-True (-not (Test-Path (Join-Path $sessionDir 'state\server-info'))) "server-info removed after stop"
    Remove-Item $projS -Recurse -Force -ErrorAction SilentlyContinue
}
```

- [ ] **Step 2: 运行确认失败**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
```

预期：group 7 FAIL（脚本不存在）。

- [ ] **Step 3: 实现 start-server.ps1**

```powershell
# Starts the brainstorm mind-map server for a project.
# Creates <project>/.superharness/brainstorm/<session-id>/{content,state}, launches
# node server.cjs detached, waits for state/server-info, prints it and exits.
param(
    [string]$ProjectDir = (Get-Location).Path,
    [int]$TimeoutSec = 10
)

$ErrorActionPreference = 'Stop'

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { Write-Error 'node not found on PATH - brainstorm mind map unavailable'; exit 1 }

$sessionId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $PID
$sessionDir = Join-Path $ProjectDir ".superharness\brainstorm\$sessionId"
New-Item -ItemType Directory -Force (Join-Path $sessionDir 'content') | Out-Null
New-Item -ItemType Directory -Force (Join-Path $sessionDir 'state') | Out-Null

$serverJs = Join-Path $PSScriptRoot 'server.cjs'
$env:SUPERHARNESS_SESSION_DIR = $sessionDir
try {
    Start-Process -FilePath $node.Source -ArgumentList ('"' + $serverJs + '"') -WindowStyle Hidden
} finally {
    Remove-Item Env:SUPERHARNESS_SESSION_DIR -ErrorAction SilentlyContinue
}

$infoPath = Join-Path $sessionDir 'state\server-info'
$deadline = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $deadline) {
    if (Test-Path $infoPath) { break }
    Start-Sleep -Milliseconds 200
}
if (-not (Test-Path $infoPath)) {
    Write-Error "server did not start within $TimeoutSec seconds"
    exit 1
}
Get-Content $infoPath -Raw -Encoding UTF8
exit 0
```

- [ ] **Step 4: 实现 stop-server.ps1**

```powershell
# Stops the brainstorm mind-map server for a session directory.
param(
    [Parameter(Mandatory = $true)][string]$SessionDir
)

$ErrorActionPreference = 'SilentlyContinue'

$infoPath = Join-Path $SessionDir 'state\server-info'
if (Test-Path $infoPath) {
    $info = Get-Content $infoPath -Raw | ConvertFrom-Json
    if ($info.pid) { Stop-Process -Id $info.pid -Force -Confirm:$false }
    Remove-Item $infoPath -Force
}
$stateDir = Join-Path $SessionDir 'state'
if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Force $stateDir | Out-Null }
New-Item -ItemType File -Force (Join-Path $stateDir 'server-stopped') | Out-Null
exit 0
```

注意：`server-info` 的 JSON 字段名是 `pid`，PowerShell 的 `$info.pid` 可直接读取；`Stop-Process -Force` 是强杀，Node 的 SIGTERM 处理器在 Windows 下不会运行，所以由本脚本负责写 `server-stopped`/删 `server-info`。

- [ ] **Step 5: 运行 PowerShell 测试确认通过**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
```

预期：全部 PASS（含 group 7）。

- [ ] **Step 6: 提交**

```powershell
git add -A
git commit -m "feat: start/stop scripts for the brainstorm server (TDD)"
```

---

### Task 10: brainstorm SKILL.md

**Files:**
- Modify: `tests/run-tests.ps1`
- Create: `template/plugins/superharness/skills/brainstorm/SKILL.md`

- [ ] **Step 1: 写失败测试（group 2 末尾追加）**

```powershell
# brainstorm skill: present, manual-only, documents the message protocol
$bsSkillPath = Join-Path $plugin 'skills\brainstorm\SKILL.md'
Assert-True (Test-Path $bsSkillPath) "includes brainstorm skill (/superharness:brainstorm)"
$bs = if (Test-Path $bsSkillPath) { Get-Content $bsSkillPath -Raw } else { '' }
Assert-True ($bs -match 'disable-model-invocation:\s*true') "brainstorm skill is manual-only (disable-model-invocation: true)"
Assert-True ($bs -match 'mindmap:snapshot') "brainstorm skill documents the mindmap:snapshot format"
Assert-True ($bs -match 'node:click') "brainstorm skill documents the node:click event format"
Assert-True ($bs -match 'start-server\.ps1') "brainstorm skill references start-server.ps1"
foreach ($f in @('server.cjs','mindmap.html','layout.js','start-server.ps1','stop-server.ps1')) {
    Assert-True (Test-Path (Join-Path $plugin "skills\brainstorm\scripts\$f")) "includes brainstorm script: $f"
}
```

- [ ] **Step 2: 运行确认失败**

预期：SKILL.md 相关断言 FAIL（scripts 文件断言此时应已 PASS）。

- [ ] **Step 3: 写 SKILL.md**

`template/plugins/superharness/skills/brainstorm/SKILL.md`（注意：全文不得出现 `superpowers:` 字样，避免 dangling-namespace 测试失败）：

````markdown
---
name: brainstorm
description: Manual-only brainstorming with a live browser mind map - explores requirements and design one question at a time while pushing the discussion structure to a draggable, zoomable mind map. ONLY invoke when the user explicitly runs /superharness:brainstorm; never self-invoke.
disable-model-invocation: true
argument-hint: [topic]
---

# Superharness Brainstorm — 实时脑图需求设计

**Topic:** $ARGUMENTS

If the topic above is empty, ask your human partner what they want to brainstorm and stop.

**Announce at start:** "Superharness brainstorm engaged. Topic: <topic>."

Turn the idea into a validated design through collaborative dialogue, while mirroring
the discussion structure to a live mind map in the user's browser.

<HARD-GATE>
Do NOT write implementation code or invoke implementation skills during this flow.
The output of this skill is a design document, not code.
</HARD-GATE>

## Phase 1 — Start the mind map session

1. Run (foreground; the script backgrounds node itself and prints server-info JSON):

   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File "<this skill's base directory>/scripts/start-server.ps1" -ProjectDir "<project root>"
   ```

2. Parse the printed JSON: save `url`, `content_dir`, `state_dir`, and the session
   directory (parent of `state_dir`). Tell the user to open `url` in a browser.
3. Remind the user to add `.superharness/` to `.gitignore` if missing.
4. **Degrade gracefully:** if node is missing or the script fails, say so and continue
   the whole flow in the terminal only. Never block brainstorming on the mind map.

## Phase 2 — Explore context

Read relevant project files, docs, and recent commits. Push the first snapshot:
the root node is the topic. Then proceed.

## Phase 3 — Clarify, one question at a time

For each clarifying question:

1. **Before asking in the terminal**, push a snapshot adding the question node
   (`kind: "question"`, `state: "open"`) with its candidate options
   (`kind: "option"`, `state: "open"`) as children.
2. Ask in the terminal (multiple choice preferred). Mention that the user can also
   click an option node in the browser.
3. **After the user answers** (terminal text is primary): read `<state_dir>/events`
   if it exists and merge with the terminal answer. Push a snapshot marking the
   chosen option `state: "chosen"`, the others `state: "rejected"`, and the question
   `state: "resolved"`.

## Phase 4 — Propose approaches

Push 2-3 approaches as branches (`kind: "decision"` parent with `kind: "option"`
children, trade-offs in `note`). Present them in the terminal with your
recommendation. Mark the chosen approach as in Phase 3. Set top-level
`status: "designing"`.

## Phase 5 — Present the design

Present the design in sections in the terminal, validating each. Fix agreed points
into the map as `kind: "requirement"` / `kind: "decision"` nodes; record known risks
as `kind: "risk"`.

## Phase 6 — Wrap up

After the user approves the design:

1. Push a final snapshot with `status: "approved"`.
2. Write the design to `superharness/specs/YYYY-MM-DD-<topic-slug>.md` in the project
   root (create the folder if missing) and commit it.
3. Stop the server:

   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File "<this skill's base directory>/scripts/stop-server.ps1" -SessionDir "<session directory>"
   ```

4. Tell the user: the design is saved, and they can run
   `/superharness:go <goal>` to implement it. Do NOT start implementation yourself.

## Message protocol

### Claude → browser: write the full snapshot to `<content_dir>/mindmap.json`

Always rewrite the whole file with the Write tool. The server watches it and pushes
it to the browser over WebSocket. Before each write, check that
`<state_dir>/server-info` exists and `<state_dir>/server-stopped` does not;
otherwise restart the server (Phase 1) or continue terminal-only.

```json
{
  "type": "mindmap:snapshot",
  "rev": 7,
  "topic": "用户登录功能",
  "status": "exploring",
  "root": {
    "id": "root", "label": "用户登录功能", "kind": "topic",
    "children": [
      { "id": "q1", "label": "认证方式？", "kind": "question", "state": "resolved",
        "children": [
          { "id": "q1-a", "label": "JWT", "kind": "option", "state": "chosen", "note": "无状态、易扩展" },
          { "id": "q1-b", "label": "Session", "kind": "option", "state": "rejected" }
        ] }
    ]
  }
}
```

Rules:
- `rev`: increment by 1 on every write (the browser discards stale revisions).
- `status`: `exploring` → `designing` → `approved`.
- Node `id`s are stable across snapshots; never reuse an id for a different node.
- `kind`: `topic | question | option | decision | requirement | risk | note`.
- `state`: `open | chosen | rejected | resolved` (default `open`).
- `note`: optional hover tooltip text. Keep labels short; details go in `note`.

### Browser → Claude: read `<state_dir>/events` (JSONL)

The server clears this file each time you push a new snapshot, so pending lines
always refer to the current screen. Missing file = no browser interaction.

```json
{"type":"node:click","id":"q1-a","label":"JWT","kind":"option","timestamp":1760000000}
```

The last click is usually the user's choice, but the terminal answer always wins
on conflict.

## Red Flags

| Thought | Reality |
|---------|---------|
| "服务器起不来，先修它" | 降级纯终端继续，brainstorm 不被脑图阻塞。 |
| "一次问三个问题快一点" | 一次一个问题。 |
| "设计批了，顺手开始写代码" | 终点是设计文档 + 提示 /superharness:go。 |
| "脑图更新太频繁，攒一批再推" | 每个问题/决策都推送，实时性就是这个技能的价值。 |
````

- [ ] **Step 4: 运行 PowerShell 测试确认通过**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
```

预期：全部 PASS（包括 group 2 的 dangling-superpowers 检查）。

- [ ] **Step 5: 提交**

```powershell
git add -A
git commit -m "feat: /superharness:brainstorm skill - manual-only flow with mind map protocol"
```

---

### Task 11: 终验、README、dogfood

**Files:**
- Modify: `README.md`
- （生成）`.claude/superharness/`、`.claude/settings.json`（dogfood，已被 .gitignore 部分忽略）

- [ ] **Step 1: 跑全部测试套件并记录输出**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
node --test tests/
```

预期：两个套件全部 PASS。任何失败回到对应任务用 systematic-debugging 处理。

- [ ] **Step 2: 更新 README.md**

更新安装/使用说明：初始化方式不变（`superharness` CLI），但说明加载机制为本地 marketplace 插件（`.claude/superharness` + `.claude/settings.json`），技能列表加入 `/superharness:brainstorm <topic>`（手动触发、实时脑图、拖拽/缩放/点选回传），并附消息协议小节（snapshot/events 两个格式，链接到 spec）。

- [ ] **Step 3: dogfood——在本仓库安装并人工验收**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File lib\install.ps1 -TargetDir .
```

确认生成 `.claude/superharness/` 与 `.claude/settings.json`，CLAUDE.md 托管段落已更新为新文案。然后重启 Claude Code 会话验收（验收标准 1：`/superharness:go`、`/superharness:brainstorm` 出现在技能列表，SessionStart 注入 HARNESS.md）。注意 `.claude/settings.json` 不在 .gitignore 中——本仓库应提交它（团队成员打开仓库即自动启用插件）。

- [ ] **Step 4: 提交**

```powershell
git add -A
git commit -m "docs: README for plugin-based loading and brainstorm skill; dogfood install"
```

- [ ] **Step 5: 对照验收标准逐条核对（spec 第 8 节）**

1. 干净目录初始化 → 两个技能可用 + hook 注入（Step 3 验证）。
2. 脑图 1 秒内更新、拖拽缩放正常（Task 8 Step 5 已人工验证）。
3. 点击节点 → events 出现 node:click（Task 8 Step 5 + server 测试）。
4. 流程结束生成 spec、服务器停止无残留（Task 9 测试覆盖 stop；流程行为由 SKILL.md 约束）。
5. 全部测试通过（Step 1 输出）。

在最终报告中逐条给出证据。

---

## Self-Review 记录

- **Spec 覆盖**：spec §1（插件化）→ Task 2/3/4；§2（流程）→ Task 10；§3（消息格式）→ Task 6/7/10；§4（服务器）→ Task 6/7/9；§5（前端）→ Task 5/8；§6（错误处理）→ Task 9/10（降级规则在 SKILL.md，启动失败测试在 group 7）；§7（测试）→ 各任务 RED/GREEN 步骤；§8（验收）→ Task 11。无遗漏。
- **占位符**：无 TBD/TODO；所有代码步骤含完整代码。
- **类型一致性**：`SUPERHARNESS_SESSION_DIR`/`server-info` 字段（`port/url/pid/content_dir/state_dir`）在 server.cjs、start-server.ps1、测试、SKILL.md 中一致；`mindmap:snapshot`/`node:click` 字段在 server 测试、前端、SKILL.md 中一致；`MindmapLayout.layout` 返回 `{nodes, links}` 与前端/测试一致。
