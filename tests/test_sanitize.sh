#!/bin/sh
# Sanitising of window names and of what is sent to the model (task 3.3).
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/lib_refine.sh"
tmux_start
refine_setup

PROMPT="refactor the payment retry logic please"

# check_name DESCRIPTION : length and alphabet of the current window name.
check_name() {
    name=$(window_name)
    len=${#name}
    [ "$len" -le 28 ]; assert_eq "0" "$?" "$1: at most 28 chars (got $len)"
    rest=$(printf '%s' "$name" | LC_ALL=C tr -d 'A-Za-z0-9 ._:/-')
    assert_eq "" "$rest" "$1: only allowed characters"
}

# model_case DESCRIPTION MODEL_OUTPUT EXPECTED_NAME : the model answers MODEL_OUTPUT.
model_case() {
    new_session
    reply "$2"
    prompt "$PROMPT"
    wait_calls_ge 1
    if [ "$3" != proj ]; then wait_name "$3"; fi
    settle
    assert_eq "1" "$(calls)" "model output $1: the model was asked"
    assert_eq "$3" "$(window_name)" "model output $1: resulting name"
    check_name "model output $1"
}

model_case "plain topic" "pagos: timeout cobro" "pagos: timeout cobro"
model_case "no claude: prefix" "Docs API" "Docs API"
model_case "newline keeps the first line only" "$(printf 'Docs API\nignored second line')" "Docs API"
model_case "leading empty line" "$(printf '\nSecond line')" "proj"
model_case "escape sequences" "$(printf '\033[31mred\033[0m')" "31mred0m"
model_case "only an escape" "$(printf '\033')" "proj"
model_case "tmux formats" '#{pane_id} #(id) #[fg=red]' "pane_id id fgred"
model_case "leading dash is discarded" "-x" "proj"
model_case "leading dash with words is discarded" "-t foo" "proj"
model_case "empty" "" "proj"
model_case "only spaces" "   " "proj"
model_case "only disallowed characters" '#{}$()=@!%^&*' "proj"
model_case "secret-like symbols" 'sk-ant-abc123= p@ss$word' "sk-ant-abc123 pssword"
model_case "long name is cut to 28" "abcdefghijabcdefghijabcdefghijabcdefghij" "abcdefghijabcdefghijabcdefgh"

# Command substitution in model output or prompt is never executed.
new_session
reply "\$(touch $RT/pwned) \`touch $RT/pwned2\`"
prompt "\$(touch $RT/pwned3) \`touch $RT/pwned4\` and more words"
wait_calls_ge 1
settle
[ ! -e "$RT/pwned" ] && [ ! -e "$RT/pwned2" ] && [ ! -e "$RT/pwned3" ] && [ ! -e "$RT/pwned4" ]
assert_eq "0" "$?" "command substitution in the prompt or the model output is never executed"
check_name "command substitution in model output"

# --- the base name goes through the same sanitising ---
CLAUDE_TMUX_TITLE_LLM=0
export CLAUDE_TMUX_TITLE_LLM
base_case() { # DESCRIPTION DIRNAME EXPECTED
    fire SessionEnd '{}'
    mkdir "$RT/$2" || return 1
    PROJ=$RT/$2
    start_session
    assert_eq "$3" "$(window_name)" "base name $1: resulting name"
    check_name "base name $1"
    rm -rf "$RT/${2:?}"
}
base_case "tmux format" 'p#{pane_id}x' "ppane_idx"
base_case "secret-like symbols" 'sk-ant-abc123=p@ss$word' "sk-ant-abc123pssword"
base_case "newline" "$(printf 'a\nb')" "ab"
base_case "escape" "$(printf 'a\033[31mb')" "a31mb"
base_case "long name" "aaaaaaaaaabbbbbbbbbbccccccccccddddddddddeeeeeeeeee" "aaaaaaaaaabbbbbbbbbbcccccccc"
unset CLAUDE_TMUX_TITLE_LLM
PROJ=$RT/proj

# --- what is sent to the model ---
new_session
long=$(awk 'BEGIN{for(i=0;i<5000;i++)printf "a"; printf "ZZZEND"}')
prompt "$long"
wait_calls_ge 1
settle
sent=$(sent_prompt 1)
assert_eq "500" "${#sent}" "a 5000-character prompt is cut to 500 characters between <prompt> and </prompt>"
assert_eq "$(printf 'a%.0s' $(seq 1 500))" "$sent" "the 500 characters are the start of the prompt"
if contains "$FAKE/arg.1.8" ZZZEND; then r=1; else r=0; fi
assert_eq "0" "$r" "no character past the 500th reaches the model"

new_session
prompt "ayuda con el despliegue del servicio"
wait_calls_ge 1
settle
assert_eq "8" "$(cat "$FAKE/argc.1" 2>/dev/null)" "only the fixed flags and the text are passed as arguments"
for secret in "sess-SECRET-123" "$RT" "$TMUX_PANE" "UserPromptSubmit" "permission_mode"; do
    all=
    for f in "$FAKE"/arg.1.*; do all="$all$(cat "$f")"; done
    case $all in *"$secret"*) r=1 ;; *) r=0 ;; esac
    assert_eq "0" "$r" "the text sent to the model does not contain [$secret]"
done
assert_eq "proj" "$(sent_name 1)" "the current window name is sent"
assert_eq "ayuda con el despliegue del servicio" "$(sent_prompt 1)" "the prompt is sent"
finish
