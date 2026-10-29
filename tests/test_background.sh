#!/bin/sh
# Background evaluation: one flight per pane, time limit, discard after SessionEnd (task 3.5).
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/lib_refine.sh"
tmux_start
refine_setup

# --- a single flight per pane ---
new_session
export CLAUDE_TMUX_TITLE_EVERY=1
reply "tema uno"
printf 2 > "$FAKE/sleep"
prompt "primer prompt que lanza la evaluacion"
wait_calls_ge 1
[ -d "$LOCK" ]
assert_eq "0" "$?" "a lock directory exists while the evaluation is in flight"
lockpid=$(cat "$LOCK"/* 2>/dev/null)
case $lockpid in '' | *[!0-9]*) r=1 ;; *) r=0 ;; esac
assert_eq "0" "$r" "the lock holds a numeric pid (got [$lockpid])"
kill -0 "$lockpid" 2>/dev/null
assert_eq "0" "$?" "the pid in the lock is alive while the evaluation runs"
prompt "segundo prompt mientras hay otra evaluacion"
assert_eq "0" "$?" "a prompt during an evaluation: hook exits 0"
wait_name "tema uno"
settle
assert_eq "1" "$(calls)" "a prompt during an evaluation does not launch a second one"
assert_eq "tema uno" "$(window_name)" "the evaluation in flight still applies its name"
[ ! -e "$LOCK" ]
assert_eq "0" "$?" "the lock is released when the evaluation ends"
unset CLAUDE_TMUX_TITLE_EVERY

# --- a hung model is killed at the time limit ---
new_session
export CLAUDE_TMUX_TITLE_TIMEOUT=2
touch "$FAKE/hang"
prompt "este modelo se queda colgado para siempre"
assert_eq "0" "$?" "hung model: hook exits 0"
wait_calls_ge 1
pid=$(cat "$FAKE/pid.1" 2>/dev/null)
kill -0 "$pid" 2>/dev/null
assert_eq "0" "$?" "hung model: the model process is running before the limit"
wait_until is_dead "$pid"
is_dead "$pid"
assert_eq "0" "$?" "hung model: the process is gone after CLAUDE_TMUX_TITLE_TIMEOUT (no orphan)"
settle
assert_eq "proj" "$(window_name)" "hung model: the name does not change"
[ ! -e "$LOCK" ]
assert_eq "0" "$?" "hung model: no lock left behind"
assert_eq "1" "$(calls)" "hung model: no retry"
unset CLAUDE_TMUX_TITLE_TIMEOUT

# --- a late answer after SessionEnd is discarded ---
new_session mine
reply "tema tardio"
printf 2 > "$FAKE/sleep"
prompt "prompt cuya respuesta llega tarde"
wait_calls_ge 1
fire SessionEnd '{}'
assert_eq "mine" "$(window_name)" "late answer: SessionEnd restores the previous name"
wait_until file_exists "$FAKE/done.1"
settle
assert_eq "mine" "$(window_name)" "late answer: the restored name is kept"
assert_eq "" "$(opt @claude_prev_auto)" "late answer: session state is not resurrected"

# --- stale and live locks ---
new_session
mkdir -p "$LOCKDIR"
deadpid=$(sh -c 'echo $$')
mkdir "$LOCK"
echo "$deadpid" > "$LOCK/pid"
reply "tema nuevo"
prompt "prompt que encuentra un cerrojo viejo"
wait_name "tema nuevo"
settle
assert_eq "tema nuevo" "$(window_name)" "a lock whose pid is dead is replaced"
assert_eq "1" "$(calls)" "stale lock: the model was invoked once"
[ ! -e "$LOCK" ]
assert_eq "0" "$?" "stale lock: released afterwards"

new_session
mkdir -p "$LOCKDIR"
mkdir "$LOCK"
echo "$$" > "$LOCK/pid"
reply "tema ajeno"
prompt "prompt que encuentra un cerrojo vivo"
assert_eq "0" "$?" "live lock: hook exits 0"
sleep 0.5
assert_eq "0" "$(calls)" "a lock whose pid is alive blocks a second evaluation"
assert_eq "proj" "$(window_name)" "live lock: the name does not change"
[ -d "$LOCK" ]
assert_eq "0" "$?" "live lock: another evaluation's lock is left alone"
rm -rf "$LOCK"
finish
