# claude-tmux-integrations

A [Claude Code](https://claude.com/claude-code) plugin marketplace with
integrations between Claude Code and tmux. Each integration is a separate
plugin under `plugins/`.

## Plugins

| Plugin | What it does |
| ------ | ------------ |
| [`tmux-window-title`](plugins/tmux-window-title/README.md) | Names the tmux window of each Claude Code session after the topic of the session (project and branch first, then a short summary written by a small model), so you can tell many sessions apart in the status bar. |

## Install

Inside Claude Code:

```
/plugin marketplace add horellana/claude-tmux-integrations
/plugin install tmux-window-title@claude-tmux-integrations
```

Requirements, configuration, privacy and known limitations are in the plugin's
README. Note that the plugin sends the start of your prompts to the Claude API
to write the window name; it can be turned off with `CLAUDE_TMUX_TITLE_LLM=0`.

## Status

- Developed and tested on Linux with tmux 3.8.
- The test suite and shellcheck pass on `ubuntu-latest` and `macos-latest` in
  GitHub Actions (`.github/workflows/test.yml`). The macOS runner's tmux
  version was not recorded, and no real Claude session has been run on macOS
  (the tests use a fake `claude`).
- The install commands above were tried on Linux with an isolated Claude Code
  config: the marketplace was added, the plugin installed, and the installed
  hook ran against a real tmux. A full Claude session with the installed copy
  was not run.

## Development

POSIX `sh` plus `jq`; the tests use a real tmux server on an isolated socket and
a fake `claude` binary, so they need no network.

```
sh tests/run.sh
shellcheck plugins/tmux-window-title/hooks/set-title.sh tests/*.sh
```

On GNU Guix, `manifest.scm` and `.envrc` provide tmux, jq and shellcheck
(`guix shell -m manifest.scm`).

Changes are planned and recorded with OpenSpec
under `openspec/` (current specs in `openspec/specs/`, finished changes in
`openspec/changes/archive/`).

## License

[MIT](LICENSE)
