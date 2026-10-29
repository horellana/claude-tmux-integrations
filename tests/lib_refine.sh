#!/bin/sh
# Helpers for tests that drive set-title.sh with a fake model binary.
# Source after lib.sh and tmux_start, then call refine_setup:
#   . "$(dirname "$0")/lib.sh"; . "$(dirname "$0")/lib_refine.sh"
#   tmux_start; refine_setup
# Not named test_*.sh, so tests/run.sh does not run it.
#
# The fake model ($FAKE/claude, selected through CLAUDE_TMUX_TITLE_CMD) records, per
# invocation number N (1-based): $FAKE/calls (one line per call), arg.N.I (argument I,
# verbatim), argc.N, stdin.N, env.N, pid.N and done.N (written after it answered).
# Its behaviour comes from files in $FAKE: reply (stdout, verbatim), sleep (seconds
# before answering), hang (never answers; sleeps 300 s), fail (error, no stdout).

HOOK=$(cd "$(dirname "$0")/.." && pwd)/plugins/tmux-window-title/hooks/set-title.sh

refine_setup() {
    RT=$(mktemp -d "${TMPDIR:-/tmp}/claude-title-refine.XXXXXX")
    FAKE=$RT/fake
    PROJ=$RT/proj # base name of the session is "proj"
    mkdir "$FAKE" "$RT/tmp" "$PROJ"
    cat > "$FAKE/claude" <<'FAKE_EOF'
#!/bin/sh
d=$CLAUDE_FAKE_DIR
date +%s >> "$d/calls"
n=$(wc -l < "$d/calls" | tr -d ' ')
echo $$ > "$d/pid.$n"
i=0
for a in "$@"; do
    i=$((i + 1))
    printf '%s' "$a" > "$d/arg.$n.$i"
done
printf '%s' "$i" > "$d/argc.$n"
cat > "$d/stdin.$n"
env > "$d/env.$n"
if [ -f "$d/hang" ]; then exec sleep 300; fi
if [ -f "$d/sleep" ]; then sleep "$(cat "$d/sleep")"; fi
if [ -f "$d/fail" ]; then echo "model exploded" >&2; exit 1; fi
cat "$d/reply"
: > "$d/done.$n"
exit 0
FAKE_EOF
    chmod +x "$FAKE/claude"
    printf KEEP > "$FAKE/reply"
    # Own TMPDIR: the hook's lock directory must not touch the shared /tmp.
    TMPDIR=$RT/tmp
    LOCKDIR=$TMPDIR/claude-tmux-title-$(id -u)
    LOCK=$LOCKDIR/$TMUX_PANE.lock
    CLAUDE_FAKE_DIR=$FAKE
    CLAUDE_TMUX_TITLE_CMD=$FAKE/claude
    unset CLAUDE_TMUX_TITLE_BG CLAUDE_TMUX_TITLE_LLM CLAUDE_TMUX_TITLE_EVERY CLAUDE_TMUX_TITLE_TIMEOUT
    export TMPDIR CLAUDE_FAKE_DIR CLAUDE_TMUX_TITLE_CMD
    trap refine_cleanup EXIT
}

refine_cleanup() {
    for f in "$FAKE"/pid.*; do
        [ -f "$f" ] && kill "$(cat "$f")" 2>/dev/null
    done
    rm -rf "$RT"
    tmux_stop
}

opt() { t show-options -w -v -t "$TMUX_PANE" "$1" 2>/dev/null; }

# fire EVENT JSON : run the hook, discarding output; status is the hook's.
fire() { printf '%s' "$2" | sh "$HOOK" "$1" >/dev/null 2>&1; }

start_session() {
    fire SessionStart "$(jq -nc --arg c "$PROJ" '{hook_event_name:"SessionStart",cwd:$c,session_id:"sess-SECRET-123"}')"
}

# prompt TEXT : UserPromptSubmit with TEXT.
prompt() {
    fire UserPromptSubmit "$(jq -nc --arg p "$1" --arg c "$PROJ" \
        '{hook_event_name:"UserPromptSubmit",prompt:$p,cwd:$c,session_id:"sess-SECRET-123",permission_mode:"default"}')"
}

reply() { printf '%s' "$1" > "$FAKE/reply"; }

reset_fake() {
    rm -f "$FAKE"/calls "$FAKE"/arg.* "$FAKE"/argc.* "$FAKE"/stdin.* "$FAKE"/env.* \
        "$FAKE"/pid.* "$FAKE"/done.* "$FAKE"/sleep "$FAKE"/hang "$FAKE"/fail
    printf KEEP > "$FAKE/reply"
}

# new_session [PRENAME] : clean slate (also for options older hooks do not clear),
# optionally rename the window to PRENAME first, then SessionStart.
# shellcheck disable=SC2120 # $1 is optional
new_session() {
    fire SessionEnd '{}'
    for o in @claude_n @claude_manual @claude_title @claude_prev_auto @claude_prev_name; do
        t set-option -w -u -t "$TMUX_PANE" "$o" 2>/dev/null
    done
    rm -rf "$LOCK"
    reset_fake
    unset CLAUDE_TMUX_TITLE_BG CLAUDE_TMUX_TITLE_LLM CLAUDE_TMUX_TITLE_EVERY CLAUDE_TMUX_TITLE_TIMEOUT
    [ -z "${1:-}" ] || t rename-window -t "$TMUX_PANE" -- "$1"
    start_session
}

# wait_until CMD... : poll up to 5 s (50 x 0.1 s) until CMD succeeds. After the first
# timeout the limit drops to 0.5 s: the test has already failed and the rest only
# needs to report it quickly.
WAIT_TICKS=50
wait_until() {
    i=0
    while [ "$i" -lt "$WAIT_TICKS" ]; do
        "$@" && return 0
        sleep 0.1
        i=$((i + 1))
    done
    WAIT_TICKS=5
    return 1
}

calls() {
    if [ -f "$FAKE/calls" ]; then wc -l < "$FAKE/calls" | tr -d ' '; else echo 0; fi
}
calls_ge() { [ "$(calls)" -ge "$1" ]; }
name_is() { [ "$(window_name)" = "$1" ]; }
lock_gone() { [ ! -e "$LOCK" ]; }
file_exists() { [ -e "$1" ]; }
is_dead() { ! kill -0 "$1" 2>/dev/null; }

wait_calls_ge() { wait_until calls_ge "$1"; }
wait_name() { wait_until name_is "$1"; }
# settle : the evaluation in flight (if any) has finished and had time to apply.
settle() { wait_until lock_gone; sleep 0.3; }

# sent_text N : the "-p" text of invocation N (the last of its 8 arguments).
sent_text() { cat "$FAKE/arg.$1.8" 2>/dev/null; }
# sent_prompt N : lines between <prompt> and </prompt> of invocation N.
sent_prompt() { awk '/^<\/prompt>$/{p=0} p{print} /^<prompt>$/{p=1}' "$FAKE/arg.$1.8" 2>/dev/null; }
# sent_name N : value of the "Current name:" line of invocation N.
sent_name() { awk '/^Current name: /{sub(/^Current name: /,""); print; exit}' "$FAKE/arg.$1.8" 2>/dev/null; }
# contains FILE STRING : STRING occurs verbatim in a line of FILE.
contains() { awk -v s="$2" 'index($0,s){f=1} END{exit !f}' "$1" 2>/dev/null; }

# make_path_without NAME DIR : DIR gets a symlink for every executable on PATH except NAME.
make_path_without() {
    mkdir -p "$2"
    oldifs=$IFS
    IFS=:
    for d in $PATH; do
        for f in "$d"/*; do
            b=${f##*/}
            [ "$b" = "$1" ] && continue
            [ -x "$f" ] && [ ! -d "$f" ] && [ ! -e "$2/$b" ] && ln -s "$f" "$2/$b"
        done
    done
    IFS=$oldifs
}
