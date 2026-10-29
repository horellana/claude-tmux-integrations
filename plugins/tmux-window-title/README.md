# tmux-window-title

A Claude Code plugin that renames the tmux window running your Claude session
after what Claude is doing, so you can tell sessions apart from the status bar.
When the session ends, the window goes back to tmux's automatic naming.

## Install

```
/plugin install tmux-window-title --marketplace <owner>/<repo>
```

## Requirements

- `tmux`, with Claude Code running inside it (the plugin uses `$TMUX_PANE`).
- `jq`, to read the hook JSON. Without `jq` the hook does nothing.

Outside tmux, with `jq` missing, or if tmux fails, the hook exits with code 0
and prints nothing, so it never interrupts Claude. It does not emit permission
decisions or alter tool input.

## Event to name

| Event              | Window name                                             |
| ------------------ | ------------------------------------------------------- |
| `SessionStart`     | `claude: idle`                                          |
| `UserPromptSubmit` | `claude: <start of the prompt>`                         |
| `PreToolUse`       | `claude: Edit foo.ts` (`Edit`/`Write`/`Read`: file basename), `claude: Bash npm test` (`Bash`: first two words), or just the tool name |
| `Notification`     | `claude: ESPERA INPUT`                                  |
| `Stop`             | `claude: idle`                                          |
| `SessionEnd`       | restores the window (see below)                         |

The name is at most 24 characters, including the `claude: ` prefix. Only the
characters `A-Za-z0-9 ._:/-` are kept; everything else is dropped, so tmux
never expands formats such as `#{...}`.

## Restore on SessionEnd

Before the first rename, the plugin saves the window's `automatic-rename`
setting and name in the window options `@claude_prev_auto` and
`@claude_prev_name`. On `SessionEnd` it puts them back: if `automatic-rename`
was on it is turned on again; if it was off, the previous name is restored and
it stays off. The `@claude_*` options are then removed.

## Limitations

- Several panes in one window: the last event wins. Panes are not told apart,
  and the first `SessionEnd` restores the window even if another session is
  still running in it.
- Abrupt close (`kill -9`, closing the terminal) skips `SessionEnd`, so the
  window keeps its last name. To fix it by hand:
  `tmux set-window-option automatic-rename on`.
- Alphanumeric secrets in the prompt are shown. The allowlist removes symbols,
  not words, so the first words of your prompt appear in the status bar and in
  screenshots. This is not a secrets control.
- Accents and any other character outside the allowlist are dropped
  (`canción` becomes `cancin`).

## Not verified

- `Notification` (`claude: ESPERA INPUT`) and `Stop` (back to `claude: idle`)
  were not observed in a real interactive session.
- Coexistence with other hooks you may have configured, for example in
  `settings.json`, was not verified.
