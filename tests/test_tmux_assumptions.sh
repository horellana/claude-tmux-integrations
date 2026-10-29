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

# User options (@x) on a window, as the plugin stores its state
assert_eq "" "$(t show-options -w -v -t "$w" @claude_x)" "unset window user option reads empty"
t set-option -w -t "$w" @claude_x "a b"
assert_eq "a b" "$(t show-options -w -v -t "$w" @claude_x)" "window user option round-trips"
t set-option -w -u -t "$w" @claude_x
assert_eq "" "$(t show-options -w -v -t "$w" @claude_x)" "set-option -w -u removes the option"
finish
