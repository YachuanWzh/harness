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

1. Run (the script backgrounds node itself and prints server-info JSON before exiting):

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

Push 2-3 approaches as branches (a `kind: "decision"` parent with `kind: "option"`
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
