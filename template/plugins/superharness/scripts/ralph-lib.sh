#!/usr/bin/env bash
# Ralph state mechanism — zero-dependency bash state library (macOS / Linux).
# Counterpart of scripts/ralph-lib.ps1.
#
# Manages the four runtime files of a resumable autonomous-task loop, all under
# <project>/.claude/superharness/ralph/ :
#   .current-task      one-line pointer to the active task (switch = rewrite the line)
#   task.json          task-list snapshot {status,phase,sprint,tasks[],updated_at}
#   trace.jsonl        append-only ledger, one {ts,phase,event,detail} JSON per line
#   .ralph-state.json  retry counter {retries,max,updated_at}, capped at 5
#
# Source this file to use the functions. The trace hooks (hooks/stop.sh,
# hooks/user-prompt-submit.sh) source it for go task tracking. Conventions:
# UTF-8 without BOM, atomic temp-then-move for JSON snapshots, ISO-8601 timestamps.
#
# JSON handling needs node (preferred) or python3 as a fallback.

# ---------------------------------------------------------------- json helper

ralph_json_escape() {
    # $1 = raw string -> prints JSON-escaped content WITHOUT surrounding quotes.
    local __raw="$1"
    if command -v node >/dev/null 2>&1; then
        RALPH_ESC="$__raw" node -e 'process.stdout.write(JSON.stringify(process.env.RALPH_ESC).slice(1,-1))'
    elif command -v python3 >/dev/null 2>&1; then
        RALPH_ESC="$__raw" python3 -c 'import json,os;print(json.dumps(os.environ["RALPH_ESC"])[1:-1],end="")'
    else
        # minimal fallback: backslash then double quote
        printf '%s' "${__raw//\\/\\\\}" | sed 's/"/\\"/g' | awk '{if(NR>1)printf "\\n";printf "%s",$0}'
    fi
}

ralph_json_get() {
    # $1 = file  $2... = property path (top-level keys only, one per arg)
    # Prints the value as text (objects/arrays as JSON), nothing when absent.
    local __f="$1"; shift
    [ -f "$__f" ] || return 0
    if command -v node >/dev/null 2>&1; then
        node -e '
            const fs=require("fs");
            let o; try{o=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));}catch{process.exit(0);}
            let v=o;
            for(let i=2;i<process.argv.length;i++){ if(v==null||typeof v!=="object"){process.exit(0);} v=v[process.argv[i]]; }
            if(v===undefined||v===null) process.exit(0);
            process.stdout.write(typeof v==="object"?JSON.stringify(v):String(v));
        ' "$__f" "$@"
    elif command -v python3 >/dev/null 2>&1; then
        python3 - "$__f" "$@" <<'PY'
import json,sys
try:
    o=json.load(open(sys.argv[1],encoding="utf-8"))
except Exception:
    sys.exit(0)
v=o
for k in sys.argv[2:]:
    if not isinstance(v,dict) or k not in v: sys.exit(0)
    v=v[k]
if v is None: sys.exit(0)
print(json.dumps(v) if isinstance(v,(dict,list)) else v,end="")
PY
    fi
}

# ---------------------------------------------------------------- paths & helpers

ralph_parse_hook_stdin() {
    # Parse hook input JSON from stdin. Writes the `cwd` and `prompt` fields to two
    # temp files and sets RALPH_HOOK_CWD_FILE / RALPH_HOOK_PROMPT_FILE. Returns 1
    # when stdin is empty or not valid JSON. Needs node or python3.
    local raw
    raw="$(cat || true)"
    printf '%s' "$raw" | grep -q '[^[:space:]]' || return 1
    local tmpdir="${TMPDIR:-/tmp}"
    RALPH_HOOK_CWD_FILE="$tmpdir/ralph-hook-cwd.$$"
    RALPH_HOOK_PROMPT_FILE="$tmpdir/ralph-hook-prompt.$$"
    if command -v node >/dev/null 2>&1; then
        printf '%s' "$raw" | RALPH_CWD_F="$RALPH_HOOK_CWD_FILE" RALPH_PROMPT_F="$RALPH_HOOK_PROMPT_FILE" node -e '
            const fs = require("fs");
            let s = "";
            process.stdin.setEncoding("utf8");
            process.stdin.on("data", d => { s += d; });
            process.stdin.on("end", () => {
                let o;
                try { o = JSON.parse(s); } catch { process.exit(1); }
                fs.writeFileSync(process.env.RALPH_CWD_F, typeof o.cwd === "string" ? o.cwd : "");
                fs.writeFileSync(process.env.RALPH_PROMPT_F, typeof o.prompt === "string" ? o.prompt : "");
            });
        ' || return 1
    elif command -v python3 >/dev/null 2>&1; then
        printf '%s' "$raw" | RALPH_CWD_F="$RALPH_HOOK_CWD_FILE" RALPH_PROMPT_F="$RALPH_HOOK_PROMPT_FILE" python3 -c '
import json, os, sys
try:
    o = json.load(sys.stdin)
except Exception:
    sys.exit(1)
cwd = o.get("cwd") if isinstance(o.get("cwd"), str) else ""
prompt = o.get("prompt") if isinstance(o.get("prompt"), str) else ""
open(os.environ["RALPH_CWD_F"], "w", encoding="utf-8").write(cwd)
open(os.environ["RALPH_PROMPT_F"], "w", encoding="utf-8").write(prompt)
' || return 1
    else
        return 1
    fi
}

ralph_cleanup_hook_stdin() {
    rm -f "${RALPH_HOOK_CWD_FILE:-}" "${RALPH_HOOK_PROMPT_FILE:-}" 2>/dev/null || true
}

ralph_dir() { printf '%s/.claude/superharness/ralph' "$1"; }

ralph_iso() { date -u '+%Y-%m-%dT%H:%M:%S+00:00'; }

ralph_go_invocation() {
    # Parse a UserPromptSubmit prompt. If it is a `/superharness:go <goal>` invocation
    # (leading slash optional, must be at the start of the prompt), print two lines:
    #   line 1: Goal
    #   line 2: Slug='YYYY-MM-DD-<kebab|task-HHmmss>'
    # Returns 1 when the prompt is not a go invocation. Pure.
    # Portable across GNU sed and BSD sed (macOS).
    local prompt="$1"
    printf '%s' "$prompt" | grep -qE '^[[:space:]]*/?superharness:go([^A-Za-z0-9_]|$)' || return 1
    # strip the invocation prefix (word boundary already verified above) and trim
    local goal
    goal="$(printf '%s' "$prompt" | sed -E 's/^[[:space:]]*\/?superharness:go[[:space:]]*//')"
    goal="$(printf '%s' "$goal" | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')"

    local date_part kebab tokens
    date_part="$(date '+%Y-%m-%d')"
    tokens="$(printf '%s' "$goal" | tr '[:upper:]' '[:lower:]' | LC_ALL=C grep -oE '[a-z0-9]+' | head -n 6 | paste -sd '-' - 2>/dev/null || true)"
    if [ -n "$tokens" ]; then
        kebab="$tokens"
    else
        kebab="task-$(date '+%H%M%S')"
    fi
    printf '%s\n%s-%s\n' "$goal" "$date_part" "$kebab"
}

ralph_mkdir() {
    local dir
    dir="$(ralph_dir "$1")"
    mkdir -p "$dir"
    printf '%s' "$dir"
}

ralph_write_text() {
    # Atomic write: temp file then move-replace. UTF-8 without BOM.
    local path="$1" text="$2"
    mkdir -p "$(dirname "$path")"
    local tmp="$path.tmp.$$"
    printf '%s' "$text" > "$tmp"
    mv -f "$tmp" "$path"
}

ralph_write_json() {
    # $1 = path, $2 = already-serialized JSON text
    ralph_write_text "$1" "$2"
}

ralph_read_json() {
    # Prints raw JSON content when the file exists and is non-empty.
    local path="$1"
    [ -f "$path" ] || return 1
    [ -s "$path" ] || return 1
    cat "$path"
}

# ---------------------------------------------------------------- .current-task

ralph_current_task_path() { printf '%s/.current-task' "$(ralph_dir "$1")"; }

ralph_set_current_task() {
    # The pointer is a single line; switching a task rewrites only this line.
    local root="$1" task_id="$2"
    task_id="$(printf '%s' "$task_id" | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')"
    ralph_write_text "$(ralph_current_task_path "$root")" "$task_id"
}

ralph_get_current_task() {
    local p line
    p="$(ralph_current_task_path "$1")"
    [ -f "$p" ] || return 0
    line="$(sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//' "$p" | head -n 1)"
    [ -n "$line" ] && printf '%s' "$line"
    return 0
}

# ---------------------------------------------------------------- task.json

ralph_task_path() { printf '%s/task.json' "$(ralph_dir "$1")"; }

ralph_init_tasks() {
    # Write a fresh task-list snapshot with an empty task list (the agent enriches
    # it later). $1=root  $2=status(planning)  $3=phase(plan)
    local root="$1" status="${2:-planning}" phase="${3:-implement}"
    local now
    now="$(ralph_iso)"
    local snapshot="{\"status\":\"$(ralph_json_escape "$status")\",\"phase\":\"$(ralph_json_escape "$phase")\",\"sprint\":{\"current\":0,\"total\":0},\"tasks\":[],\"updated_at\":\"$now\"}"
    ralph_write_json "$(ralph_task_path "$root")" "$snapshot"
}

ralph_get_tasks() {
    ralph_read_json "$(ralph_task_path "$1")"
}

ralph_get_phase() {
    # Prints task.json's phase, or 'go' when absent.
    local phase
    phase="$(ralph_json_get "$(ralph_task_path "$1")" phase)"
    if [ -n "$phase" ]; then printf '%s' "$phase"; else printf 'go'; fi
}

# ---------------------------------------------------------------- trace.jsonl

ralph_trace_path() { printf '%s/trace.jsonl' "$(ralph_dir "$1")"; }

ralph_add_trace() {
    # Append a single minified {ts,phase,event,detail} line. Never rewrites earlier
    # lines — the worst a crash can corrupt is the final line.
    # $1=root  $2=phase  $3=event  $4=detail
    local root="$1" phase="$2" event="$3" detail="${4:-}"
    ralph_mkdir "$root" > /dev/null
    local now line
    now="$(ralph_iso)"
    line="{\"ts\":\"$now\",\"phase\":\"$(ralph_json_escape "$phase")\",\"event\":\"$(ralph_json_escape "$event")\",\"detail\":\"$(ralph_json_escape "$detail")\"}"
    printf '%s\n' "$line" >> "$(ralph_trace_path "$root")"
}

ralph_get_trace_tail() {
    # Print the last N non-empty lines of the ledger (raw JSON lines).
    local root="$1" count="${2:-1}"
    local p
    p="$(ralph_trace_path "$root")"
    [ -f "$p" ] || return 0
    tail -n "$count" "$p" | grep -v '^[[:space:]]*$' || true
}

# ---------------------------------------------------------------- .ralph-state.json (retry counter)

ralph_retry_path() { printf '%s/.ralph-state.json' "$(ralph_dir "$1")"; }

ralph_get_retry_state() {
    # Prints two lines: retries, max. Defaults to 0, 5 when absent or malformed.
    local root="$1" retries max
    retries="$(ralph_json_get "$(ralph_retry_path "$root")" retries)"
    max="$(ralph_json_get "$(ralph_retry_path "$root")" max)"
    case "$retries" in ''|*[!0-9]*) retries=0 ;; esac
    case "$max" in ''|*[!0-9]*) max=5 ;; esac
    printf '%s\n%s\n' "$retries" "$max"
}

ralph_set_retry_state() {
    # $1=root  $2=retries  $3=max
    local root="$1" retries="$2" max="$3" now
    now="$(ralph_iso)"
    ralph_write_json "$(ralph_retry_path "$root")" "{\"retries\":$retries,\"max\":$max,\"updated_at\":\"$now\"}"
}

ralph_add_retry() {
    # Increment the retry counter, clamped at max. Prints the new retry count.
    local root="$1" state retries max
    state="$(ralph_get_retry_state "$root")"
    retries="$(printf '%s\n' "$state" | head -n 1)"
    max="$(printf '%s\n' "$state" | tail -n 1)"
    local n=$((retries + 1))
    if [ "$n" -gt "$max" ]; then n=$max; fi
    ralph_set_retry_state "$root" "$n" "$max"
    printf '%s' "$n"
}

ralph_test_retry_exhausted() {
    # Exit status 0 when retries >= max.
    local state retries max
    state="$(ralph_get_retry_state "$1")"
    retries="$(printf '%s\n' "$state" | head -n 1)"
    max="$(printf '%s\n' "$state" | tail -n 1)"
    [ "$retries" -ge "$max" ]
}

ralph_reset_retry() {
    local state max
    state="$(ralph_get_retry_state "$1")"
    max="$(printf '%s\n' "$state" | tail -n 1)"
    ralph_set_retry_state "$1" 0 "$max"
}

# ---------------------------------------------------------------- task bootstrap

ralph_start_task() {
    # Auto-bootstrap a fresh go task: point .current-task, seed an empty task.json
    # (planning/plan — the agent enriches the task list later), open the trace ledger
    # with a task:started event, and reset the retry counter. Idempotent-ish: calling
    # again repoints to a new TaskId and appends another task:started line.
    # $1=root  $2=task_id  $3=goal
    local root="$1" task_id="$2" goal="${3:-}"
    ralph_set_current_task "$root" "$task_id"
    ralph_init_tasks "$root" 'planning' 'plan'
    ralph_add_trace "$root" 'plan' 'task:started' "$goal"
    ralph_reset_retry "$root"
}

# ---------------------------------------------------------------- cold-start recovery

ralph_get_resume_context() {
    # Assemble the deterministic file-based facts a freshly-started agent needs to
    # resume: the active pointer, the task snapshot, the last ledger event, and the
    # retry state — as a single JSON object. The agent then reconciles these
    # against `git diff` (code wins) and fixes task.json.
    local root="$1"
    local current tasks last_trace retries max all_done
    current="$(ralph_get_current_task "$root")"
    tasks="$(ralph_get_tasks "$root" || true)"
    last_trace="$(ralph_get_trace_tail "$root" 1 | tail -n 1)"
    local state
    state="$(ralph_get_retry_state "$root")"
    retries="$(printf '%s\n' "$state" | head -n 1)"
    max="$(printf '%s\n' "$state" | tail -n 1)"

    all_done=false
    if [ -n "$tasks" ]; then
        local remaining=""
        if command -v node >/dev/null 2>&1; then
            remaining="$(RALPH_TASKS="$tasks" node -e '
                let o; try{o=JSON.parse(process.env.RALPH_TASKS||"");}catch{process.exit(0);}
                const ts=Array.isArray(o.tasks)?o.tasks:[];
                process.stdout.write(ts.some(t=>t.status!=="done")?"1":"");
            ')"
        elif command -v python3 >/dev/null 2>&1; then
            remaining="$(RALPH_TASKS="$tasks" python3 -c '
import json,os
try:
    o=json.loads(os.environ.get("RALPH_TASKS",""))
except Exception:
    raise SystemExit(0)
ts=o.get("tasks") or []
print("1" if any(t.get("status")!="done" for t in ts) else "",end="")')"
        fi
        [ -z "$remaining" ] && all_done=true
    fi

    local current_json="null" tasks_json="null" last_json="null"
    [ -n "$current" ] && current_json="\"$(ralph_json_escape "$current")\""
    [ -n "$tasks" ] && tasks_json="$tasks"
    [ -n "$last_trace" ] && last_json="$last_trace"

    printf '{"current_task":%s,"tasks":%s,"last_trace":%s,"all_done":%s,"retry":{"retries":%s,"max":%s}}' \
        "$current_json" "$tasks_json" "$last_json" "$all_done" "$retries" "$max"
}
