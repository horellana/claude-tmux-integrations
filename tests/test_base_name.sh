#!/bin/sh
# Base window name from the project folder and git branch (task 2.1).
. "$(dirname "$0")/lib.sh"
HOOK=$(cd "$(dirname "$0")/.." && pwd)/plugins/tmux-window-title/hooks/set-title.sh
tmux_start
# Never let a real model rename the window under test.
CLAUDE_TMUX_TITLE_LLM=0
export CLAUDE_TMUX_TITLE_LLM

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/claude-title-base.XXXXXX")
cleanup() { rm -rf "$ROOT"; tmux_stop; }
trap cleanup EXIT

fire() { printf '%s' "$2" | TMUX_PANE="${3:-$TMUX_PANE}" sh "$HOOK" "$1" >/dev/null 2>&1; }
opt() { t show-options -w -v -t "$TMUX_PANE" "$1" 2>/dev/null; }
cwd_json() { jq -nc --arg c "$1" '{hook_event_name:"SessionStart",cwd:$c}'; }

# mkrepo DIR BRANCH : git repo with one commit on BRANCH.
mkrepo() {
    mkdir -p "$1" &&
        git -C "$1" init -q -b "$2" &&
        git -C "$1" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --allow-empty -m init
}

# start_in DIR : session start with DIR as cwd, then print the window name.
start_in() {
    fire SessionStart "$(cwd_json "$1")"
    window_name
}
# Each case begins from a restored window so the saved state is fresh.
reset() { fire SessionEnd '{}'; }

mkrepo "$ROOT/api-pagos" main
assert_eq "api-pagos" "$(start_in "$ROOT/api-pagos")" "repo on main is named after the repo"
reset

git -C "$ROOT/api-pagos" checkout -q -b fix/timeout
assert_eq "api-pagos fix/timeout" "$(start_in "$ROOT/api-pagos")" "repo on a work branch appends the branch"
reset

mkrepo "$ROOT/legacy" master
assert_eq "legacy" "$(start_in "$ROOT/legacy")" "repo on master is named after the repo only"
reset

mkrepo "$ROOT/mono" main
mkdir -p "$ROOT/mono/src/deep"
assert_eq "mono" "$(start_in "$ROOT/mono/src/deep")" "cwd in a repo subdirectory uses the repo root name"
reset

mkdir "$ROOT/notas"
assert_eq "notas" "$(start_in "$ROOT/notas")" "directory outside a repo is named after the directory"
reset

mkdir "$ROOT/workdir"
(
    cd "$ROOT/workdir" || exit 1
    printf '%s' '{"hook_event_name":"SessionStart"}' | TMUX_PANE=$TMUX_PANE sh "$HOOK" SessionStart >/dev/null 2>&1
)
assert_eq "workdir" "$(window_name)" "missing cwd falls back to the basename of PWD"
reset

mkdir "$ROOT/café ñandú\$&x"
assert_eq "caf andx" "$(start_in "$ROOT/café ñandú\$&x")" "characters outside the allowed list are dropped"
reset

mkdir "$ROOT/a.b_c-d:e f"
assert_eq "a.b_c-d:e f" "$(start_in "$ROOT/a.b_c-d:e f")" "allowed punctuation is kept"
reset

mkdir "$ROOT/aaaaaaaaaabbbbbbbbbbccccccccccddddddddddeeeeeeeeee"
assert_eq "aaaaaaaaaabbbbbbbbbbcccccccc" "$(start_in "$ROOT/aaaaaaaaaabbbbbbbbbbccccccccccddddddddddeeeeeeeeee")" "long folder name is cut to its first 28 characters"
reset

git -C "$ROOT/api-pagos" checkout -q -b fix/timeout-muy-largo-de-verdad
assert_eq "api-pagos fix/timeout-muy-la" "$(start_in "$ROOT/api-pagos")" "repo plus long branch is cut to 28 characters"
reset

# --- saved state and restore ---
start_in "$ROOT/notas" >/dev/null
assert_eq "1" "$(opt @claude_prev_auto)" "session start stores @claude_prev_auto"
# The auto-renamed name may change on its own, so only check that one was saved.
[ -n "$(opt @claude_prev_name)" ]
assert_eq "0" "$?" "session start stores a previous window name"
fire SessionEnd '{}'
assert_eq "" "$(opt @claude_prev_auto)" "session end clears @claude_prev_auto"
assert_eq "1" "$(t display-message -p -t "$TMUX_PANE" '#{automatic-rename}')" "session end turns automatic-rename back on"

t rename-window -t "$TMUX_PANE" -- mine
start_in "$ROOT/notas" >/dev/null
assert_eq "0" "$(opt @claude_prev_auto)" "custom-named window stores prev_auto 0"
assert_eq "mine" "$(opt @claude_prev_name)" "custom-named window stores its name"
fire SessionEnd '{}'
assert_eq "mine" "$(window_name)" "session end restores the custom name"
finish
