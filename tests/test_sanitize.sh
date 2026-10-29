#!/bin/sh
# Sanitising of the window name (task 3.1).
. "$(dirname "$0")/lib.sh"
HOOK=$(cd "$(dirname "$0")/.." && pwd)/plugins/tmux-window-title/hooks/set-title.sh
tmux_start
tmp=$(mktemp -d)
trap 'tmux_stop; rm -rf "$tmp"' EXIT

# check DESCRIPTION PROMPT : fire the prompt, then verify length and alphabet.
check() {
    t rename-window -t "$TMUX_PANE" -- before
    jq -n --arg p "$2" '{hook_event_name:"UserPromptSubmit",prompt:$p}' |
        sh "$HOOK" UserPromptSubmit >/dev/null 2>&1
    name=$(window_name)
    len=${#name}
    [ "$len" -le 24 ]; assert_eq "0" "$?" "$1: at most 24 chars (got $len)"
    rest=$(printf '%s' "$name" | tr -d 'A-Za-z0-9 ._:/-')
    assert_eq "" "$rest" "$1: only allowed characters"
    case $name in "claude:"*) r=0 ;; *) r=1 ;; esac
    assert_eq "0" "$r" "$1: window was renamed with the claude: prefix (got [$name])"
}

long=$(printf 'abcdefghij%.0s' $(seq 1 20))
check "200 char prompt" "$long"
check "newlines" "$(printf 'line one\nline two\n\nline three')"
check "tmux format" '#{pane_id} #{session_name} #(id) #[fg=red]'
check "command substitution" "\$(touch $tmp/pwned) \`touch $tmp/pwned2\`"
check "quotes" "it's \"quoted\" 'single' \"double\""
check "escape sequences" "$(printf '\033[31mred\033[0m \033]0;title\007 bell')"
check "leading dash" "-t foo -n bar"
check "only disallowed chars" '#{}$()=@!%^&*'
check "secret symbols" 'sk-ant-abc123= p@ss$word'

[ ! -e "$tmp/pwned" ] && [ ! -e "$tmp/pwned2" ]
assert_eq "0" "$?" "command substitution in the prompt is never executed"

t rename-window -t "$TMUX_PANE" -- before
jq -n '{prompt:"#{session_name}"}' | sh "$HOOK" UserPromptSubmit >/dev/null 2>&1
n=$(window_name)
[ "$n" != "claude: test" ] && [ "$n" != "test" ]
assert_eq "0" "$?" "tmux does not expand #{session_name} (got [$n])"

jq -n '{prompt:"p@ss$word sk=1"}' | sh "$HOOK" UserPromptSubmit >/dev/null 2>&1
n=$(window_name)
case $n in *@*|*\$*|*=*) r=1 ;; *) r=0 ;; esac
assert_eq "0" "$r" "secret-like symbols do not appear (got [$n])"

jq -n '{prompt:"-t foo"}' | sh "$HOOK" UserPromptSubmit >/dev/null 2>&1
assert_eq "claude: -t foo" "$(window_name)" "prompt starting with a dash is taken as text"
finish
