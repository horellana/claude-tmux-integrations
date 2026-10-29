#!/bin/sh
# Saving and restoring the window naming state (task 4.1).
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/lib_refine.sh"
tmux_start
refine_setup

auto() { t display-message -p -t "$TMUX_PANE" '#{automatic-rename}'; }
claude_opts() {
    t show-options -w -t "$TMUX_PANE" | while read -r l; do
        case $l in @claude_*) echo "$l" ;; esac
    done
}

# --- UserPromptSubmit without SessionStart: no state, no rename ---
t rename-window -t "$TMUX_PANE" -- fixed
reply "intruso"
prompt "un prompt sustancial sin sesion iniciada"
assert_eq "0" "$?" "prompt without session start: exit 0"
sleep 0.3
assert_eq "fixed" "$(window_name)" "prompt without session start: the name is not changed"
assert_eq "0" "$(auto)" "prompt without session start: automatic-rename unchanged (off)"
assert_eq "" "$(claude_opts)" "prompt without session start: no @claude_* options are created"
assert_eq "0" "$(calls)" "prompt without session start: the model is not invoked"
t set-window-option -t "$TMUX_PANE" automatic-rename on
prompt "otro prompt sustancial sin sesion iniciada"
sleep 0.3
assert_eq "1" "$(auto)" "prompt without session start: automatic-rename unchanged (on)"
assert_eq "" "$(claude_opts)" "prompt without session start: still no @claude_* options (on)"
assert_eq "0" "$(calls)" "prompt without session start: the model is still not invoked"

# --- automatic-rename on ---
assert_eq "1" "$(auto)" "precondition: automatic-rename is on"
start_session
assert_eq "1" "$(opt @claude_prev_auto)" "session start stores @claude_prev_auto=1"
[ -n "$(opt @claude_prev_name)" ]
assert_eq "0" "$?" "session start stores a non-empty previous window name"
assert_eq "proj" "$(opt @claude_title)" "session start sets @claude_title to the base name"
assert_eq "0" "$(auto)" "during the session automatic-rename is off"
reply "tema uno"
prompt "primer prompt sustancial de la sesion"
wait_name "tema uno"
settle
assert_eq "tema uno" "$(opt @claude_title)" "the model's name is stored in @claude_title"
assert_eq "1" "$(opt @claude_n)" "@claude_n counts the substantial prompt"
t rename-window -t "$TMUX_PANE" -- mi-trabajo
export CLAUDE_TMUX_TITLE_EVERY=1
reply "tema dos"
prompt "segundo prompt sustancial de la sesion"
wait_calls_ge 2
settle
unset CLAUDE_TMUX_TITLE_EVERY
assert_eq "1" "$(opt @claude_manual)" "a manual rename sets @claude_manual=1"
fire SessionEnd '{}'
assert_eq "1" "$(auto)" "session end turns automatic-rename back on"
assert_eq "" "$(claude_opts)" "no @claude_* options remain after session end (auto on, manual rename)"

# --- automatic-rename off with a custom name ---
new_session mine
assert_eq "0" "$(auto)" "precondition: automatic-rename is off"
assert_eq "0" "$(opt @claude_prev_auto)" "custom-named window stores prev_auto 0"
assert_eq "mine" "$(opt @claude_prev_name)" "custom-named window stores its name"
prompt "un prompt sustancial en la sesion"
wait_calls_ge 1
settle
assert_eq "mine" "$(opt @claude_prev_name)" "saved state is not overwritten by later events"
start_session
assert_eq "0" "$(opt @claude_prev_auto)" "a second session start does not overwrite the saved prev_auto"
assert_eq "mine" "$(opt @claude_prev_name)" "a second session start does not overwrite the saved name"
fire SessionEnd '{}'
assert_eq "mine" "$(window_name)" "custom name is restored"
assert_eq "0" "$(auto)" "automatic-rename stays off"
assert_eq "" "$(claude_opts)" "no @claude_* options remain after session end (auto off)"
finish
