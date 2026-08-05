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
            const [harnessPath, stackPath] = process.argv.slice(1);
            let ctx = "<EXTREMELY_IMPORTANT>\nYou have superharness. Follow it for all engineering work in this project.\n\n"
                + fs.readFileSync(harnessPath, "utf8") + "\n</EXTREMELY_IMPORTANT>";
            if (stackPath && fs.existsSync(stackPath)) {
                const s = fs.readFileSync(stackPath, "utf8");
                if (s.trim()) {
                    ctx += "\n\n<EXTREMELY_IMPORTANT>\nThis project targets a specific tech stack. Follow this guidance.\n\n" + s + "\n</EXTREMELY_IMPORTANT>";
                }
            }
            process.stdout.write(JSON.stringify({
                hookSpecificOutput: { hookEventName: "SessionStart", additionalContext: ctx }
            }));
        ' "$harness_path" "$stack_path"
    elif command -v python3 >/dev/null 2>&1; then
        python3 - "$harness_path" "$stack_path" <<'PY'
import json, os, sys
harness_path, stack_path = sys.argv[1], sys.argv[2]
ctx = ("<EXTREMELY_IMPORTANT>\nYou have superharness. Follow it for all engineering work in this project.\n\n"
       + open(harness_path, encoding="utf-8").read() + "\n</EXTREMELY_IMPORTANT>")
if stack_path and os.path.isfile(stack_path):
    s = open(stack_path, encoding="utf-8").read()
    if s.strip():
        ctx += ("\n\n<EXTREMELY_IMPORTANT>\nThis project targets a specific tech stack. Follow this guidance.\n\n"
                + s + "\n</EXTREMELY_IMPORTANT>")
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": ctx}}), end="")
PY
    fi
}

# JSON escaping is handled by node/python; never emit malformed JSON.
emit_payload 2>/dev/null || true
exit 0
