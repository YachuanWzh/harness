#!/usr/bin/env bash
# Superharness project installer (macOS / Linux). Counterpart of lib\install.ps1.
# Detects project type automatically and installs superharness:
#   - Claude Code projects (CLAUDE.md / .claude)  -> local marketplace plugin
#   - flavor-code projects (FLAVOR.md / .flavor)   -> .flavor/plugins/superharness/
#   - Both present -> both installed
#
# Usage: bash install.sh [--target-dir <project root>] [--template=<type>] [--stack=<tech>]
#
# JSON editing of .claude/settings.json uses `node` when available; otherwise a
# marker-guarded text merge is applied (safe because we control the managed keys).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_DIR="$REPO_ROOT/template"
TARGET_DIR="$(pwd)"

[ -d "$TEMPLATE_DIR" ] || { echo "Template directory not found: $TEMPLATE_DIR" >&2; exit 1; }

# ---------- parse CLI args ----------
TEMPLATE=""
STACK=""
SAW_TEMPLATE=0
SAW_STACK=0

for a in "$@"; do
    case "$a" in
        --target-dir=*) TARGET_DIR="${a#--target-dir=}" ;;
        --target-dir)   TARGET_DIR="__NEXT__" ;;
        --template=*)   SAW_TEMPLATE=1; TEMPLATE="${a#--template=}"; TEMPLATE="$(printf '%s' "$TEMPLATE" | tr '[:upper:]' '[:lower:]')" ;;
        --template)     SAW_TEMPLATE=1 ;;
        --stack=*)      SAW_STACK=1; STACK="${a#--stack=}"; STACK="$(printf '%s' "$STACK" | tr '[:upper:]' '[:lower:]')" ;;
        --stack)        SAW_STACK=1 ;;
        *)
            if [ "$TARGET_DIR" = "__NEXT__" ]; then TARGET_DIR="$a"; fi
            ;;
    esac
done
# handle "--target-dir <value>" two-token form
if [ "$TARGET_DIR" = "__NEXT__" ]; then
    echo "Error: --target-dir requires a value." >&2; exit 1
fi

[ -d "$TARGET_DIR" ] || { echo "Target directory not found: $TARGET_DIR" >&2; exit 1; }

if [ "$SAW_TEMPLATE" = "1" ] && [ -z "$TEMPLATE" ]; then
    echo "Error: --template requires a value. Valid: frontend, backend, fullstack." >&2; exit 1
fi
if [ "$SAW_STACK" = "1" ] && [ -z "$TEMPLATE" ]; then
    echo "Error: --stack requires --template (stack is meaningless without a template)." >&2; exit 1
fi

# resolved stack-doc id, or empty when no --template given
STACK_DOC_ID=""
if [ -n "$TEMPLATE" ]; then
    case "$TEMPLATE" in
        frontend)
            [ -n "$STACK" ] || STACK="react"
            case "$STACK" in react|vue) ;; *) echo "Error: Invalid --stack '$STACK' for --template=frontend. Valid: react, vue." >&2; exit 1 ;; esac
            STACK_DOC_ID="frontend-$STACK" ;;
        backend)
            [ -n "$STACK" ] || STACK="python"
            case "$STACK" in python|java|node) ;; *) echo "Error: Invalid --stack '$STACK' for --template=backend. Valid: python, java, node." >&2; exit 1 ;; esac
            STACK_DOC_ID="backend-$STACK" ;;
        fullstack)
            if [ -n "$STACK" ]; then echo "Error: --stack is not allowed with --template=fullstack (fixed React+Python)." >&2; exit 1; fi
            STACK_DOC_ID="fullstack" ;;
        *)
            echo "Error: Unknown --template '$TEMPLATE'. Valid: frontend, backend, fullstack." >&2; exit 1 ;;
    esac
fi

# ---------- helpers ----------

# Replace (or append) a marker-delimited managed section in a markdown file.
# $1=file  $2=begin marker  $3=end marker  $4=full section text (incl. markers)
upsert_managed_section() {
    local file="$1" begin="$2" end="$3" section="$4"
    if [ -f "$file" ] && grep -qF "$begin" "$file"; then
        # drop everything from begin marker through end marker, then re-append section
        local tmp="$file.tmp.$$"
        awk -v b="$begin" -v e="$end" '
            $0 == b { skip = 1; next }
            skip && $0 == e { skip = 0; next }
            !skip { print }
        ' "$file" > "$tmp"
        # strip trailing blank lines, then append the new section
        printf '%s\n' "$(cat "$tmp")" > "$tmp"
        printf '\n%s\n' "$section" >> "$tmp"
        mv "$tmp" "$file"
    elif [ -f "$file" ]; then
        printf '%s\n\n%s\n' "$(cat "$file")" "$section" > "$file"
    else
        printf '%s\n' "$section" > "$file"
    fi
}

# Append a .gitignore entry (with a leading comment) when absent.
# $1=.gitignore path  $2=comment  $3=pattern
append_gitignore_entry() {
    local gi="$1" comment="$2" line="$3"
    if [ -f "$gi" ] && grep -qF "$line" "$gi"; then
        return 0
    fi
    if [ -f "$gi" ] && [ -s "$gi" ]; then
        # ensure the file ends with a newline before appending
        [ -z "$(tail -c 1 "$gi")" ] || printf '\n' >> "$gi"
    fi
    printf '%s\n%s\n' "$comment" "$line" >> "$gi"
}

# Merge superharness marketplace/plugin entries into .claude/settings.json.
# Uses node when available; otherwise falls back to text-level insertion.
merge_claude_settings() {
    local settings="$1"
    if command -v node >/dev/null 2>&1; then
        node - "$settings" <<'EOF'
const fs = require('fs');
const p = process.argv[2];
let s = {};
if (fs.existsSync(p)) {
    try { s = JSON.parse(fs.readFileSync(p, 'utf8')); } catch { s = {}; }
}
s.extraKnownMarketplaces = s.extraKnownMarketplaces || {};
s.extraKnownMarketplaces.superharness = { source: { source: 'directory', path: '.claude/superharness' } };
s.enabledPlugins = s.enabledPlugins || {};
s.enabledPlugins['superharness@superharness'] = true;
fs.writeFileSync(p, JSON.stringify(s, null, 2));
EOF
    else
        # Fallback: create/patch minimal settings without node.
        if [ ! -f "$settings" ]; then
            cat > "$settings" <<'EOF'
{
  "extraKnownMarketplaces": {
    "superharness": { "source": { "source": "directory", "path": ".claude/superharness" } }
  },
  "enabledPlugins": { "superharness@superharness": true }
}
EOF
        elif ! grep -q '"superharness@superharness"' "$settings"; then
            echo "WARNING: node not found and $settings already exists; please add" >&2
            echo "  extraKnownMarketplaces.superharness = {\"source\":{\"source\":\"directory\",\"path\":\".claude/superharness\"}}" >&2
            echo "  enabledPlugins[\"superharness@superharness\"] = true" >&2
            echo "manually to $settings." >&2
        fi
    fi
}

# ---------- 0. detect project type ----------

HAS_CLAUDE=0
HAS_FLAVOR=0
{ [ -f "$TARGET_DIR/CLAUDE.md" ] || [ -d "$TARGET_DIR/.claude" ]; } && HAS_CLAUDE=1
{ [ -f "$TARGET_DIR/FLAVOR.md" ] || [ -d "$TARGET_DIR/.flavor" ]; } && HAS_FLAVOR=1

# Backward compatible: if nothing detected, default to Claude Code
if [ "$HAS_CLAUDE" = "0" ] && [ "$HAS_FLAVOR" = "0" ]; then
    HAS_CLAUDE=1
fi

INSTALLED_ANYTHING=0

# ============================================================================
# 1. Install for Claude Code (CLAUDE.md / .claude)
# ============================================================================

if [ "$HAS_CLAUDE" = "1" ]; then
    echo "[Claude Code] Detected Claude Code project, installing superharness plugin..."

    MARKET_DIR="$TARGET_DIR/.claude/superharness"

    # --- 1a. Copy template -> .claude/superharness ---
    mkdir -p "$MARKET_DIR"
    cp -R "$TEMPLATE_DIR/." "$MARKET_DIR/"

    # --- 1b. Active stack guidance ---
    STACK_TARGET="$MARKET_DIR/STACK.md"
    if [ -n "$STACK_DOC_ID" ]; then
        STACK_SOURCE="$MARKET_DIR/plugins/superharness/stacks/$STACK_DOC_ID.md"
        [ -f "$STACK_SOURCE" ] || { echo "Stack guidance doc missing: $STACK_SOURCE" >&2; exit 1; }
        cp -f "$STACK_SOURCE" "$STACK_TARGET"
    else
        rm -f "$STACK_TARGET"
    fi

    # --- 1c. Merge .claude/settings.json ---
    mkdir -p "$TARGET_DIR/.claude"
    merge_claude_settings "$TARGET_DIR/.claude/settings.json"

    # --- 1d. Remove legacy skills-dir install ---
    rm -rf "$TARGET_DIR/.claude/skills/superharness"

    # --- 1e. Managed section in CLAUDE.md ---
    CLAUDE_SECTION='<!-- SUPERHARNESS:BEGIN -->
## Superharness

This project uses **superharness**, loaded as a Claude Code plugin from the local
marketplace at `.claude/superharness` (enabled in `.claude/settings.json` via
`extraKnownMarketplaces` + `enabledPlugins`). Its SessionStart hook injects
`HARNESS.md` into every session. If that context is missing, read
`.claude/superharness/plugins/superharness/HARNESS.md` now and follow it for all
engineering work.

- Run a task end-to-end: `/superharness:go <task goal>`
- Small focused change (lighter go, no worktree/plan-file/ralph overhead):
  `/superharness:light <task goal>`
- Brainstorm with a live browser mind map (manual trigger only):
  `/superharness:brainstorm <topic>`
- Non-negotiable: strict TDD (failing test first), systematic debugging, and
  verification with real command output before claiming anything is done.
<!-- SUPERHARNESS:END -->'

    upsert_managed_section "$TARGET_DIR/CLAUDE.md" \
        '<!-- SUPERHARNESS:BEGIN -->' '<!-- SUPERHARNESS:END -->' "$CLAUDE_SECTION"

    # --- 1f. .gitignore entries for Claude Code runtime state ---
    append_gitignore_entry "$TARGET_DIR/.gitignore" \
        '# superharness ralph runtime state (per-task tracking + retry)' \
        '.claude/superharness/ralph/'
    append_gitignore_entry "$TARGET_DIR/.gitignore" \
        '# superharness brainstorm mind-map session state (transient)' \
        '.claude/superharness/brainstorm/'

    echo "  Claude Code plugin installed to: $MARKET_DIR"
    INSTALLED_ANYTHING=1
fi

# ============================================================================
# 2. Install for flavor-code (FLAVOR.md / .flavor)
# ============================================================================

if [ "$HAS_FLAVOR" = "1" ]; then
    echo "[flavor-code] Detected flavor-code project, installing superharness plugin..."

    FLAVOR_PLUGIN_DIR="$TARGET_DIR/.flavor/plugins/superharness"
    FLAVOR_SKILLS_DEST="$FLAVOR_PLUGIN_DIR/skills"
    SKILLS_SOURCE="$TEMPLATE_DIR/plugins/superharness/skills"
    PLUGIN_META_SOURCE="$TEMPLATE_DIR/plugins/superharness/plugin"

    [ -d "$SKILLS_SOURCE" ] || { echo "Skills source directory not found: $SKILLS_SOURCE" >&2; exit 1; }

    # --- 2a. Create plugin directory, copy manifest + entry point ---
    mkdir -p "$FLAVOR_PLUGIN_DIR"
    cp -f "$PLUGIN_META_SOURCE/flavor-plugin.json" "$FLAVOR_PLUGIN_DIR/"
    cp -f "$PLUGIN_META_SOURCE/index.js" "$FLAVOR_PLUGIN_DIR/"

    # --- 2a'. Docs consumed by the plugin hooks (SessionStart injects HARNESS.md) ---
    cp -f "$TEMPLATE_DIR/plugins/superharness/HARNESS.md" "$FLAVOR_PLUGIN_DIR/"
    if [ -n "$STACK_DOC_ID" ]; then
        cp -f "$TEMPLATE_DIR/plugins/superharness/stacks/$STACK_DOC_ID.md" "$FLAVOR_PLUGIN_DIR/STACK.md"
    else
        rm -f "$FLAVOR_PLUGIN_DIR/STACK.md"
    fi

    # --- 2b. Copy skills into .flavor/plugins/superharness/skills/ ---
    rm -rf "$FLAVOR_SKILLS_DEST"
    cp -R "$SKILLS_SOURCE" "$FLAVOR_SKILLS_DEST"

    COPIED_SKILLS=""
    for d in "$FLAVOR_SKILLS_DEST"/*/; do
        [ -d "$d" ] || continue
        name="$(basename "$d")"
        if [ -z "$COPIED_SKILLS" ]; then COPIED_SKILLS="\`$name\`"; else COPIED_SKILLS="$COPIED_SKILLS, \`$name\`"; fi
    done

    # --- 2c. Clean up legacy flat .flavor/skills/ install (pre-plugin) ---
    rm -rf "$TARGET_DIR/.flavor/skills"

    # --- 2d. Managed section in FLAVOR.md ---
    FLAVOR_SECTION="<!-- SUPERHARNESS:FLAVOR-BEGIN -->
## Superharness

This project has **superharness** installed as a flavor-code plugin under
\`.flavor/plugins/superharness/\`. It registers a skill root that provides
engineering-discipline skills for autonomous development, plus SessionStart /
UserPromptSubmit / Stop hooks that inject \`HARNESS.md\` into every session and
track \`/go\` tasks under \`.claude/superharness/ralph/\`.

Installed skills: $COPIED_SKILLS

Key capabilities:
- **go** -- Drive a task end-to-end under strict TDD + verification + code review discipline.
- **light** -- Lightweight mode for small focused tasks: TDD with exemptions, real-output verification, no worktree/plan-file/ralph overhead.
- **brainstorm** -- Explore requirements with a live browser mind map (manual trigger only).
- **test-driven-development** -- RED-GREEN-REFACTOR cycle. No production code without a failing test first.
- **systematic-debugging** -- Root-cause tracing, defense-in-depth, no guess-and-patch.
- **verification-before-completion** -- Run the full test suite and show real output before claiming done.
- **requesting-code-review** -- Dispatch a reviewer subagent over the diff.
- **writing-plans** -- Break down multi-step work into bite-sized TDD tasks.
- **using-git-worktrees** -- Isolate work in a disposable workspace.
- **subagent-driven-development** -- Execute multi-task plans with parallel subagents.

Usage in flavor-code: \`/<skill-name> <args>\`, e.g. \`/go refactor login module\` or \`/brainstorm payment plan\`.
<!-- SUPERHARNESS:FLAVOR-END -->"

    upsert_managed_section "$TARGET_DIR/FLAVOR.md" \
        '<!-- SUPERHARNESS:FLAVOR-BEGIN -->' '<!-- SUPERHARNESS:FLAVOR-END -->' "$FLAVOR_SECTION"

    # --- 2e. .gitignore entries for flavor-code runtime state ---
    append_gitignore_entry "$TARGET_DIR/.gitignore" \
        '# superharness brainstorm mind-map session state (transient)' \
        '.superharness/'
    append_gitignore_entry "$TARGET_DIR/.gitignore" \
        '# superharness ralph runtime state (per-task tracking + retry)' \
        '.claude/superharness/ralph/'

    echo "  flavor-code plugin installed to: $FLAVOR_PLUGIN_DIR"
    INSTALLED_ANYTHING=1
fi

# ============================================================================
# 3. Done
# ============================================================================

if [ "$INSTALLED_ANYTHING" = "0" ]; then
    echo "No project marker detected (CLAUDE.md/.claude or FLAVOR.md/.flavor). Nothing installed."
    echo "Run superharness in a project directory with CLAUDE.md, FLAVOR.md, .claude, or .flavor."
    exit 0
fi

echo ""

if [ "$HAS_CLAUDE" = "1" ]; then
    echo "-- Claude Code --"
    echo "  1. Start Claude Code in this project directory (trust workspace when asked)."
    echo "  2. Plugin loads automatically from local marketplace .claude/superharness."
    echo "  3. Run a task:  /superharness:go [task goal]"
    echo "     or a small focused change:  /superharness:light [task goal]"
    echo "     or brainstorm:  /superharness:brainstorm [topic]"
fi

if [ "$HAS_FLAVOR" = "1" ]; then
    [ "$HAS_CLAUDE" = "1" ] && echo ""
    echo "-- flavor-code --"
    echo "  1. Start flavor-code in this project directory:  flavor"
    echo "  2. Plugin auto-loads from .flavor/plugins/superharness/ (skillRoot registered at startup)."
    echo "  3. Run a task:  /go [task goal]"
    echo "     or a small focused change:  /light [task goal]"
    echo "     or brainstorm:  /brainstorm [topic]"
fi

echo ""
exit 0
