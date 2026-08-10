#!/usr/bin/env bash
# Superharness project installer (macOS / Linux). Counterpart of lib\install.ps1.
# Detects project type automatically and installs superharness:
#   - Claude Code projects (CLAUDE.md / .claude)  -> local marketplace plugin
#   - flavor-code projects (FLAVOR.md / .flavor)   -> .flavor/plugins/superharness/
#   - Both present -> both installed
#
# Usage: bash install.sh [--target-dir <project root>] [--template=<type>] [--stack=<tech>]
#                        [--frontend=<tech>] [--backend=<tech>] [--uninstall]
#
# JSON editing of .claude/settings.json uses `node` when available; otherwise a
# marker-guarded text merge is applied (safe because we control the managed keys).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_DIR="$REPO_ROOT/template"
TARGET_DIR="$(pwd)"

# ---------- parse CLI args ----------
TEMPLATE=""
STACK=""
FRONTEND=""
BACKEND=""
UNINSTALL=0
SAW_TEMPLATE=0
SAW_STACK=0
SAW_FRONTEND=0
SAW_BACKEND=0

for a in "$@"; do
    case "$a" in
        --uninstall|-uninstall) UNINSTALL=1 ;;
        --target-dir=*) TARGET_DIR="${a#--target-dir=}" ;;
        --target-dir)   TARGET_DIR="__NEXT__" ;;
        --template=*)   SAW_TEMPLATE=1; TEMPLATE="${a#--template=}"; TEMPLATE="$(printf '%s' "$TEMPLATE" | tr '[:upper:]' '[:lower:]')" ;;
        --template)     SAW_TEMPLATE=1 ;;
        --stack=*)      SAW_STACK=1; STACK="${a#--stack=}"; STACK="$(printf '%s' "$STACK" | tr '[:upper:]' '[:lower:]')" ;;
        --stack)        SAW_STACK=1 ;;
        --frontend=*)   SAW_FRONTEND=1; FRONTEND="${a#--frontend=}"; FRONTEND="$(printf '%s' "$FRONTEND" | tr '[:upper:]' '[:lower:]')" ;;
        --frontend)     SAW_FRONTEND=1 ;;
        --backend=*)    SAW_BACKEND=1; BACKEND="${a#--backend=}"; BACKEND="$(printf '%s' "$BACKEND" | tr '[:upper:]' '[:lower:]')" ;;
        --backend)      SAW_BACKEND=1 ;;
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

# ============================================================================
# 0. Uninstall mode — revert everything the installer adds (and only that).
#    Placed before any --template validation so `--uninstall` always wins.
# ============================================================================
if [ "$UNINSTALL" = "1" ]; then
    # Remove a marker-delimited managed section from a markdown file.
    # $1=file  $2=begin marker  $3=end marker. Returns 0 when a section was removed.
    remove_managed_section() {
        local file="$1" begin="$2" end="$3"
        [ -f "$file" ] || return 1
        if ! grep -qF "$begin" "$file"; then return 1; fi
        local tmp="$file.tmp.$$"
        awk -v b="$begin" -v e="$end" '
            $0 == b { skip = 1; next }
            skip && $0 == e { skip = 0; next }
            !skip { print }
        ' "$file" > "$tmp"
        if cmp -s "$file" "$tmp"; then rm -f "$tmp"; return 1; fi
        local text
        text="$(cat "$tmp")"
        if [ -z "$text" ]; then
            # installer-created file: empty after removal -> drop it
            rm -f "$tmp" "$file"
        else
            printf '%s\n' "$text" > "$tmp"
            mv "$tmp" "$file"
        fi
        return 0
    }

    # Remove the managed '# superharness ...' comment + following pattern lines
    # from .gitignore. $1=.gitignore path, remaining args are the managed patterns.
    # Returns 0 when any line was removed.
    remove_gitignore_entries() {
        local gi="$1"; shift
        local patterns=("$@")
        [ -f "$gi" ] || return 1
        local tmp="$gi.tmp.$$"
        : > "$tmp"
        local line skip_next matched p
        skip_next=0
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in
                '# superharness '*)
                    skip_next=1
                    continue ;;
            esac
            if [ "$skip_next" = "1" ]; then
                skip_next=0
                matched=0
                for p in "${patterns[@]}"; do
                    if [ "$line" = "$p" ]; then matched=1; break; fi
                done
                [ "$matched" = "1" ] && continue
            fi
            printf '%s\n' "$line" >> "$tmp"
        done < "$gi"
        if cmp -s "$gi" "$tmp"; then rm -f "$tmp"; return 1; fi
        local text
        text="$(cat "$tmp")"
        if [ -z "$text" ]; then
            rm -f "$tmp" "$gi"
        else
            printf '%s\n' "$text" > "$tmp"
            mv "$tmp" "$gi"
        fi
        return 0
    }

    # Remove the superharness keys from .claude/settings.json. Uses node; a
    # malformed file is left untouched. Always returns 0 so `set -e` cannot abort.
    unmerge_claude_settings() {
        local settings="$1"
        if command -v node >/dev/null 2>&1; then
            node - "$settings" <<'EOF' || true
const fs = require('fs');
const p = process.argv[2];
let raw;
try { raw = fs.readFileSync(p, 'utf8'); } catch { process.exit(0); }
let s;
try { s = JSON.parse(raw); } catch { process.exit(0); }
let changed = false;
if (s.extraKnownMarketplaces && typeof s.extraKnownMarketplaces === 'object') {
    if ('superharness' in s.extraKnownMarketplaces) { delete s.extraKnownMarketplaces.superharness; changed = true; }
    if (Object.keys(s.extraKnownMarketplaces).length === 0) { delete s.extraKnownMarketplaces; }
}
if (s.enabledPlugins && typeof s.enabledPlugins === 'object') {
    if ('superharness@superharness' in s.enabledPlugins) { delete s.enabledPlugins['superharness@superharness']; changed = true; }
    if (Object.keys(s.enabledPlugins).length === 0) { delete s.enabledPlugins; }
}
if (!changed) process.exit(0);
if (Object.keys(s).length === 0) { fs.rmSync(p); } else { fs.writeFileSync(p, JSON.stringify(s, null, 2) + '\n'); }
EOF
        else
            echo "WARNING: node not found; please remove extraKnownMarketplaces.superharness and" >&2
            echo "  enabledPlugins[\"superharness@superharness\"] manually from $settings." >&2
        fi
        return 0
    }

    echo "Superharness uninstall..."
    UNINSTALLED_ANYTHING=0

    # --- Claude Code side ---
    if [ -d "$TARGET_DIR/.claude/superharness" ]; then
        rm -rf "$TARGET_DIR/.claude/superharness"
        echo "  Removed $TARGET_DIR/.claude/superharness"
        UNINSTALLED_ANYTHING=1
    fi
    if [ -d "$TARGET_DIR/.claude/skills/superharness" ]; then
        rm -rf "$TARGET_DIR/.claude/skills/superharness"
        echo "  Removed legacy $TARGET_DIR/.claude/skills/superharness"
        UNINSTALLED_ANYTHING=1
    fi
    if [ -f "$TARGET_DIR/.claude/settings.json" ]; then
        unmerge_claude_settings "$TARGET_DIR/.claude/settings.json"
    fi

    if remove_managed_section "$TARGET_DIR/CLAUDE.md" \
        '<!-- SUPERHARNESS:BEGIN -->' '<!-- SUPERHARNESS:END -->'; then
        UNINSTALLED_ANYTHING=1
    fi

    # --- flavor-code side ---
    if [ -d "$TARGET_DIR/.flavor/plugins/superharness" ]; then
        rm -rf "$TARGET_DIR/.flavor/plugins/superharness"
        echo "  Removed $TARGET_DIR/.flavor/plugins/superharness"
        UNINSTALLED_ANYTHING=1
    fi
    if remove_managed_section "$TARGET_DIR/FLAVOR.md" \
        '<!-- SUPERHARNESS:FLAVOR-BEGIN -->' '<!-- SUPERHARNESS:FLAVOR-END -->'; then
        UNINSTALLED_ANYTHING=1
    fi

    if [ -f "$TARGET_DIR/.gitignore" ]; then
        if remove_gitignore_entries "$TARGET_DIR/.gitignore" \
            '.claude/superharness/ralph/' '.claude/superharness/brainstorm/' \
            '.superharness/' '.flavor/superharness/ralph/'; then
            UNINSTALLED_ANYTHING=1
        fi
    fi

    if [ "$UNINSTALLED_ANYTHING" = "0" ]; then
        echo "No superharness install found in $TARGET_DIR. Nothing to uninstall."
    else
        echo "Superharness uninstalled from $TARGET_DIR. Your other project settings were left untouched."
    fi
    exit 0
fi

if [ "$UNINSTALL" != "1" ] && [ ! -d "$TEMPLATE_DIR" ]; then
    echo "Template directory not found: $TEMPLATE_DIR" >&2; exit 1
fi

if [ "$SAW_TEMPLATE" = "1" ] && [ -z "$TEMPLATE" ]; then
    echo "Error: --template requires a value. Valid: frontend, backend, fullstack." >&2; exit 1
fi
if [ "$SAW_STACK" = "1" ] && [ -z "$TEMPLATE" ]; then
    echo "Error: --stack requires --template (stack is meaningless without a template)." >&2; exit 1
fi
if { [ "$SAW_FRONTEND" = "1" ] || [ "$SAW_BACKEND" = "1" ]; } && [ "$TEMPLATE" != "fullstack" ]; then
    echo "Error: --frontend/--backend only apply to --template=fullstack." >&2; exit 1
fi

# resolved stack-doc id for single-stack templates, or empty when no --template given;
# fullstack instead resolves FULLSTACK_FRONT / FULLSTACK_BACK and concatenates docs.
STACK_DOC_ID=""
FULLSTACK_FRONT=""
FULLSTACK_BACK=""
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
            if [ -n "$STACK" ]; then echo "Error: --stack is not allowed with --template=fullstack; use --frontend=react|vue and --backend=python|java|node instead." >&2; exit 1; fi
            [ -n "$FRONTEND" ] || FRONTEND="react"
            [ -n "$BACKEND" ] || BACKEND="python"
            case "$FRONTEND" in react|vue) ;; *) echo "Error: Invalid --frontend '$FRONTEND'. Valid: react, vue." >&2; exit 1 ;; esac
            case "$BACKEND" in python|java|node) ;; *) echo "Error: Invalid --backend '$BACKEND'. Valid: python, java, node." >&2; exit 1 ;; esac
            FULLSTACK_FRONT="$FRONTEND"
            FULLSTACK_BACK="$BACKEND" ;;
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

# Write the active stack guidance. Single-stack templates copy one doc;
# fullstack concatenates frontend + backend + seam docs into STACK.md.
# $1=source root (contains plugins/superharness/stacks)  $2=target STACK.md path
write_stack_guidance() {
    local source_root="$1" target="$2"
    local stacks_dir="$source_root/plugins/superharness/stacks"
    if [ -n "$STACK_DOC_ID" ]; then
        local src="$stacks_dir/$STACK_DOC_ID.md"
        [ -f "$src" ] || { echo "Stack guidance doc missing: $src" >&2; exit 1; }
        cp -f "$src" "$target"
    elif [ -n "$FULLSTACK_FRONT" ]; then
        local front="$stacks_dir/frontend-$FULLSTACK_FRONT.md"
        local back="$stacks_dir/backend-$FULLSTACK_BACK.md"
        local seam="$stacks_dir/fullstack-seam.md"
        [ -f "$front" ] || { echo "Stack guidance doc missing: $front" >&2; exit 1; }
        [ -f "$back" ] || { echo "Stack guidance doc missing: $back" >&2; exit 1; }
        [ -f "$seam" ] || { echo "Stack guidance doc missing: $seam" >&2; exit 1; }
        { cat "$front"; printf '\n'; cat "$back"; printf '\n'; cat "$seam"; } > "$target"
    else
        rm -f "$target"
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
    write_stack_guidance "$MARKET_DIR" "$STACK_TARGET"

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
    write_stack_guidance "$TEMPLATE_DIR" "$FLAVOR_PLUGIN_DIR/STACK.md"

    # --- 2b. Copy skills into .flavor/plugins/superharness/skills/ ---
    rm -rf "$FLAVOR_SKILLS_DEST"
    cp -R "$SKILLS_SOURCE" "$FLAVOR_SKILLS_DEST"

    # --- 2b'. Ralph state library — skills (go) source it to drive task tracking;
    #          its install path under .flavor/ selects the .flavor state root ---
    mkdir -p "$FLAVOR_PLUGIN_DIR/scripts"
    cp -f "$TEMPLATE_DIR/plugins/superharness/scripts/ralph-lib.ps1" "$FLAVOR_PLUGIN_DIR/scripts/"
    cp -f "$TEMPLATE_DIR/plugins/superharness/scripts/ralph-lib.sh" "$FLAVOR_PLUGIN_DIR/scripts/"

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
track \`/go\` tasks under \`.flavor/superharness/ralph/\`.

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
        '.flavor/superharness/ralph/'

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
