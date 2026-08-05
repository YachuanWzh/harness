#!/usr/bin/env bash
# UserPromptSubmit hook (macOS / Linux). Counterpart of user-prompt-submit.ps1.
# Two jobs, both best-effort (always exits 0):
#  1. Auto-trigger ralph tracking: if the submitted prompt is a `/superharness:go`
#     invocation, bootstrap the ralph state (.current-task + task.json + trace.jsonl)
#     under the ralph state root (.claude/superharness/ralph/ under Claude Code,
#     .flavor/superharness/ralph/ under flavor-code) so the files appear automatically the moment
#     a go task starts — no agent-run bootstrap required. A distinct go goal repoints
#     to a new task; re-submitting the same task is a no-op.
#  2. Stash the pending round's user query + timestamp so the Stop hook can record a
#     `round` heartbeat even if the go skill wrote no execution event this round.

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/ralph-lib.sh
. "$HOOKS_DIR/../scripts/ralph-lib.sh" 2>/dev/null || { exit 0; }

main() {
    ralph_parse_hook_stdin || return 0
    local cwd prompt
    cwd="$(cat "$RALPH_HOOK_CWD_FILE" 2>/dev/null || true)"
    prompt="$(cat "$RALPH_HOOK_PROMPT_FILE" 2>/dev/null || true)"
    ralph_cleanup_hook_stdin
    case "$cwd" in *[![:space:]]*) ;; *) return 0 ;; esac

    # 1. Auto-trigger on a go invocation (start/repoint a task automatically).
    local inv goal slug
    if inv="$(ralph_go_invocation "$prompt")"; then
        goal="$(printf '%s\n' "$inv" | head -n 1)"
        slug="$(printf '%s\n' "$inv" | tail -n 1)"
        if [ "$slug" != "$(ralph_get_current_task "$cwd")" ]; then
            ralph_start_task "$cwd" "$slug" "$goal"
        fi
    fi

    # 2. Stash the pending round.
    local pending_json
    pending_json="{\"ts\":\"$(ralph_iso)\",\"query\":\"$(ralph_json_escape "$prompt")\"}"
    ralph_write_json "$(ralph_dir "$cwd")/.pending-prompt.json" "$pending_json"
    return 0
}

main 2>/dev/null || true
exit 0
