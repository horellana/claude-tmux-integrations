#!/bin/sh
# Saving and restoring the window naming state (task 4.1).
. "$(dirname "$0")/lib.sh"
HOOK=$(cd "$(dirname "$0")/.." && pwd)/plugins/tmux-window-title/hooks/set-title.sh
tmux_start

fire() { printf '%s' "$2" | TMUX_PANE="${3:-$TMUX_PANE}" sh "$HOOK" "$1" >/dev/null 2>&1; }
opt() { t show-options -w -v -t "${2:-$TMUX_PANE}" "$1" 2>/dev/null; }
auto() { t display-message -p -t "$TMUX_PANE" '#{automatic-rename}'; }
claude_opts() {
    t show-options -w -t "$TMUX_PANE" | while read -r l; do
        case $l in @claude_*) echo "$l" ;; esac
    done
}

# --- automatic-rename on ---
orig=$(window_name)
fire SessionStart '{}'
[ -n "$(opt @claude_prev_auto)" ]
assert_eq "0" "$?" "session start stores @claude_prev_auto"
assert_eq "$orig" "$(opt @claude_prev_name)" "session start stores the previous window name"
fire UserPromptSubmit '{"prompt":"hola"}'
assert_eq "0" "$(auto)" "during the session automatic-rename is off"
fire SessionEnd '{}'
assert_eq "1" "$(auto)" "session end turns automatic-rename back on"
assert_eq "" "$(claude_opts)" "no @claude_* options remain after session end (auto on)"

# --- first event is not SessionStart: state is still saved before renaming ---
orig=$(window_name)
fire PreToolUse '{"tool_name":"Grep","tool_input":{}}'
assert_eq "$orig" "$(opt @claude_prev_name)" "state is saved before the first rename even without session start"
assert_eq "0" "$(auto)" "precondition: renamed window has automatic-rename off"
fire SessionEnd '{}'
assert_eq "1" "$(auto)" "restored to on after a session that began without session start"

# --- automatic-rename off with a custom name ---
t rename-window -t "$TMUX_PANE" -- mine
assert_eq "0" "$(auto)" "precondition: automatic-rename is off"
fire SessionStart '{}'
fire UserPromptSubmit '{"prompt":"hola"}'
assert_eq "mine" "$(opt @claude_prev_name)" "saved state is not overwritten by later events"
fire SessionStart '{}'
assert_eq "mine" "$(opt @claude_prev_name)" "a second session start does not overwrite the saved name"
fire SessionEnd '{}'
assert_eq "mine" "$(window_name)" "custom name is restored"
assert_eq "0" "$(auto)" "automatic-rename stays off"
assert_eq "" "$(claude_opts)" "no @claude_* options remain after session end (auto off)"
finish
