#!/bin/sh
# Window title per Claude Code hook event (tasks 2.1-2.5).
. "$(dirname "$0")/lib.sh"
HOOK=$(cd "$(dirname "$0")/.." && pwd)/plugins/tmux-window-title/hooks/set-title.sh
tmux_start

# fire EVENT JSON [PANE]
fire() { printf '%s' "$2" | TMUX_PANE="${3:-$TMUX_PANE}" sh "$HOOK" "$1" >/dev/null 2>&1; }
prompt_json() { jq -n --arg p "$1" '{hook_event_name:"UserPromptSubmit",prompt:$p}'; }
tool_json() { jq -nc --arg n "$1" --argjson i "$2" '{hook_event_name:"PreToolUse",tool_name:$n,tool_input:$i}'; }

fire SessionStart '{"hook_event_name":"SessionStart"}'
assert_eq "claude: idle" "$(window_name)" "session start names the window idle"

fire UserPromptSubmit "$(prompt_json 'hola mundo')"
assert_eq "claude: hola mundo" "$(window_name)" "short prompt is shown whole after the prefix"

fire Stop '{"hook_event_name":"Stop"}'
assert_eq "claude: idle" "$(window_name)" "stop names the window idle"

fire UserPromptSubmit "$(prompt_json 'arregla el bug del login en auth.ts')"
assert_eq "claude: arregla el bug d" "$(window_name)" "long prompt is truncated so the whole name is 24 chars"

fire PreToolUse "$(tool_json Edit '{"file_path":"src/foo.ts"}')"
assert_eq "claude: Edit foo.ts" "$(window_name)" "Edit shows the basename of file_path"

fire PreToolUse "$(tool_json Read '{"file_path":"/a/b/x.md"}')"
assert_eq "claude: Read x.md" "$(window_name)" "Read shows the basename of file_path"

fire PreToolUse "$(tool_json Bash '{"command":"ls -la /tmp"}')"
assert_eq "claude: Bash ls -la" "$(window_name)" "Bash shows the first two words of the command"

fire PreToolUse "$(tool_json Bash '{"command":"npm test --watch"}')"
assert_eq "claude: Bash npm test" "$(window_name)" "Bash npm test --watch shows the first two words"

fire PreToolUse "$(tool_json Grep '{"pattern":"x"}')"
assert_eq "claude: Grep" "$(window_name)" "unknown tool shows only its name"

fire PreToolUse "$(tool_json Edit '{}')"
assert_eq "claude: Edit" "$(window_name)" "tool without target shows only its name"

fire PreToolUse '{"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":"garbage"}'
assert_eq "claude: Edit" "$(window_name)" "unusable tool_input shows only the tool name"

fire Stop '{}'
printf '%s' 'this is { not json' | sh "$HOOK" PreToolUse >/dev/null 2>&1
assert_eq "0" "$?" "unreadable JSON exits 0"

fire Notification '{"hook_event_name":"Notification","message":"Claude needs your permission"}'
assert_eq "claude: ESPERA INPUT" "$(window_name)" "notification names the window ESPERA INPUT"

# Two windows, focus on window 2, event from window 1.
fire Stop '{}'
w1=$TMUX_PANE
w2=$(t new-window -d -P -F '#{pane_id}')
t select-window -t "$w2"
t rename-window -t "$w2" -- other
fire UserPromptSubmit "$(prompt_json 'work')" "$w1"
assert_eq "claude: work" "$(window_name "$w1")" "event renames the window of its own pane"
assert_eq "other" "$(window_name "$w2")" "focused window that did not emit the event keeps its name"
fire Notification '{}' "$w2"
assert_eq "claude: work" "$(window_name "$w1")" "each window keeps the state of its own session"
assert_eq "claude: ESPERA INPUT" "$(window_name "$w2")" "second window shows its own state"

# Two panes in one window: last event wins.
pb=$(t split-window -d -t "$w1" -P -F '#{pane_id}')
fire Stop '{}' "$w1"
fire Notification '{}' "$pb"
assert_eq "claude: ESPERA INPUT" "$(window_name "$w1")" "second pane event wins over earlier first pane event"
fire Stop '{}' "$w1"
assert_eq "claude: idle" "$(window_name "$w1")" "later event from first pane wins again"
finish
