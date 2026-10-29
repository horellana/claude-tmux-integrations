#!/bin/sh
# Silent, non-blocking behaviour outside tmux and on failure (tasks 4.2, 4.3).
. "$(dirname "$0")/lib.sh"
HOOK=$(cd "$(dirname "$0")/.." && pwd)/plugins/tmux-window-title/hooks/set-title.sh
tmux_start
tmp=$(mktemp -d)
trap 'tmux_stop; rm -rf "$tmp"' EXIT
SH=$(command -v sh)
JSON='{"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"a/b.ts"}}'

# run_hook EVENT : runs the hook with the caller's env prefix in $ENVP; sets status/out/err.
run_hook() {
    out=$(printf '%s' "$JSON" | env "$@" "$SH" "$HOOK" PreToolUse 2>"$tmp/err")
    status=$?
    err=$(cat "$tmp/err")
}

# tmux shim recording every call
mkdir "$tmp/shim"
cat > "$tmp/shim/tmux" <<SHIM
#!/bin/sh
echo "\$@" >> "$tmp/calls"
exit 1
SHIM
chmod +x "$tmp/shim/tmux"

for case in unset empty; do
    rm -f "$tmp/calls"
    if [ "$case" = unset ]; then
        run_hook -u TMUX_PANE "PATH=$tmp/shim:$PATH"
    else
        run_hook TMUX_PANE= "PATH=$tmp/shim:$PATH"
    fi
    assert_eq "0" "$status" "TMUX_PANE $case: exit 0"
    assert_eq "" "$out$err" "TMUX_PANE $case: no output"
    [ ! -s "$tmp/calls" ]; assert_eq "0" "$?" "TMUX_PANE $case: tmux is not invoked"
done

# Dead server.
run_hook TMUX_PANE=%0 "TMUX=$tmp/nonexistent-socket,0,0"
assert_eq "0" "$status" "dead tmux server: exit 0"
assert_eq "" "$out$err" "dead tmux server: no output"

# No jq on PATH.
mkdir "$tmp/nojq"
oldifs=$IFS; IFS=:
for d in $PATH; do
    for f in "$d"/*; do
        b=${f##*/}
        [ "$b" = jq ] && continue
        [ -x "$f" ] && [ ! -d "$f" ] && [ ! -e "$tmp/nojq/$b" ] && ln -s "$f" "$tmp/nojq/$b"
    done
done
IFS=$oldifs
t rename-window -t "$TMUX_PANE" -- before
run_hook "PATH=$tmp/nojq"
assert_eq "0" "$status" "no jq: exit 0"
assert_eq "" "$out$err" "no jq: no output"
assert_eq "before" "$(window_name)" "no jq: window is left alone"

# PreToolUse against a live server emits no decision.
run_hook "PATH=$PATH"
assert_eq "0" "$status" "PreToolUse: exit 0"
assert_eq "" "$out" "PreToolUse: stdout empty (no permission decision)"
assert_eq "" "$err" "PreToolUse: stderr empty"
assert_eq "claude: Edit b.ts" "$(window_name)" "PreToolUse still renames the window"
finish
