# Superharness `--template` Tech-Stack Flag Implementation Plan

> **For agentic workers:** Execute this plan task-by-task under the superharness:go workflow, Phase 2 (strict TDD per task). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `superharness --template=<frontend|backend|fullstack> [--stack=<...>]` that, on init, injects per-tech-stack engineering-discipline guidance into every Claude session via the existing SessionStart hook.

**Architecture:** Ship six stack guidance docs inside the plugin template (`stacks/*.md`). The installer parses `--template`/`--stack` from forwarded CLI args, validates them, resolves to one source doc, and copies it to `<proj>\.claude\superharness\STACK.md` (above the overwritten `plugins\` tree, so it survives re-installs). A plain re-install removes `STACK.md`. The SessionStart hook appends `STACK.md` to `additionalContext` after `HARNESS.md` when present.

**Tech Stack:** Windows PowerShell 5.1 (installer + hook), zero-dependency PowerShell assertion suite (`tests\run-tests.ps1`).

---

## File Structure

- Create: `template\plugins\superharness\stacks\frontend-react.md` — React stack guidance
- Create: `template\plugins\superharness\stacks\frontend-vue.md` — Vue stack guidance
- Create: `template\plugins\superharness\stacks\backend-python.md` — Python stack guidance
- Create: `template\plugins\superharness\stacks\backend-java.md` — Java stack guidance
- Create: `template\plugins\superharness\stacks\backend-node.md` — Node stack guidance
- Create: `template\plugins\superharness\stacks\fullstack.md` — React+Python combined + seam guidance
- Modify: `lib\install.ps1` — parse/validate `--template`/`--stack`, write/remove `STACK.md`
- Modify: `template\plugins\superharness\hooks\session-start.ps1` — inject `STACK.md` when present
- Modify: `tests\run-tests.ps1` — extend `Invoke-Installer`; add template/stack/hook test groups
- Modify: `README.md` — document new flags

**Note on the two trees:** `template\` is the source copied into projects; `lib\install.ps1` copies from it. The project's own `.claude\superharness\` is a dogfood copy — refresh it by re-running the installer at the end (Task 6). Always edit `template\`, never the `.claude\superharness\` copy.

**Resolution table (template + stack → source doc):**

| template | --stack | default | source doc (stacks/) |
|----------|---------|---------|----------------------|
| frontend | react/vue | react | frontend-react.md / frontend-vue.md |
| backend | python/java/node | python | backend-python.md / backend-java.md / backend-node.md |
| fullstack | (rejected) | — | fullstack.md |

---

## Task 1: Stack guidance source docs

**Files:**
- Create: `template\plugins\superharness\stacks\frontend-react.md`
- Create: `template\plugins\superharness\stacks\frontend-vue.md`
- Create: `template\plugins\superharness\stacks\backend-python.md`
- Create: `template\plugins\superharness\stacks\backend-java.md`
- Create: `template\plugins\superharness\stacks\backend-node.md`
- Create: `template\plugins\superharness\stacks\fullstack.md`
- Test: `tests\run-tests.ps1`

- [ ] **Step 1: Write the failing test**

Add this test group near the end of `tests\run-tests.ps1`, immediately before the `# ---- cleanup + summary` line (`Remove-Item $proj, $proj2, ...`):

```powershell
# ---------------------------------------------------------------- Test group 8: stack guidance source docs
Write-Host "`n[8] Template ships the six stack guidance docs"
$stacksDir = Join-Path $RepoRoot 'template\plugins\superharness\stacks'
$stackDocs = @{
    'frontend-react.md' = 'React'
    'frontend-vue.md'   = 'Vue'
    'backend-python.md' = 'pytest'
    'backend-java.md'   = 'JUnit'
    'backend-node.md'   = 'Jest'
    'fullstack.md'      = 'React'
}
foreach ($doc in $stackDocs.Keys) {
    $p = Join-Path $stacksDir $doc
    Assert-True (Test-Path $p) "template ships stacks/$doc"
    $body = if (Test-Path $p) { Get-Content $p -Raw } else { '' }
    Assert-True ($body -match $stackDocs[$doc]) "stacks/$doc mentions $($stackDocs[$doc])"
    Assert-True ($body -match 'TDD|test') "stacks/$doc covers testing discipline"
}
$fs = Join-Path $stacksDir 'fullstack.md'
$fsBody = if (Test-Path $fs) { Get-Content $fs -Raw } else { '' }
Assert-True ($fsBody -match 'Python') "stacks/fullstack.md mentions Python (combined stack)"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1`
Expected: FAIL — `template ships stacks/frontend-react.md` and the others fail (files do not exist).

- [ ] **Step 3: Create `frontend-react.md`**

```markdown
# Frontend stack: React

This project's frontend is **React**. Apply these conventions when working here.

## Layout
- `src/components/` reusable components (one component per file, PascalCase).
- `src/pages/` or `src/routes/` route-level components.
- `src/hooks/` custom hooks (`useX` naming). `src/lib/` framework-agnostic helpers.

## Testing (TDD — write the failing test first)
- Test runner: **Vitest**. Component tests: **@testing-library/react** + `@testing-library/jest-dom`.
- Run all: `npm run test`. Single file: `npx vitest run src/components/Foo.test.tsx`.
- Test behavior through the rendered DOM (roles, text, user events), not implementation details.
- User interaction via `@testing-library/user-event`, not raw `fireEvent` where avoidable.

## Standards
- TypeScript, strict mode. Function components + hooks only (no class components).
- Keep components small and pure; lift side effects into hooks. Co-locate `Foo.tsx` + `Foo.test.tsx`.
- Lint/format with ESLint + Prettier; run `npm run lint` before claiming done.
```

- [ ] **Step 4: Create `frontend-vue.md`**

```markdown
# Frontend stack: Vue

This project's frontend is **Vue 3**. Apply these conventions when working here.

## Layout
- `src/components/` reusable components (`<script setup>` SFCs, PascalCase filenames).
- `src/views/` route-level views. `src/composables/` composition functions (`useX`).
- `src/stores/` Pinia stores. `src/lib/` framework-agnostic helpers.

## Testing (TDD — write the failing test first)
- Test runner: **Vitest**. Component tests: **@vue/test-utils** + `@testing-library/jest-dom`.
- Run all: `npm run test`. Single file: `npx vitest run src/components/Foo.spec.ts`.
- Mount the component and assert on rendered output and emitted events, not internal refs.

## Standards
- TypeScript + `<script setup>`. Composition API only (no Options API for new code).
- Keep components small; extract logic into composables. Co-locate `Foo.vue` + `Foo.spec.ts`.
- Lint/format with ESLint + Prettier; run `npm run lint` before claiming done.
```

- [ ] **Step 5: Create `backend-python.md`**

```markdown
# Backend stack: Python

This project's backend is **Python**. Apply these conventions when working here.

## Layout
- `src/<package>/` application code. `tests/` mirrors the package tree.
- API layer (FastAPI routers / Django views) thin; business logic in service modules.

## Testing (TDD — write the failing test first)
- Test runner: **pytest**. Run all: `pytest`. Single test: `pytest tests/test_foo.py::test_bar -v`.
- Use fixtures for setup; parametrize for input variations. Assert on behavior/return values.
- HTTP layer: FastAPI `TestClient` / Django test client against real routes.

## Standards
- Type hints everywhere; check with `mypy`. Format with `black`, lint with `ruff`.
- Manage deps with the project's tool (`pyproject.toml` + uv/poetry, or `requirements.txt`).
- Run `ruff check` and the full `pytest` suite before claiming done.
```

- [ ] **Step 6: Create `backend-java.md`**

```markdown
# Backend stack: Java

This project's backend is **Java** (Spring ecosystem). Apply these conventions when working here.

## Layout
- `src/main/java/...` application code; `src/test/java/...` mirrors it.
- Layered: `controller` (thin) -> `service` (business logic) -> `repository` (data).

## Testing (TDD — write the failing test first)
- Test framework: **JUnit 5** + **AssertJ**; mock with **Mockito**.
- Run all: `mvn test` (or `./gradlew test`). Single: `mvn -Dtest=FooServiceTest test`.
- Web layer: `@WebMvcTest` + `MockMvc`. Assert on behavior and HTTP contracts.

## Standards
- Constructor injection (no field `@Autowired`). Keep controllers thin.
- Follow standard Java style; format with the project's plugin (Spotless/google-java-format).
- Run the full `mvn test` (or gradle) suite before claiming done.
```

- [ ] **Step 7: Create `backend-node.md`**

```markdown
# Backend stack: Node

This project's backend is **Node** (TypeScript). Apply these conventions when working here.

## Layout
- `src/` application code; routes thin (Express/Fastify), logic in `src/services/`.
- `src/**/*.test.ts` co-located or a `tests/` tree mirroring `src/`.

## Testing (TDD — write the failing test first)
- Test runner: **Jest** (ts-jest) or **Vitest** — follow whatever the repo already uses.
- Run all: `npm run test`. Single: `npx jest src/services/foo.test.ts` (or the vitest equivalent).
- HTTP layer: **supertest** against the real app instance. Assert on responses, not internals.

## Standards
- TypeScript, strict mode. `async/await` over raw promises; handle errors explicitly.
- Lint/format with ESLint + Prettier; run `npm run lint` and the full test suite before done.
```

- [ ] **Step 8: Create `fullstack.md`**

```markdown
# Fullstack: React + Python

This project is **fullstack**: a **React** frontend and a **Python** backend. Apply both stacks'
conventions (see the React and Python guidance above) plus the seam rules below.

## Layout
- `frontend/` React app; `backend/` Python app. Keep them independently testable.

## Frontend (React)
- Vitest + @testing-library/react. TypeScript strict. Small pure components, side effects in hooks.

## Backend (Python)
- pytest. Type hints + mypy. Thin API layer (FastAPI), logic in services. black + ruff.

## The seam (React <-> Python)
- **API contract is the contract.** Define request/response shapes once; mirror them as TS types
  on the frontend. Change them in lockstep and update tests on both sides in the same task.
- **CORS:** backend allows the dev frontend origin; do not disable CORS globally.
- **Dev proxy:** frontend dev server proxies `/api` to the backend to avoid origin mismatch.
- **End-to-end:** cover at least one real frontend->backend flow with an e2e/integration test.

## Discipline
- TDD on both sides. Run frontend (`npm run test`) and backend (`pytest`) suites before claiming done.
```

- [ ] **Step 9: Run test to verify it passes**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1`
Expected: PASS — all `[8]` assertions green; existing groups still pass.

- [ ] **Step 10: Commit**

```bash
git add template/plugins/superharness/stacks tests/run-tests.ps1
git commit -m "feat: stack guidance source docs for --template"
```

---

## Task 2: Installer parses, validates, and resolves `--template`/`--stack`

**Files:**
- Modify: `lib\install.ps1:8-10` (param block) and add a resolution section
- Test: `tests\run-tests.ps1`

- [ ] **Step 1: Write the failing test (extend `Invoke-Installer` + add error/validation group)**

First, replace the existing `Invoke-Installer` helper in `tests\run-tests.ps1` (currently lines ~31-35) with a version that forwards template/stack:

```powershell
function Invoke-Installer {
    param([string]$TargetDir, [string]$Template, [string]$Stack)
    $extra = @()
    if ($Template) { $extra += "--template=$Template" }
    if ($Stack)    { $extra += "--stack=$Stack" }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $InstallScript -TargetDir $TargetDir @extra | Out-Null
    return $LASTEXITCODE
}
```

Then add this group immediately before the `# ---- cleanup + summary` line:

```powershell
# ---------------------------------------------------------------- Test group 9: --template validation + resolution
Write-Host "`n[9] Installer resolves --template/--stack into STACK.md"
function Get-StackFile { param([string]$ProjectDir) Join-Path $ProjectDir '.claude\superharness\STACK.md' }

# 9a. frontend default -> React
$pf = New-TempProject
Invoke-Installer -TargetDir $pf -Template 'frontend' | Out-Null
$sf = Get-StackFile $pf
Assert-True (Test-Path $sf) "frontend default writes STACK.md"
$sfBody = if (Test-Path $sf) { Get-Content $sf -Raw } else { '' }
Assert-True ($sfBody -match 'React') "frontend default STACK.md is React"
Assert-True ($sfBody -notmatch 'This project''s frontend is \*\*Vue') "frontend default is not Vue"

# 9b. frontend --stack=vue
$pv = New-TempProject
Invoke-Installer -TargetDir $pv -Template 'frontend' -Stack 'vue' | Out-Null
Assert-True ((Get-Content (Get-StackFile $pv) -Raw) -match 'Vue') "frontend --stack=vue STACK.md is Vue"

# 9c. backend default -> Python
$pb = New-TempProject
Invoke-Installer -TargetDir $pb -Template 'backend' | Out-Null
Assert-True ((Get-Content (Get-StackFile $pb) -Raw) -match 'pytest') "backend default STACK.md is Python"

# 9d. backend --stack=java / node
$pj = New-TempProject
Invoke-Installer -TargetDir $pj -Template 'backend' -Stack 'java' | Out-Null
Assert-True ((Get-Content (Get-StackFile $pj) -Raw) -match 'JUnit') "backend --stack=java STACK.md is Java"
$pn = New-TempProject
Invoke-Installer -TargetDir $pn -Template 'backend' -Stack 'node' | Out-Null
Assert-True ((Get-Content (Get-StackFile $pn) -Raw) -match 'Jest|Node') "backend --stack=node STACK.md is Node"

# 9e. fullstack -> React + Python
$pfs = New-TempProject
Invoke-Installer -TargetDir $pfs -Template 'fullstack' | Out-Null
$fsB = Get-Content (Get-StackFile $pfs) -Raw
Assert-True ($fsB -match 'React' -and $fsB -match 'Python') "fullstack STACK.md mentions React and Python"
Assert-True ($fsB -match 'seam|API contract') "fullstack STACK.md covers the integration seam"

# 9f. errors -> non-zero exit
Assert-True ((Invoke-Installer -TargetDir (New-TempProject) -Template 'bogus') -ne 0) "invalid --template exits non-zero"
Assert-True ((Invoke-Installer -TargetDir (New-TempProject) -Template 'frontend' -Stack 'python') -ne 0) "invalid stack for template exits non-zero"
Assert-True ((Invoke-Installer -TargetDir (New-TempProject) -Template 'fullstack' -Stack 'react') -ne 0) "fullstack + --stack exits non-zero"

# 9g. backward compat: no --template -> no STACK.md
$pnone = New-TempProject
Invoke-Installer -TargetDir $pnone | Out-Null
Assert-True (-not (Test-Path (Get-StackFile $pnone))) "no --template leaves no STACK.md"

# 9h. plain re-install after a template removes STACK.md
Invoke-Installer -TargetDir $pf | Out-Null
Assert-True (-not (Test-Path (Get-StackFile $pf))) "plain re-install removes a previously written STACK.md"

Remove-Item $pf, $pv, $pb, $pj, $pn, $pfs, $pnone -Recurse -Force -ErrorAction SilentlyContinue
```

- [ ] **Step 2: Run test to verify it fails**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1`
Expected: FAIL — `frontend default writes STACK.md` etc. fail; error cases exit 0 (installer ignores unknown args today).

- [ ] **Step 3: Add params to `install.ps1`**

Replace the param block at `lib\install.ps1:8-10`:

```powershell
param(
    [string]$TargetDir = (Get-Location).Path,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)
```

- [ ] **Step 4: Add parsing/validation/resolution after `$TemplateDir` is set**

Insert this block in `lib\install.ps1` immediately after the existing target/template existence checks (after the `if (-not (Test-Path $TargetDir)) { ... }` block, before `$MarketDir = ...`):

```powershell
# --- Parse optional --template / --stack from forwarded CLI args ---
$Template = $null; $Stack = $null
foreach ($a in $Rest) {
    if ($a -match '^--template=(.+)$') { $Template = $Matches[1].ToLower() }
    elseif ($a -match '^--stack=(.+)$') { $Stack = $Matches[1].ToLower() }
}

# resolved stack-doc id, or $null when no --template given
$StackDocId = $null
if ($Template) {
    $valid = @{
        frontend  = @{ default = 'react';  stacks = @('react','vue') }
        backend   = @{ default = 'python'; stacks = @('python','java','node') }
        fullstack = @{ default = $null;    stacks = @() }
    }
    if (-not $valid.ContainsKey($Template)) {
        Write-Error "Unknown --template '$Template'. Valid: frontend, backend, fullstack."
        exit 1
    }
    if ($Template -eq 'fullstack') {
        if ($Stack) { Write-Error "--stack is not allowed with --template=fullstack (fixed React+Python)."; exit 1 }
        $StackDocId = 'fullstack'
    } else {
        if (-not $Stack) { $Stack = $valid[$Template].default }
        if ($valid[$Template].stacks -notcontains $Stack) {
            Write-Error "Invalid --stack '$Stack' for --template=$Template. Valid: $($valid[$Template].stacks -join ', ')."
            exit 1
        }
        $StackDocId = "$Template-$Stack"
    }
}
```

- [ ] **Step 5: Write or remove `STACK.md` after the template copy**

Insert this in `lib\install.ps1` immediately after the `Copy-Item ... -Recurse -Force` line that populates `$MarketDir` (the `# --- 1. Copy template ...` block):

```powershell
# --- 1b. Active stack guidance: write chosen STACK.md, or remove it for a plain install ---
$StackTarget = Join-Path $MarketDir 'STACK.md'
if ($StackDocId) {
    $StackSource = Join-Path $MarketDir "plugins\superharness\stacks\$StackDocId.md"
    if (-not (Test-Path $StackSource)) { Write-Error "Stack guidance doc missing: $StackSource"; exit 1 }
    Copy-Item -Path $StackSource -Destination $StackTarget -Force
} elseif (Test-Path $StackTarget) {
    Remove-Item $StackTarget -Force
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1`
Expected: PASS — all `[9]` assertions green; existing groups still pass.

- [ ] **Step 7: Commit**

```bash
git add lib/install.ps1 tests/run-tests.ps1
git commit -m "feat: parse/validate --template/--stack and write STACK.md"
```

---

## Task 3: SessionStart hook injects `STACK.md`

**Files:**
- Modify: `template\plugins\superharness\hooks\session-start.ps1:14-17`
- Test: `tests\run-tests.ps1`

- [ ] **Step 1: Write the failing test**

Add this group immediately before the `# ---- cleanup + summary` line:

```powershell
# ---------------------------------------------------------------- Test group 10: hook injects STACK.md
Write-Host "`n[10] session-start.ps1 appends STACK.md when present"
$ph = New-TempProject
Invoke-Installer -TargetDir $ph -Template 'frontend' -Stack 'vue' | Out-Null
$pluginH = Get-PluginDir $ph
$env:CLAUDE_PLUGIN_ROOT = $pluginH
$outH = (& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pluginH 'hooks\session-start.ps1')) -join "`n"
Remove-Item Env:CLAUDE_PLUGIN_ROOT -ErrorAction SilentlyContinue
$ctxH = ''
try { $ctxH = ($outH | ConvertFrom-Json).hookSpecificOutput.additionalContext } catch {}
Assert-True ($ctxH -match 'superharness') "hook still injects HARNESS.md"
Assert-True ($ctxH -match 'Vue') "hook appends STACK.md (Vue) when present"

# absent STACK.md -> unchanged (no stack marker)
$ph2 = New-TempProject
Invoke-Installer -TargetDir $ph2 | Out-Null
$pluginH2 = Get-PluginDir $ph2
$env:CLAUDE_PLUGIN_ROOT = $pluginH2
$outH2 = (& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pluginH2 'hooks\session-start.ps1')) -join "`n"
Remove-Item Env:CLAUDE_PLUGIN_ROOT -ErrorAction SilentlyContinue
$ctxH2 = ''
try { $ctxH2 = ($outH2 | ConvertFrom-Json).hookSpecificOutput.additionalContext } catch {}
Assert-True ($ctxH2 -notmatch 'Frontend stack:') "hook omits stack guidance when no STACK.md"

Remove-Item $ph, $ph2 -Recurse -Force -ErrorAction SilentlyContinue
```

- [ ] **Step 2: Run test to verify it fails**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1`
Expected: FAIL — `hook appends STACK.md (Vue) when present` fails (hook only reads HARNESS.md).

- [ ] **Step 3: Extend the hook to append STACK.md**

In `template\plugins\superharness\hooks\session-start.ps1`, replace the context-building line (currently line 17):

```powershell
$context = "<EXTREMELY_IMPORTANT>`nYou have superharness. Follow it for all engineering work in this project.`n`n$content`n</EXTREMELY_IMPORTANT>"
```

with:

```powershell
$context = "<EXTREMELY_IMPORTANT>`nYou have superharness. Follow it for all engineering work in this project.`n`n$content`n</EXTREMELY_IMPORTANT>"

# Append the active tech-stack guidance (STACK.md lives at <marketplace root> = pluginRoot\..\..).
$stackPath = Join-Path (Split-Path -Parent (Split-Path -Parent $pluginRoot)) 'STACK.md'
if (Test-Path $stackPath) {
    $stackContent = Get-Content $stackPath -Raw -Encoding UTF8
    if ($stackContent) {
        $context += "`n`n<EXTREMELY_IMPORTANT>`nThis project targets a specific tech stack. Follow this guidance.`n`n$stackContent`n</EXTREMELY_IMPORTANT>"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1`
Expected: PASS — all `[10]` assertions green; existing hook group `[5]` still passes.

- [ ] **Step 5: Commit**

```bash
git add template/plugins/superharness/hooks/session-start.ps1 tests/run-tests.ps1
git commit -m "feat: SessionStart hook injects active STACK.md guidance"
```

---

## Task 4: Document the new flags in README

**Files:**
- Modify: `README.md` (the "初始化项目" section near line 22-36)
- Test: manual read (docs only — no assertion)

- [ ] **Step 1: Add a flags subsection after the init产物 table**

Insert after the table that ends at `README.md` line ~36 (the row `| CLAUDE.md 中的 SUPERHARNESS 标记段 | ... |`):

```markdown

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
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: document --template/--stack flags in README"
```

---

## Task 5: Run the full suite + refresh the dogfood install

**Files:**
- Modify: project's own `.claude\superharness\` (via re-running the installer)

- [ ] **Step 1: Run the full PowerShell suite (verification)**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1`
Expected: `=== Results: <N> passed, 0 failed ===` (groups 1–10 all green).

- [ ] **Step 2: Refresh this repo's own dogfood install so its `.claude\superharness\` matches the new template**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File lib\install.ps1 -TargetDir .`
Expected: "Superharness installed into: ...\.claude\superharness" and exit 0. (No `--template` here — this repo is the harness itself, not a stack project; STACK.md must not appear.)

- [ ] **Step 3: Verify no STACK.md leaked into this repo**

Run: `powershell -NoProfile -Command "Test-Path .claude\superharness\STACK.md"`
Expected: `False`.

- [ ] **Step 4: Commit the refreshed dogfood copy**

```bash
git add .claude/superharness
git commit -m "chore: refresh dogfood install with stack docs + hook update"
```

---

## Self-Review

**Spec coverage:**
- Template = guidance (not scaffolding) → Task 1 docs are pure guidance. ✓
- `--template` frontend/backend/fullstack + `--stack` with defaults → Task 2 resolution table + validation. ✓
- Defaults React / Python; fullstack fixed React+Python rejecting `--stack` → Task 2 `$valid` map + error path. ✓
- Hook injection of STACK.md, survives re-install, plain re-install removes it → Task 2 step 5 + Task 3. ✓
- Backward compatibility (no `--template`) → Task 2 step 5 `elseif` + test 9g. ✓
- Docs → Task 4. ✓

**Placeholder scan:** No TBD/TODO; every code/test step shows full content. ✓

**Type/identifier consistency:** `$StackDocId`, `$StackTarget`, `$StackSource`, `Get-StackFile`, `stacks\<id>.md`, and `STACK.md` at marketplace root are used identically across Tasks 2 and 3, and match the hook's `pluginRoot\..\..` resolution. ✓
