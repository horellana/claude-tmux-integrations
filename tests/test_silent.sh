#!/bin/sh
# Silent, non-blocking behaviour outside tmux, on failure and inside the model call (tasks 3.6, 4.2, 4.3).
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/lib_refine.sh"
tmux_start
refine_setup
tmp=$RT/silent
mkdir "$tmp"
SH=$(command -v sh)

# run_hook EVENT JSON [ENV...] : stdout in $out, stderr in $tmp/err (read it with `errs`), status in $status.
run_hook() {
    ev=$1
    js=$2
    shift 2
    out=$(printf '%s' "$js" | env "$@" "$SH" "$HOOK" "$ev" 2>"$tmp/err")
    status=$?
}
errs() { cat "$tmp/err"; }

PJSON=$(jq -nc --arg c "$PROJ" '{hook_event_name:"UserPromptSubmit",prompt:"un prompt sustancial de prueba",cwd:$c}')
SJSON=$(jq -nc --arg c "$PROJ" '{hook_event_name:"SessionStart",cwd:$c}')
EJSON='{"hook_event_name":"SessionEnd"}'
json_for() { case $1 in SessionStart) echo "$SJSON" ;; UserPromptSubmit) echo "$PJSON" ;; *) echo "$EJSON" ;; esac; }

# tmux shim recording every call
mkdir "$tmp/shim"
cat > "$tmp/shim/tmux" <<SHIM
#!/bin/sh
echo "\$@" >> "$tmp/calls"
exit 1
SHIM
chmod +x "$tmp/shim/tmux"

# --- outside tmux: nothing runs, nothing is printed ---
new_session
for ev in SessionStart UserPromptSubmit SessionEnd; do
    for case in unset empty; do
        rm -f "$tmp/calls"
        if [ "$case" = unset ]; then
            run_hook "$ev" "$(json_for "$ev")" -u TMUX_PANE "PATH=$tmp/shim:$PATH"
        else
            run_hook "$ev" "$(json_for "$ev")" TMUX_PANE= "PATH=$tmp/shim:$PATH"
        fi
        assert_eq "0" "$status" "$ev, TMUX_PANE $case: exit 0"
        assert_eq "" "$out$(errs)" "$ev, TMUX_PANE $case: no output"
        [ ! -s "$tmp/calls" ]; assert_eq "0" "$?" "$ev, TMUX_PANE $case: tmux is not invoked"
    done
done
sleep 0.3
assert_eq "0" "$(calls)" "outside tmux: the model is never invoked"

# --- dead server ---
for ev in SessionStart UserPromptSubmit SessionEnd; do
    run_hook "$ev" "$(json_for "$ev")" TMUX_PANE=%0 "TMUX=$tmp/nonexistent-socket,0,0"
    assert_eq "0" "$status" "dead tmux server, $ev: exit 0"
    assert_eq "" "$out$(errs)" "dead tmux server, $ev: no output"
done

# --- no jq on PATH ---
make_path_without jq "$tmp/nojq"
new_session
t rename-window -t "$TMUX_PANE" -- before
run_hook UserPromptSubmit "$PJSON" "PATH=$tmp/nojq"
settle
assert_eq "0" "$status" "no jq: exit 0"
assert_eq "" "$out$(errs)" "no jq: no output"
assert_eq "before" "$(window_name)" "no jq: window is left alone"

# --- invalid JSON ---
new_session
for ev in UserPromptSubmit SessionStart SessionEnd; do
    run_hook "$ev" 'not json {' "PATH=$PATH"
    settle
    assert_eq "0" "$status" "invalid JSON, $ev: exit 0"
    assert_eq "" "$out$(errs)" "invalid JSON, $ev: no output"
done
new_session
t rename-window -t "$TMUX_PANE" -- before
run_hook UserPromptSubmit 'not json {' "PATH=$PATH"
settle
assert_eq "before" "$(window_name)" "invalid JSON: the prompt is not evaluated and the name is left alone"
assert_eq "0" "$(calls)" "invalid JSON: the model is not invoked"

# --- unknown events do nothing ---
new_session
for ev in PreToolUse Stop Notification; do
    run_hook "$ev" '{"tool_name":"Edit","tool_input":{"file_path":"a/b.ts"}}' "PATH=$PATH"
    assert_eq "0" "$status" "$ev: exit 0"
    assert_eq "" "$out$(errs)" "$ev: no output"
done
assert_eq "proj" "$(window_name)" "unknown events leave the name"
assert_eq "0" "$(calls)" "unknown events do not invoke the model"

# --- CLAUDE_TMUX_TITLE_BG=1: the hook exits at once, silently ---
fire SessionEnd '{}'
for o in @claude_n @claude_manual @claude_title @claude_prev_auto @claude_prev_name; do
    t set-option -w -u -t "$TMUX_PANE" "$o" 2>/dev/null
done
assert_eq "" "$(opt @claude_prev_auto)" "setup: no session state before the BG=1 SessionStart"
t rename-window -t "$TMUX_PANE" -- before
run_hook SessionStart "$SJSON" CLAUDE_TMUX_TITLE_BG=1
assert_eq "0" "$status" "BG=1, SessionStart: exit 0"
assert_eq "" "$out$(errs)" "BG=1, SessionStart: no output"
assert_eq "before" "$(window_name)" "BG=1, SessionStart: no rename"
assert_eq "" "$(opt @claude_prev_auto)" "BG=1, SessionStart: no state saved"
new_session
reply "nombre intruso"
run_hook UserPromptSubmit "$PJSON" CLAUDE_TMUX_TITLE_BG=1
settle
assert_eq "0" "$status" "BG=1, UserPromptSubmit: exit 0"
assert_eq "" "$out$(errs)" "BG=1, UserPromptSubmit: no output"
assert_eq "proj" "$(window_name)" "BG=1, UserPromptSubmit: no rename even for a substantial prompt"
assert_eq "0" "$(calls)" "BG=1, UserPromptSubmit: the model is not invoked"
assert_eq "" "$(opt @claude_n)" "BG=1, UserPromptSubmit: the prompt is not counted"
saved_auto=$(opt @claude_prev_auto)
[ -n "$saved_auto" ]; assert_eq "0" "$?" "setup: session state exists before the BG=1 SessionEnd"
run_hook SessionEnd "$EJSON" CLAUDE_TMUX_TITLE_BG=1
assert_eq "0" "$status" "BG=1, SessionEnd: exit 0"
assert_eq "" "$out$(errs)" "BG=1, SessionEnd: no output"
assert_eq "$saved_auto" "$(opt @claude_prev_auto)" "BG=1, SessionEnd: state is not cleared, nothing restored"
assert_eq "proj" "$(window_name)" "BG=1, SessionEnd: the name stays"

# --- the guard reaches the model process, so its hooks exit at once ---
new_session
prompt "este prompt lanza al modelo de verdad"
wait_calls_ge 1
settle
awk '$0 == "CLAUDE_TMUX_TITLE_BG=1"{f=1} END{exit !f}' "$FAKE/env.1" 2>/dev/null
assert_eq "0" "$?" "the model process runs with CLAUDE_TMUX_TITLE_BG=1"

# --- CLAUDE_TMUX_TITLE_LLM=0 / no binary: base name stays ---
new_session
reply "nombre del modelo"
run_hook UserPromptSubmit "$PJSON" CLAUDE_TMUX_TITLE_LLM=0
settle
assert_eq "0" "$status" "LLM=0: exit 0"
assert_eq "" "$out$(errs)" "LLM=0: no output"
assert_eq "0" "$(calls)" "LLM=0: the model is not invoked"
assert_eq "proj" "$(window_name)" "LLM=0: the base name stays"

make_path_without claude "$tmp/noclaude"
new_session
run_hook SessionStart "$SJSON" -u CLAUDE_TMUX_TITLE_CMD CLAUDE_TMUX_TITLE_LLM=0 "PATH=$tmp/noclaude"
run_hook UserPromptSubmit "$PJSON" -u CLAUDE_TMUX_TITLE_CMD CLAUDE_TMUX_TITLE_LLM=0 "PATH=$tmp/noclaude"
settle
assert_eq "0" "$status" "LLM=0 and no binary: exit 0"
assert_eq "" "$out$(errs)" "LLM=0 and no binary: no output"
assert_eq "proj" "$(window_name)" "LLM=0 and no binary: the base name stays"

# --- full run inside tmux: foreground is silent, whatever the model does ---
for mode in name fail; do
    new_session
    rm -f "$tmp/err"
    if [ "$mode" = name ]; then reply "nombre del modelo"; else touch "$FAKE/fail"; fi
    run_hook UserPromptSubmit "$PJSON" "PATH=$PATH"
    wait_calls_ge 1
    settle
    assert_eq "0" "$status" "model answering ($mode): exit 0"
    assert_eq "" "$out$(errs)" "model answering ($mode): no stdout or stderr, also after the background work ends"
done
finish
