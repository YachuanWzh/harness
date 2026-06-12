# 任务执行过程跟踪与重试（resume）设计

**日期:** 2026-06-12
**作用范围:** `superharness:go` 工作流
**状态:** 已批准，待实现

## 1. 目标

在 `/superharness:go` 执行过程中，把"每一轮需要用户介入的对话"持久化成一份**每任务一个、单行最小化的 JSON** 追踪文件；并提供一个 `/superharness:resume` 入口，能从追踪文件读回上下文、由人确认后**复现 → 定位根因 → 修改出问题的代码 → 验证**，把失败真正修好（而非盲目重跑）。

### 需求要点（来自用户）

1. 无论任务是否完成，**每一轮需要用户介入的对话都必须被记录**。
2. agent 回答可能过长：
   - **成功**时该轮只记录 `task completed`；
   - **失败**时只记录**失败的 test case 内容 + 用户 query**，外加时间戳等对重试有用的关键信息（不再记录整段对话原文 —— 这是对最初"记录全文"需求的明确收窄）。
3. **成功 / 失败主要看 test case**：该轮跑了测试且全绿 = 成功；跑了测试且有失败 = 失败；该轮没跑测试 = `in_progress`（另算）。
4. 范围包含 resume：从日志读回上下文，**由人确认后继续/重试，不自动重试**；重试不止重跑用例，还要**定位原因并修改出问题的代码**。

## 2. 架构 —— 混合式，hook 拥有"记录"这件事

记录的可靠性交给 Claude Code 的 hook（自动、不依赖 Claude 记忆）；成败的**语义判定**交给 `go` 工作流写的一个小标记文件。

- **`UserPromptSubmit` hook**：每次用户提交 prompt 时，把 `{ts, query}` 暂存为"待结算的一轮"。这是"每一轮都被记录"得以**无条件成立**的关键 —— 它不依赖 Claude 记得做任何事。
- **`Stop` hook**：当 Claude 把控制权交还用户时触发（即"一轮需要用户介入的对话"结束）。它合成该轮记录、追加进每任务追踪文件，然后消费（删除）临时标记。
- **outcome 标记（Claude 写）**：`go` 工作流在跑完测试后写一个结构化标记，`Stop` hook 据此**决定**保留为 success / failure / in_progress。标记缺失时该轮仍按 `in_progress` 记录 —— 标记只做**增强**，绝不充当门槛。

**作用范围限定**：仅当有 `go` 任务正在进行（存在任务态标记 `.task.json`）时才记录。普通对话 / 非 go 会话的 `Stop` 一律 no-op。

## 3. 组件与文件

新增 / 修改（源在 `template/plugins/superharness/`，由 `lib/install.ps1` 整树拷贝到目标项目的 `.claude/superharness/`）：

| 文件 | 角色 |
|---|---|
| `hooks/trace-lib.ps1` | 共享辅助：路径解析、最小化 JSON 读取/追加（单行写出）、stdin 解析、"永远 exit 0" 守卫 |
| `hooks/user-prompt-submit.ps1` | 写 `.state/<sid>.prompt.json = {ts, query}` |
| `hooks/stop.ps1` | 合成一轮、追加进 `<task>.json`、消费临时标记 |
| `hooks/hooks.json` | 新增 `UserPromptSubmit` 与 `Stop` 两个注册（保留既有 `SessionStart`） |
| `skills/go/SKILL.md` | Phase 1 写任务态标记；Phase 2/3 跑测试后写 outcome 标记；Phase 5 标记任务完成 |
| `skills/resume/SKILL.md` | 新增 `/superharness:resume [slug]`：复现 → 定位根因 → 改码 → 验证 |

### 文件布局（在**目标项目**里，路径取自 hook 传入的 `cwd`，与 `superharness/plans/` 对齐）

```
superharness/trace/
  2026-06-12-<slug>.json          # 交付物：每任务一个，单行最小化 JSON
  .state/                          # 临时态，gitignore
    <session_id>.prompt.json       # UserPromptSubmit 写：{ts, query}
    <session_id>.outcome.json      # Claude(go) 写：{outcome, summary, failing_tests, test_command, notes, task_status?}
    <session_id>.task.json         # go 任务开始时写：{task_id, slug, goal, started_at}
```

## 4. 单轮数据流

1. 用户提交 prompt → `UserPromptSubmit` 写 `.state/<sid>.prompt.json = {ts, query}`。
2. Claude 工作：
   - 任务开始时（go Phase 1）写 `.state/<sid>.task.json`；
   - 跑完测试 / 交还控制权前（go Phase 2/3）写 `.state/<sid>.outcome.json`。
3. Claude 交还控制权 → `Stop` hook：
   - 若**无** `.task.json` → no-op，exit 0；
   - 否则合并 `prompt.json` + `outcome.json`（缺 outcome 时默认 `outcome:"in_progress"`），分配轮号 `n`，按下面规则裁剪后追加进 `<task>.json` 的 `rounds[]`，更新顶层 `status` / `updated_at`；
   - 删除 `.prompt.json` 与 `.outcome.json`（消费，避免泄漏到下一轮）；
   - 若 outcome 里带 `task_status`（completed/failed/abandoned），写入顶层 `status` 并删除 `.task.json`（任务收尾）。

## 5. 记录结构与成败规则

整份文件**最小化写成单行**（用户选择的"单行最小化 JSON"）。逻辑结构如下：

```jsonc
{
  "task_id": "2026-06-12-task-trace",
  "goal": "实现任务执行过程跟踪与重试",
  "started_at": "2026-06-12T10:00:00+08:00",
  "updated_at": "2026-06-12T10:42:00+08:00",
  "status": "in_progress",            // in_progress | completed | failed | abandoned
  "rounds": [
    // in_progress：该轮没跑测试（如澄清提问）→ query + ts + 一句话摘要
    {"n":1,"ts":"…","query":"…","outcome":"in_progress","summary":"探索仓库、提出设计问题"},

    // failure：该轮跑了测试且 ≥1 失败 → 只记失败用例 + query + ts + 关键重试信息
    {"n":2,"ts":"…","query":"…","outcome":"failure","test_command":"npm test",
     "failing_tests":[{"name":"…","file":"…","message":"…"}],"notes":"…"},

    // success：该轮跑了测试且全绿 → 只记 task completed
    {"n":3,"ts":"…","query":"…","outcome":"success","summary":"task completed","test_command":"npm test"}
  ]
}
```

**成败判定（看 test case）：**

| 该轮情况 | outcome | 记录内容 |
|---|---|---|
| 跑了测试且全绿 | `success` | `summary:"task completed"` + `test_command` |
| 跑了测试且有失败 | `failure` | `failing_tests`(名称/文件/消息) + `query` + `ts` + `test_command` + `notes` |
| 该轮没跑测试 | `in_progress` | `query` + `ts` + 一句话 `summary` |
| outcome 标记缺失（Claude 没写） | `in_progress` | `query` + `ts`（hook 兜底，需求 1 无条件成立） |

字段口径（hook 与 marker 的分工）：
- `ts`、`query`、`n` —— 由 hook 无条件提供（来自 `UserPromptSubmit` 暂存 + Stop 时计数）。
- `outcome`、`summary`、`failing_tests`、`test_command`、`notes` —— 由 Claude 的 outcome 标记提供，缺失则降级。

## 6. Resume

`/superharness:resume [slug]`（仅手动触发）：

1. **读取**最新 `status != completed` 的追踪文件（或按 `slug`/路径指定的那个）；打印 goal、各轮历史、最后一次失败的 `failing_tests` 与 `test_command`。
2. 动手前**先与人确认**（不自动重试）。
3. 确认后进入完整的**复现 → 定位 → 改码 → 验证**闭环（不是盲目重跑）：
   - **复现** —— 重跑记录里的 `failing_tests` / `test_command`，确认仍按记录原因失败（RED）。
   - **定位** —— 调用 `superharness:systematic-debugging` 找出问题代码的**根因**（不允许猜测式打补丁）。
   - **改码** —— 走 TDD 修复：失败用例即现成 RED，用最小改动把它转 GREEN。
   - **验证** —— `superharness:verification-before-completion` 重跑**全量**测试；转绿则记一条新的 `success` 轮、更新顶层 `status`。
   - 仍红 → 这次新失败作为又一条 `failure` 轮记录（追踪文件累积完整的重试历史）。

## 7. 错误处理

每个 hook 沿用既有 `session-start.ps1` 的契约：`$ErrorActionPreference='SilentlyContinue'`，包 try，**永远 `exit 0`** —— 坏掉的追踪 hook 绝不能阻塞会话。stdin 为空 / 格式损坏 → exit 0，不写文件。`<task>.json` 的写入要避免半截文件（先写临时文件再原子替换）。

## 8. 测试（TDD，零依赖，写进 `tests/run-tests.ps1`）

全部失败用例先行：

**安装器层：**
- `hooks.json` 现在注册了 `UserPromptSubmit` 与 `Stop`（且仍有 `SessionStart`）。
- 新增脚本均被安装：`hooks/user-prompt-submit.ps1`、`hooks/stop.ps1`、`hooks/trace-lib.ps1`、`skills/resume/SKILL.md`。
- `go` skill 文档提到写 outcome 标记。

**行为层（向 hook 脚本管道喂 JSON）：**
- success 轮 → 该轮 `outcome:"success"`、`summary:"task completed"`。
- failure 轮 → 该轮含 `failing_tests`，且**不含**整段对话原文 blob。
- **outcome 标记缺失 → 该轮仍被记录为 `in_progress`**（需求 1）。
- 追踪文件是**单行**（断言内容里没有 `\n`）。
- 无 `.task.json` → `Stop` 为 no-op，不产生游离文件，exit 0。
- stdin 损坏/为空 → exit 0，不抛异常。
- `Stop` 之后临时标记 `.prompt.json` / `.outcome.json` 被消费删除。

## 9. 已定默认项

- 追踪 `.json` 文件**保留在项目里**（不 gitignore），以便 resume 读取、人工审阅；仅 `superharness/trace/.state/` 临时标记 gitignore。
- 本设计文档落在 `docs/superpowers/specs/2026-06-12-task-trace-and-resume-design.md`。

## 10. 不做（YAGNI）

- 不自动重试。
- 不做跨任务的全局累积日志（每任务一个文件）。
- 不 gzip（用单行最小化文本，便于排查）。
- 失败轮不落整段对话原文。
