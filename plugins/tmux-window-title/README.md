# tmux-window-title

A Claude Code plugin that names the tmux window running your Claude session
after the topic of the session, so you can tell sessions apart from the status
bar. The name describes what the session is about; it never shows activity
state (idle, tool in use, waiting for input). When the session ends, the
window goes back to how it was before.

How the name is built:

1. On `SessionStart`, the window gets an immediate base name: the project
   folder (git root, or the working directory if there is no repository),
   followed by the git branch when it is not `main` or `master`. For example
   `api-pagos fix/timeout`, or `notas` outside a repository.
2. In the background, a small model refines it. On the first substantial
   prompt, and then every N-th substantial prompt (N = 3 by default), the
   plugin runs `claude -p --model haiku ...` with the current name and the
   start of the prompt. The model answers either `KEEP` (the name stays) or a
   new name of at most 28 characters. An unusable answer leaves the name as it
   is.

A prompt is substantial when it does not start with `/` and has at least 10
characters.

## Install

```
/plugin install tmux-window-title --marketplace horellana/claude-tmux-integrations
```

## Requirements

- `tmux`, with Claude Code running inside it (the plugin uses `$TMUX_PANE`).
- `jq`, to read the hook JSON. Without `jq` the base name falls back to the
  hook's working directory (`$PWD`) and the model refinement does nothing.
- `git` (optional), for the repository root and branch in the base name.
  Without it the name is the folder name.
- `claude` in the `PATH` (optional), for the model refinement. Without it
  the window keeps its base name.

On macOS, install the dependencies with Homebrew: `brew install tmux jq`.
macOS has not been tested (see "Not verified").

Outside tmux, with a failing tmux or any other error, the hook exits with code
0 and prints nothing, so it never interrupts Claude. It does not emit
permission decisions or alter tool input.

## Events

| Event              | What the plugin does                                              |
| ------------------ | ----------------------------------------------------------------- |
| `SessionStart`     | Saves the window's previous state and sets the base name.         |
| `UserPromptSubmit` | Counts substantial prompts; when one is due, starts the background refinement and returns at once. |
| `SessionEnd`       | Restores the window (see below).                                  |

No other events are hooked. Tool use, notifications and turn endings do not
change the name.

The name is at most 28 characters. Only the characters `A-Za-z0-9 ._:/-` are
kept, in both the base name and the model's answer; everything else is
dropped, so tmux never expands formats such as `#{...}`. Only the first line of
the model's answer is used, and an answer starting with `-` is ignored.

## Configuration

All variables are optional and are read from the environment of the Claude
Code process.

| Variable                    | Default  | Effect |
| --------------------------- | -------- | ------ |
| `CLAUDE_TMUX_TITLE_LLM`     | unset    | Set to `0` to disable the model: the window keeps its base name and `claude` is never invoked. Any other value leaves it enabled. |
| `CLAUDE_TMUX_TITLE_EVERY`   | `3`      | Evaluate on the first substantial prompt and then every N-th one. An invalid value (not a positive integer) falls back to 3. |
| `CLAUDE_TMUX_TITLE_TIMEOUT` | `30`     | Seconds to wait for the model before giving up (no retries). An invalid value falls back to 30. |
| `CLAUDE_TMUX_TITLE_CMD`     | `claude` | Command used to call the model. Meant for tests and unusual installs. |
| `CLAUDE_TMUX_TITLE_BG`      | unset    | Internal. The plugin sets it on the model's process so that, if that process fires hooks, `set-title.sh` exits immediately instead of recursing. Do not set it yourself: while it is set the plugin does nothing. |

## Manual renames

The plugin remembers the last name it set (window option `@claude_title`). When
a model answer is about to be applied and the window name is different, you
renamed the window: the plugin sets `@claude_manual`, does not apply the
answer, and does not evaluate again for the rest of the session. The rename is
noticed when the model answers, not at the moment you rename. A new
`SessionStart` in the same window clears this and names it again.

## Background work

- One evaluation at a time per pane. A prompt that arrives while another
  evaluation is running is not evaluated (the prompt still counts toward N).
  The lock is a directory in `${TMPDIR:-/tmp}/claude-tmux-title-<uid>/`; a lock
  whose process is gone is replaced.
- Time limit of `CLAUDE_TMUX_TITLE_TIMEOUT` seconds, enforced by a watcher
  process; no retries. A failed or timed-out evaluation changes nothing.
- If the session ended before the model answered, the answer is discarded.

## Privacy and cost

Every evaluation sends the current window name and up to the first 500
characters of your prompt to the Claude API, using your own account, and
spends tokens of the small model. The plugin does nothing to hide secrets:
alphanumeric secrets in the prompt are sent like any other text (as the prompt
already is to the main session). The resulting name is also visible in the
status bar and in screenshots, and the allowlist removes symbols, not words,
so this is not a secrets control.

To avoid the model call entirely, set `CLAUDE_TMUX_TITLE_LLM=0`; only the
local base name is used.

## Restore on SessionEnd

Before the first rename, the plugin saves the window's `automatic-rename`
setting and name in the window options `@claude_prev_auto` and
`@claude_prev_name`. On `SessionEnd` it puts them back: if `automatic-rename`
was on it is turned on again; if it was off, the previous name is restored and
it stays off. Then all the `@claude_*` options are removed.

## Limitations

- Several panes in one window: the last one to write wins. Panes are not told
  apart, and the first `SessionEnd` restores the window even if another
  session is still running in it.
- Abrupt close (`kill -9`, closing the terminal) skips `SessionEnd`, so the
  window keeps its last name. To fix it by hand:
  `tmux set-window-option automatic-rename on`.
- Accents and any other character outside the allowlist are dropped
  (`canción` becomes `cancin`). The model is asked for ASCII; a folder name
  with accents loses them in the base name.

## Not verified

- Tested only on Linux with tmux 3.8. No minimum tmux version has been
  verified, so none is claimed.
- macOS has not been tested. A CI workflow (`.github/workflows/test.yml`)
  with a Linux and macOS matrix is proposed but has not been run on either.
- A real interactive Claude session has not been verified yet; the tests use
  a fake `claude` (`CLAUDE_TMUX_TITLE_CMD`). The check with the real `claude`
  is a separate step.
- The example name `pagos: timeout cobro` depends on what Haiku answers; the
  model may produce a different name, or one in another language.
- The time-limit watcher has a small possible race: if it is stopped in a
  narrow window it may leave a `sleep` process running until the limit
  expires. It has not been observed after the fix.
- Coexistence with other hooks you may have configured, for example in
  `settings.json`, was not verified.
