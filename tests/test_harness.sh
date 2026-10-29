#!/bin/sh
. "$(dirname "$0")/lib.sh"
tmux_start
sock=$TEST_SOCKET
t new-window -d -n probe
assert_eq "probe" "$(t display-message -p -t :probe '#{window_name}')" "can create and read a window name"
tmux_stop
if tmux -L "$sock" ls >/dev/null 2>&1; then
    assert_eq "dead" "alive" "server is killed after the test"
else
    assert_eq "dead" "dead" "server is killed after the test"
fi
finish
