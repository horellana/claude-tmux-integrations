#!/bin/sh
# Verifies the tmux behaviour the design relies on (tmux 3.8).
. "$(dirname "$0")/lib.sh"
tmux_start
w=$TMUX_PANE
auto() { t display-message -p -t "$w" '#{automatic-rename}'; }

assert_eq "1" "$(auto)" "automatic-rename starts on"
t rename-window -t "$w" -- "claude: idle"
assert_eq "0" "$(auto)" "rename-window sets automatic-rename off"
t set-window-option -t "$w" automatic-rename on
assert_eq "1" "$(auto)" "set-window-option automatic-rename on re-enables it"
finish
