#!/bin/sh
# The window name never encodes activity state (task 2.2).
. "$(dirname "$0")/lib.sh"
HOOK=$(cd "$(dirname "$0")/.." && pwd)/plugins/tmux-window-title/hooks/set-title.sh
tmux_start

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/claude-title-state.XXXXXX")
cleanup() { rm -rf "$ROOT"; tmux_stop; }
trap cleanup EXIT

# HOOK_PATH overrides PATH for the hook process (to hide `claude`).
fire() { printf "%s" "$2" | PATH=${HOOK_PATH:-$PATH} TMUX_PANE="${3:-$TMUX_PANE}" sh "$HOOK" "$1" >/dev/null 2>&1; }

mkdir -p "$ROOT/api-pagos"
git -C "$ROOT/api-pagos" init -q -b main
git -C "$ROOT/api-pagos" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --allow-empty -m init
CWD=$ROOT/api-pagos

# A PATH identical to the current one but without any `claude` executable.
NOCLAUDE=$ROOT/bin
mkdir "$NOCLAUDE"
old_ifs=$IFS
IFS=:
for d in $PATH; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
        if [ ! -x "$f" ] || [ -d "$f" ]; then continue; fi
        n=${f##*/}
        [ "$n" = claude ] && continue
        [ -e "$NOCLAUDE/$n" ] || ln -s "$f" "$NOCLAUDE/$n"
    done
done
IFS=$old_ifs

# has_state NAME : true if NAME looks like an activity state.
has_state() {
    case $1 in
        *claude:* | *idle* | *'ESPERA INPUT'* | *'Edit foo.ts'*) return 0 ;;
    esac
    return 1
}
assert_stateless() {
    if has_state "$1"; then
        assert_eq "a name without state text" "$1" "$2"
    else
        assert_eq "ok" "ok" "$2"
    fi
}

start_json=$(jq -nc --arg c "$CWD" '{hook_event_name:"SessionStart",cwd:$c}')
prompt_json=$(jq -nc --arg c "$CWD" '{hook_event_name:"UserPromptSubmit",cwd:$c,prompt:"arregla el bug"}')
tool_json='{"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"/x/foo.ts"}}'
notif_json='{"hook_event_name":"Notification","message":"Claude needs your permission"}'
stop_json='{"hook_event_name":"Stop"}'

run_cycle() { # $1 = label
    fire SessionStart "$start_json"
    base=$(window_name)
    assert_eq "api-pagos" "$base" "$1: session start gives the base name"
    assert_stateless "$base" "$1: session start name has no state text"

    fire UserPromptSubmit "$prompt_json"
    assert_eq "$base" "$(window_name)" "$1: prompt without a model keeps the base name"

    fire PreToolUse "$tool_json"
    assert_eq "$base" "$(window_name)" "$1: tool use does not change the name"
    assert_stateless "$(window_name)" "$1: tool use name has no state text"

    fire Notification "$notif_json"
    assert_eq "$base" "$(window_name)" "$1: notification does not change the name"
    assert_stateless "$(window_name)" "$1: notification name has no state text"

    fire Stop "$stop_json"
    assert_eq "$base" "$(window_name)" "$1: stop does not change the name"
    assert_stateless "$(window_name)" "$1: stop name has no state text"
    fire SessionEnd '{}'
}

HOOK_PATH=$NOCLAUDE
run_cycle "no claude on PATH"

HOOK_PATH=
CLAUDE_TMUX_TITLE_LLM=0
export CLAUDE_TMUX_TITLE_LLM
run_cycle "model disabled"
finish
