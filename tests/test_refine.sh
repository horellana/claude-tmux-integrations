#!/bin/sh
# Topic refinement by the model, in the background (task 3.1).
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/lib_refine.sh"
tmux_start
refine_setup

# --- first substantial prompt renames with the model's answer ---
new_session
reply "pagos: timeout cobro"
prompt "arregla el timeout al cobrar con tarjeta en el servicio de pagos"
wait_name "pagos: timeout cobro"
assert_eq "pagos: timeout cobro" "$(window_name)" "first substantial prompt renames the window with the model's answer"
assert_eq "pagos: timeout cobro" "$(opt @claude_title)" "@claude_title records the name the plugin set"
assert_eq "1" "$(calls)" "the model is invoked exactly once for the first prompt"

# --- how the model is invoked ---
assert_eq "8" "$(cat "$FAKE/argc.1" 2>/dev/null)" "model gets exactly 8 arguments"
assert_eq "-p" "$(cat "$FAKE/arg.1.1" 2>/dev/null)" "argument 1 is -p"
assert_eq "--model" "$(cat "$FAKE/arg.1.2" 2>/dev/null)" "argument 2 is --model"
assert_eq "haiku" "$(cat "$FAKE/arg.1.3" 2>/dev/null)" "argument 3 is haiku"
assert_eq "--tools" "$(cat "$FAKE/arg.1.4" 2>/dev/null)" "argument 4 is --tools"
assert_eq "" "$(cat "$FAKE/arg.1.5" 2>/dev/null)" "argument 5 is the empty tool list"
[ -f "$FAKE/arg.1.5" ]
assert_eq "0" "$?" "the empty tool list is passed as a real (empty) argument"
assert_eq "--no-session-persistence" "$(cat "$FAKE/arg.1.6" 2>/dev/null)" "argument 6 is --no-session-persistence"
assert_eq "--disable-slash-commands" "$(cat "$FAKE/arg.1.7" 2>/dev/null)" "argument 7 is --disable-slash-commands"
assert_eq "proj" "$(sent_name 1)" "the text carries the current window name"
assert_eq "arregla el timeout al cobrar con tarjeta en el servicio de pagos" "$(sent_prompt 1)" "a short prompt is sent intact between <prompt> and </prompt>"
assert_eq "" "$(cat "$FAKE/stdin.1" 2>/dev/null)" "the model's stdin is empty (/dev/null)"
[ -f "$FAKE/stdin.1" ]
assert_eq "0" "$?" "the model was started and read its stdin to the end"

# --- the current name follows the rename ---
settle
export CLAUDE_TMUX_TITLE_EVERY=1
prompt "ahora documenta la API de pagos con ejemplos"
wait_calls_ge 2
assert_eq "pagos: timeout cobro" "$(sent_name 2)" "a later evaluation sends the name set before"
settle
unset CLAUDE_TMUX_TITLE_EVERY

# --- KEEP leaves the name ---
for k in KEEP keep "  Keep  "; do
    new_session
    reply "$k"
    prompt "sigue trabajando en lo mismo de antes"
    wait_calls_ge 1
    settle
    assert_eq "1" "$(calls)" "[$k]: the model was asked"
    assert_eq "proj" "$(window_name)" "[$k]: answer KEEP leaves the name"
done

# --- the hook returns before a slow model answers ---
new_session
reply "tema lento"
printf 2 > "$FAKE/sleep"
t0=$(date +%s)
prompt "tarea larga que tarda en resumirse"
rc=$?
t1=$(date +%s)
elapsed=$((t1 - t0))
assert_eq "0" "$rc" "slow model: hook exits 0"
[ "$elapsed" -le 1 ]
assert_eq "0" "$?" "slow model: hook returned without waiting for the 2 s model (took ${elapsed}s)"
assert_eq "proj" "$(window_name)" "slow model: name unchanged when the hook returns"
wait_name "tema lento"
assert_eq "tema lento" "$(window_name)" "slow model: the name is applied once the model answers"
settle

# --- model failure leaves the name ---
new_session
touch "$FAKE/fail"
prompt "esto hace fallar al modelo con error"
rc=$?
wait_calls_ge 1
settle
assert_eq "0" "$rc" "failing model: hook exits 0"
assert_eq "1" "$(calls)" "failing model: the model was invoked"
assert_eq "proj" "$(window_name)" "failing model: name unchanged"

# --- missing binary leaves the base name ---
new_session
CLAUDE_TMUX_TITLE_CMD=$FAKE/does-not-exist
export CLAUDE_TMUX_TITLE_CMD
prompt "el binario del modelo no existe aqui"
assert_eq "0" "$?" "CMD does not exist: hook exits 0"
settle
assert_eq "proj" "$(window_name)" "CMD does not exist: base name kept"

new_session
NOCLAUDE=$RT/nopath
make_path_without claude "$NOCLAUDE"
json=$(jq -nc --arg p "no hay claude en el PATH" --arg c "$PROJ" '{prompt:$p,cwd:$c}')
out=$(printf '%s' "$json" | env -u CLAUDE_TMUX_TITLE_CMD "PATH=$NOCLAUDE" "$(command -v sh)" "$HOOK" UserPromptSubmit 2>&1)
rc=$?
settle
assert_eq "0" "$rc" "no claude on PATH: hook exits 0"
assert_eq "" "$out" "no claude on PATH: no output"
assert_eq "proj" "$(window_name)" "no claude on PATH: base name kept"
finish
