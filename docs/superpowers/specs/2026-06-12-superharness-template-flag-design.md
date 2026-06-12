# Superharness `--template` 技术栈模板设计

日期：2026-06-12
状态：已批准，待实现

## 目标

为 superharness 初始化增加技术栈模板能力：

```
superharness --template=frontend [--stack=react|vue]
superharness --template=backend  [--stack=python|java|node]
superharness --template=fullstack
```

初始化时除了加载 superharness 插件/技能（现有行为），再为项目注入**对应技术栈的工程纪律指引**，
让 Claude 在该栈下按对应最佳实践工作。

## 关键决策（来自脑暴）

1. **"模板"= 工程纪律指引**，不是可运行的业务脚手架。不生成 package.json / 业务源码，
   而是面向 Claude 的栈约定（目录结构、测试框架与运行方式、代码规范、栈专属 TDD 注意点）。
2. **二级 `--stack` flag**，省略时用默认。
3. **默认栈**：前端 = React（`--stack=vue` 切换）；后端 = Python（`--stack=java|node` 切换）。
4. **fullstack 固定 = React + Python**，不接受 `--stack`。
5. **送达方式 = SessionStart 钩子注入 STACK.md**，与现有 HARNESS.md 注入机制一致，保证每会话加载。
6. 不带 `--template` 时维持现有行为（无栈指引），向后兼容。

## 合法组合与校验

| template | 合法 --stack | 默认 | 解析为 |
|----------|-------------|------|--------|
| frontend | react, vue | react | frontend-react / frontend-vue |
| backend | python, java, node | python | backend-python / backend-java / backend-node |
| fullstack | （不接受） | — | fullstack |

校验失败一律非零退出 + 明确错误信息：

- `template` 不在 `{frontend, backend, fullstack}` → 错误。
- `--stack` 不在该 template 的合法集合 → 错误。
- `fullstack` 同时给了 `--stack` → 错误。
- 未给 `--template`：合法，走现有路径，不写 STACK.md。

## 架构

完全沿用现有插件 / 本地 marketplace / SessionStart 钩子结构，仅新增一个标记文件 + 钩子扩展。

### 1. CLI 与参数解析

- `bin\superharness.cmd` 已用 `%*` 透传，无需改动（用户键入的 `--template=frontend --stack=vue`
  原样到达 `install.ps1`）。
- `install.ps1` 用 `[Parameter(ValueFromRemainingArguments)]` 捕获剩余参数，手动解析
  `--template=<v>` 与 `--stack=<v>`（精确匹配用户键入的 `--flag=value` 语法）。

### 2. 栈指引源文件（随模板下发，单一事实源）

`template\plugins\superharness\stacks\` 下：

- `frontend-react.md`
- `frontend-vue.md`
- `backend-python.md`
- `backend-java.md`
- `backend-node.md`
- `fullstack.md`

每份内容：简洁、真实的该栈工程指引——目录约定、**测试框架与运行命令**
（Vitest/RTL、pytest、JUnit/Maven、Jest 等）、代码规范、栈专属 TDD 注意点。
`fullstack.md` 额外覆盖 React↔Python 接缝：API 契约、CORS、开发代理、monorepo 布局、e2e。

### 3. 送达（钩子注入）

- 安装器把 `template` + `stack` 解析为一份源文档，复制到
  `<proj>\.claude\superharness\STACK.md`。该位置在被覆盖的 `plugins\` 树**之上**，
  重装时不会被 `Copy-Item template\* -Force` 删除/覆盖，得以存活。
- 不带 `--template` 的普通重装会**删除** STACK.md（可预测地复位）。
- `session-start.ps1` 扩展：若插件根的 `..\..\STACK.md` 存在，则在注入 HARNESS.md
  之后把它追加进 `additionalContext`。

### 4. 文档

- `README.md`：使用表 + 新 flag 说明。
- CLAUDE.md 托管段：补一句技术栈模板说明（可选，安装器维护）。

## 测试（先写，TDD）

在 `tests\run-tests.ps1` 新增测试组。`Invoke-Installer` 扩展为可透传 `--template`/`--stack`，
模拟真实 CLI 调用。

- 源文档：六份 `stacks\*.md` 均存在于 template。
- 组合 → STACK.md：
  - `--template=frontend`（默认）→ STACK.md 提到 React，不提 Vue。
  - `--template=frontend --stack=vue` → 提到 Vue。
  - `--template=backend`（默认）→ Python。
  - `--template=backend --stack=java` → Java。
  - `--template=backend --stack=node` → Node。
  - `--template=fullstack` → 同时提到 React 与 Python，且含集成/接缝内容。
- 错误：非法 template、该 template 下非法 stack、fullstack+`--stack` → 非零退出。
- 向后兼容：不带 `--template` → 不写 STACK.md；带模板后普通重装 → STACK.md 被删除。
- 钩子：STACK.md 存在时 `additionalContext` 含其内容；不存在时维持现有输出。

## 范围外（YAGNI）

- 不生成可运行业务脚手架文件。
- fullstack 不做栈可选（固定 React+Python）。
- 不做基于 package.json/pom.xml 的自动栈检测。
