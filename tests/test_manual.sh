#!/bin/sh
# A manual rename is respected for the rest of the session (task 3.4).
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/lib_refine.sh"
tmux_start
refine_setup

# --- manual rename before the first evaluation ---
new_session
reply "otro tema"
t rename-window -t "$TMUX_PANE" -- mi-trabajo
prompt "un prompt que alcanza la evaluacion"
settle
assert_eq "mi-trabajo" "$(window_name)" "manual rename: the model's answer does not replace the name"
assert_eq "1" "$(opt @claude_manual)" "manual rename: @claude_manual is 1"
c=$(calls)
export CLAUDE_TMUX_TITLE_EVERY=1
prompt "otro prompt que tambien evaluaria"
prompt "y un tercero que tambien evaluaria"
settle
assert_eq "$c" "$(calls)" "manual rename: the model is not invoked any more"
assert_eq "mi-trabajo" "$(window_name)" "manual rename: the name still stays"
unset CLAUDE_TMUX_TITLE_EVERY

# --- manual rename after the plugin already renamed ---
new_session
reply "tema uno"
prompt "primer prompt que define el tema"
wait_name "tema uno"
settle
assert_eq "tema uno" "$(window_name)" "setup: the plugin renamed the window"
t rename-window -t "$TMUX_PANE" -- mi-trabajo
export CLAUDE_TMUX_TITLE_EVERY=1
reply "tema dos"
prompt "segundo prompt que alcanza evaluacion"
settle
assert_eq "mi-trabajo" "$(window_name)" "rename after an automatic one: name kept despite another answer"
assert_eq "1" "$(opt @claude_manual)" "rename after an automatic one: @claude_manual is 1"
c=$(calls)
prompt "tercer prompt que alcanza evaluacion"
settle
assert_eq "$c" "$(calls)" "rename after an automatic one: the model is not invoked any more"
assert_eq "mi-trabajo" "$(window_name)" "rename after an automatic one: still kept"
finish
