#!/bin/sh
# Name the tmux window of this pane after Claude Code's activity.
# Usage: set-title.sh <EVENT>, hook JSON on stdin. Cosmetic: always exits 0, silent.
exec >/dev/null 2>&1
event=${1:-}
pane=${TMUX_PANE:-}
[ -n "$pane" ] || exit 0

if [ "$event" = SessionEnd ]; then
    prev_auto=$(tmux show-options -w -v -t "$pane" @claude_prev_auto)
    prev_name=$(tmux show-options -w -v -t "$pane" @claude_prev_name)
    case $prev_auto in
        1) tmux set-window-option -t "$pane" automatic-rename on ;;
        0) tmux rename-window -t "$pane" -- "$prev_name" ;;
        *) exit 0 ;;
    esac
    tmux set-option -w -u -t "$pane" @claude_prev_auto
    tmux set-option -w -u -t "$pane" @claude_prev_name
    exit 0
fi

case $event in
    SessionStart | Stop) text=idle ;;
    Notification) text='ESPERA INPUT' ;;
    UserPromptSubmit | PreToolUse)
        command -v jq || exit 0
        # shellcheck disable=SC2016 # $n and $i are jq variables
        if [ "$event" = UserPromptSubmit ]; then
            filter='.prompt // "" | strings'
        else
            filter='(.tool_name // "" | strings) as $n
                | ((.tool_input | objects) // {}) as $i
                | (if $n == "Edit" or $n == "Write" or $n == "Read"
                    then ([$i.file_path | strings | split("/") | last][0] // "")
                  elif $n == "Bash"
                    then ([$i.command | strings | [splits("\\s+") | select(. != "")] | .[0:2] | join(" ")][0] // "")
                  else "" end) as $t
                | $n + (if ($t // "") != "" then " " + $t else "" end)'
        fi
        text=$(head -c 1048576 | jq -r "$filter" | head -c 512) || exit 0
        ;;
    *) exit 0 ;;
esac

name=$(printf 'claude: %s' "$text" | tr -cd 'A-Za-z0-9 ._:/-' | cut -c1-24)

if [ -z "$(tmux show-options -w -v -t "$pane" @claude_prev_auto)" ]; then
    auto=$(tmux display-message -p -t "$pane" '#{automatic-rename}') || exit 0
    cur=$(tmux display-message -p -t "$pane" '#{window_name}')
    tmux set-option -w -t "$pane" @claude_prev_auto "$auto"
    tmux set-option -w -t "$pane" @claude_prev_name "$cur"
fi
tmux rename-window -t "$pane" -- "$name"
exit 0
