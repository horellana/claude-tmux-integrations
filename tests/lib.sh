#!/bin/sh
# Test helpers. Source from a test file: `. "$(dirname "$0")/lib.sh"`.
# Each test gets its own tmux server on an isolated socket (no mocks).

FAILURES=0

# Start an isolated tmux server with one detached session; export TMUX/TMUX_PANE.
tmux_start() {
    # mktemp -d with an explicit template works on GNU and BSD; its basename is unique
    TEST_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/claude-title-test.XXXXXX")
    TEST_SOCKET=${TEST_TMPDIR##*/}
    export TEST_SOCKET TEST_TMPDIR
    trap tmux_stop EXIT
    tmux -L "$TEST_SOCKET" -f /dev/null new-session -d -x 200 -y 50 -s test
    TMUX_PANE=$(tmux -L "$TEST_SOCKET" display-message -p -t test '#{pane_id}')
    TEST_SOCKET_PATH=$(tmux -L "$TEST_SOCKET" display-message -p '#{socket_path}')
    TMUX="$TEST_SOCKET_PATH,0,0"
    export TMUX TMUX_PANE
}

tmux_stop() {
    [ -n "${TEST_SOCKET:-}" ] && tmux -L "$TEST_SOCKET" kill-server 2>/dev/null
    # kill-server leaves the socket file behind
    [ -n "${TEST_SOCKET_PATH:-}" ] && rm -f "$TEST_SOCKET_PATH"
    [ -n "${TEST_TMPDIR:-}" ] && rm -rf "$TEST_TMPDIR"
    return 0
}

# t ARGS... : tmux against the test server.
t() { tmux -L "$TEST_SOCKET" "$@"; }

# Name of the window containing pane $1 (default: $TMUX_PANE).
# shellcheck disable=SC2120 # $1 is optional
window_name() { t display-message -p -t "${1:-$TMUX_PANE}" '#{window_name}'; }

# assert_eq EXPECTED ACTUAL DESCRIPTION
assert_eq() {
    if [ "$1" = "$2" ]; then
        printf 'ok   - %s\n' "$3"
    else
        printf 'FAIL - %s\n       expected: [%s]\n       actual:   [%s]\n' "$3" "$1" "$2"
        FAILURES=$((FAILURES + 1))
    fi
}

# Exit non-zero if any assertion failed.
finish() { [ "$FAILURES" -eq 0 ]; }
