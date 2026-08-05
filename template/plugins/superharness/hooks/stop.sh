#!/usr/bin/env bash
# Stop hook (macOS / Linux). Counterpart of stop.ps1.
# When a go task is active (ralph state root: .claude/superharness/ralph under
# Claude Code, .flavor/superharness/ralph under flavor-code; .current-task present),
# append a 'round' heartbeat to trace.jsonl so every user-facing round is recorded
# even if the go skill wrote no execution event this round. No-op otherwise.
# Always exits 0.

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/ralph-lib.sh
. "$HOOKS_DIR/../scripts/ralph-lib.sh" 2>/dev/null || { exit 0; }

main() {
    ralph_parse_hook_stdin || return 0
    local cwd
    cwd="$(cat "$RALPH_HOOK_CWD_FILE" 2>/dev/null || true)"
    ralph_cleanup_hook_stdin
    case "$cwd" in *[![:space:]]*) ;; *) return 0 ;; esac

    local pending_path ct
    pending_path="$(ralph_dir "$cwd")/.pending-prompt.json"
    ct="$(ralph_get_current_task "$cwd")"
    if [ -z "$ct" ]; then
        # Not tracking a go task — drop any stray pending prompt and bail.
        rm -f "$pending_path" 2>/dev/null || true
        return 0
    fi

    local query phase
    query="$(ralph_json_get "$pending_path" query)"
    phase="$(ralph_get_phase "$cwd")"

    ralph_add_trace "$cwd" "$phase" 'round' "$query"
    rm -f "$pending_path" 2>/dev/null || true
    return 0
}

main 2>/dev/null || true
exit 0
