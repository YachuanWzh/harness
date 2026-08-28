#!/usr/bin/env bash
# Superharness SessionStart hook (macOS / Linux). Counterpart of session-start.ps1.
# Reads HARNESS.md from the plugin root and injects it into the session as
# additionalContext, so Claude Code starts every session with the harness rules loaded.
# Always exits 0: a broken hook must never block a session.

plugin_root="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "$plugin_root" ]; then
    plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

harness_path="$plugin_root/HARNESS.md"
[ -f "$harness_path" ] || exit 0
[ -s "$harness_path" ] || exit 0

# The active tech-stack guidance (STACK.md lives at <marketplace root> = pluginRoot/../..).
stack_path="$(cd "$plugin_root/../.." 2>/dev/null && pwd)/STACK.md"
[ -f "$stack_path" ] || stack_path=""

emit_payload() {
    if command -v node >/dev/null 2>&1; then
        node -e '
            const fs = require("fs");
            const path = require("path");
            const [harnessPath, stackPath, workspace] = process.argv.slice(1);
            let ctx = "<EXTREMELY_IMPORTANT>\nYou have superharness. Follow it for all engineering work in this project.\n\n"
                + fs.readFileSync(harnessPath, "utf8") + "\n</EXTREMELY_IMPORTANT>";
            if (stackPath && fs.existsSync(stackPath)) {
                const s = fs.readFileSync(stackPath, "utf8");
                if (s.trim()) {
                    ctx += "\n\n<EXTREMELY_IMPORTANT>\nThis project targets a specific tech stack. Follow this guidance.\n\n" + s + "\n</EXTREMELY_IMPORTANT>";
                }
            }
            // One-line onboarding nudge when neither the generated doc nor the
            // analysis cache exists. Manual-only; never auto-analyze.
            if (workspace && fs.existsSync(workspace)
                && !fs.existsSync(path.join(workspace, "ONBOARDING.md"))
                && !fs.existsSync(path.join(workspace, ".claude", "superharness", "onboarding", "cache.json"))) {
                ctx += "\n\n<superharness-onboarding-hint>\nNo onboarding guide for this workspace yet. Run /onboarding (superharness:onboarding) to analyze the codebase, map module business relationships, and generate ONBOARDING.md plus an interactive module mind map. The agent decides when to run it - nothing is analyzed automatically.\n</superharness-onboarding-hint>";
            }
            process.stdout.write(JSON.stringify({
                hookSpecificOutput: { hookEventName: "SessionStart", additionalContext: ctx }
            }));
        ' "$harness_path" "$stack_path" "$PWD"
    elif command -v python3 >/dev/null 2>&1; then
        python3 - "$harness_path" "$stack_path" "$PWD" <<'PY'
import json, os, sys
harness_path, stack_path, workspace = sys.argv[1], sys.argv[2], sys.argv[3]
ctx = ("<EXTREMELY_IMPORTANT>\nYou have superharness. Follow it for all engineering work in this project.\n\n"
       + open(harness_path, encoding="utf-8").read() + "</EXTREMELY_IMPORTANT>")
if stack_path and os.path.isfile(stack_path):
    s = open(stack_path, encoding="utf-8").read()
    if s.strip():
        ctx += ("\n\n<EXTREMELY_IMPORTANT>\nThis project targets a specific tech stack. Follow this guidance.\n\n"
                + s + "\n</EXTREMELY_IMPORTANT>")
if workspace and os.path.isdir(workspace) \
        and not os.path.isfile(os.path.join(workspace, "ONBOARDING.md")) \
        and not os.path.isfile(os.path.join(workspace, ".claude", "superharness", "onboarding", "cache.json")):
    ctx += ("\n\n<superharness-onboarding-hint>\nNo onboarding guide for this workspace yet. "
            "Run /onboarding (superharness:onboarding) to analyze the codebase, map module business relationships, "
            "and generate ONBOARDING.md plus an interactive module mind map. "
            "The agent decides when to run it - nothing is analyzed automatically.\n</superharness-onboarding-hint>")
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": ctx}}), end="")
PY
    fi
}

# JSON escaping is handled by node/python; never emit malformed JSON.
emit_payload 2>/dev/null || true
exit 0
