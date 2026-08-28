---
name: onboarding
description: Use when the user runs /superharness:onboarding or /onboarding, or asks to onboard a newcomer / understand the codebase's business logic - deeply analyzes the workspace codebase (module responsibilities, cross-module business flows, data models) and produces ONBOARDING.md plus a live interactive mind map; supports incremental re-runs via cache
argument-hint: [optional focus: module name, flow, or "drill <node>"]
---

# Superharness Onboarding — deep business-logic analysis for newcomers

**Focus:** $ARGUMENTS

**Announce at start:** "Superharness onboarding engaged. Analyzing workspace: <goal or 'full overview'>."

Turn the current workspace into something a new team member can understand fast:
a committed `ONBOARDING.md` + per-topic docs, mirrored live to an interactive
mind map in the browser. The analysis is **layered** (overview → drill-down) and
**incremental** (cache keyed by git hash). Deep business-logic interpretation is
done by you (the agent); mechanical graph work is delegated to the astgraph
plugin when available, with a mandatory fallback when it is not.

**State root:** the superharness state root follows the host — `.claude/superharness/`
under Claude Code, `.flavor/superharness/` under flavor-code. Everywhere below,
`.claude/superharness/` stands for whichever state root applies (the onboarding
cache lives at `<state-root>/superharness/onboarding/`).

<HARD-GATE>
Never modify source files. This skill only reads code and writes: the
onboarding cache (state root, gitignored), ONBOARDING.md, docs/onboarding/*,
and mind-map snapshots. Do not refactor, fix, or "improve" the analyzed code.
</HARD-GATE>

## Phase 0 — Engine detection (never blocks on astgraph)

1. Determine the workspace root and state root.
2. Decide the analysis engine — use the deterministic helper:

   ```
   echo '{"astToolsAvailable":<bool>,"indexDbExists":<bool>}' | node <this skill's base directory>/scripts/onboarding-lib.cjs engine
   ```

   - `astToolsAvailable` = this session actually exposes `ast_search /
     ast_callers / ast_callees / ast_impact / ast_context` (flavor-code with the
     astgraph plugin; Claude Code hosts normally do NOT).
   - `indexDbExists` = `.flavor/astgraph/index.db` exists in the workspace.
3. Outcomes:
   - `{engine:"astgraph"}` → use astgraph retrieval throughout Phase B.
   - `{engine:"fallback", suggestAstInit:true}` → tools exist but no graph yet:
     **tell the user they can run `/ast init` for sharper analysis later, and
     continue right now with the fallback engine** — never wait for it.
   - `{engine:"fallback"}` → no astgraph at all (plugin not installed, Claude
     Code host, or non-TS/JS project): fallback is the plan, not a failure.
4. Fallback engine = Glob/Grep/Read + LSP (`LspFindRefs`, `LspHover`). Record
   the engine in the cache and stamp each generated doc header with
   `分析引擎: astgraph|fallback` so readers know the precision level.

## Phase 1 — Session + cache

1. Read `<state-root>/superharness/onboarding/cache.json` if present (may be empty/absent).
2. Get `git rev-parse HEAD` and the changed-file set:
   - with cache: `git diff --name-only <cache.gitHash> HEAD` plus
     `git status --porcelain` (dirty files);
   - no cache → full pass.
3. Plan the pass with the helper:

   ```
   echo '{"cache":<cache-or-null>,"headHash":"<head>","changedFiles":[...]}' | node <skill base>/scripts/onboarding-lib.cjs refresh
   ```

   `{full:true}` → module discovery for everything; otherwise only the
   `changed` module ids get (re-)analyzed in depth.

**Mind map session** (like brainstorm; degrade gracefully to terminal-only if node/scripts fail):

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<superharness skills dir>/brainstorm/scripts/start-server.ps1" -ProjectDir "<project root>"
```

Save `url`, `content_dir`, `state_dir` from the JSON it prints, tell the user to
open the URL, and remind them `<state-root>/superharness/brainstorm/` should be
gitignored. Push snapshots using the brainstorm message protocol
(`type:"mindmap:snapshot"`); node `kind` values additionally used here are
`module`, `flow`, `entity`.

## Phase 2 — Phase A: module overview (shallow, bounded cost)

1. **Discover modules**: directory/package structure (`package.json`, workspace
   configs, top-level dirs), entry points, and import/dependency edges — via
   `ast_search` when astgraph is live, else Grep for import/require statements.
   Cluster into modules by directory/package boundary (keep the project's own
   vocabulary for names).
2. **Rank by connectivity**; deep-analyze at most the top 8 modules this run
   (spec: control LLM cost on first pass). Mark the rest `待下钻` in the map.
3. For each analyzed module produce the cached row:
   `{ "summary": 一句话职责, "files": [ownership paths], "deps": [module ids], "doc": docs/onboarding/<id>.md }`
   and note **business relations** — who calls it in which scenario, what data
   crosses the boundary (read the code; do not guess).
4. Push the overview snapshot (root = project name, children = module nodes with
   one-line labels, dependency edges as `note` children on the callee), and
   write/update `ONBOARDING.md`:
   - 项目一句话 + 技术栈
   - Mermaid module map (`graph LR` with dependency arrows)
   - 模块速览表（职责 / 关键入口 file:line / 依赖）
   - 推荐上手路径（读代码顺序，3–5 步，每步给 file:line）
   - 核心业务流程索引（链接 docs/onboarding/*.md）
   - 头部署名：`分析引擎` + 缓存 git hash（短格式）

## Phase 3 — Phase B: drill-down (deep, demand-driven)

Two entry paths, same loop:
- **Terminal** (always available): user asks, e.g. "深入 install 模块" /
  "一次 go 任务从头到尾经过哪些模块" / `"/onboarding drill <node-or-flow>"`.
- **Browser clicks**: after each snapshot, poll `<state_dir>/events` (like
  brainstorm edit rounds). A `node:click` on a `module` / `flow` node = drill
  request for that node.

Per drill-down:
1. Pick 1–3 representative **business flows** through the target (entry → ... →
   persistence/output). For each hop, record `file:line`.
   - astgraph: `ast_callers` / `ast_callees` walk the chain; `ast_impact
     --hops 3` gives the cross-module blast radius; `ast_context` reads ranges.
   - fallback: `LspFindRefs` for call sites, Grep for dynamic/dispatch calls,
     Read for the semantics. Say explicitly in the doc when a link is inferred
     rather than graph-verified.
2. Identify **data flow**: the entities that cross module boundaries, where
   they're created, transformed, stored. Add `entity` nodes to the map.
3. Write `docs/onboarding/<topic>.md`: 场景说明 → 调用链（编号步骤 + file:line）
   → 模块协作图（Mermaid sequenceDiagram）→ 数据流转 → 改动影响面（ast_impact
   结果或 Grep 依据）→ 常见坑（来自真实代码观察）。
4. Push an updated snapshot (rev+1) with the new branch expanded, update cache,
   and refresh the `ONBOARDING.md` flow index.

Loop until the user stops asking or the map is fully explored. Keep each drill
focused; do not re-analyze cached unchanged modules.

## Phase 4 — Phase C: self-check + finish

1. **Stale sweep**:

   ```
   echo '{"cache":<cache>,"existingFiles":[...workspace file list...]}' | node <skill base>/scripts/onboarding-lib.cjs stale
   ```

   Mark returned entries `stale: true` in cache and grey them in the map;
   offer to re-analyze them (they'll appear as `changed` next refresh).
2. Save cache atomically with the new `gitHash` + engine + timestamp.
3. Stop the mind-map server:

   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File "<superharness skills dir>/brainstorm/scripts/stop-server.ps1" -SessionDir "<session directory>"
   ```

4. Report: which docs were created/updated, engine used, what was marked stale.
   Remind the user that `ONBOARDING.md` and `docs/onboarding/` are plain repo
   files they (or the team) decide whether to commit — this skill never commits.

## Incremental re-runs

Second `/onboarding` invocation: refresh-plan → only changed/deep-missing
modules re-analyzed, stale sweep runs, map is re-pushed from cache. If
`git` is unavailable, treat everything as changed (full pass) and note it.

## Red Flags

| Thought | Reality |
|---------|---------|
| "No astgraph, let me bail" | Fallback engine is a first-class path. Continue. |
| "Let me ask them to /ast init first" | Hint it, then proceed with fallback — never block. |
| "I'll analyze every module deeply now" | Top-8 by connectivity, rest on demand. Cost discipline. |
| "This call link looks obvious, skip verification" | Guessing creates docs that mislead newcomers. Cite file:line. |
| "I'll tidy this messy module while here" | Read-only. HARD-GATE: no source edits. |
