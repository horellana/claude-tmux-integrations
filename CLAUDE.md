# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Estado del proyecto

Objetivo: alojar N integraciones entre Claude (Claude Code) y tmux. Entorno: Linux (GNU Guix), tmux 3.8. Es un repo git (rama `main`); las ramas de integración/producción aún no están definidas.

Primera integración: plugin `tmux-window-title` (nombra la ventana de tmux por el tema de la sesión, sin estados en el nombre: nombre base inmediato = carpeta/raíz git + rama si no es main/master, refinado en segundo plano con `claude -p --model haiku`; ver su `README.md`).

## Lenguaje y estructura

- Lenguaje: POSIX sh, con `jq` para leer el JSON de los hooks.
- Cada integración es un plugin de Claude Code en `plugins/<nombre>/`, listado en el marketplace de la raíz.

```
.claude-plugin/marketplace.json
plugins/tmux-window-title/
  .claude-plugin/plugin.json
  hooks/hooks.json
  hooks/set-title.sh
  README.md
tests/{lib.sh,lib_refine.sh,run.sh,test_*.sh}   # test_base_name, test_refine, test_cadence, test_manual, test_background, test_no_state_names, ...
.github/workflows/test.yml                     # CI: shellcheck + tests en ubuntu y macOS (no ejecutado aún)
manifest.scm + .envrc     # entorno Guix: tmux, jq, shellcheck
.shellcheckrc
LICENSE                   # MIT
```

## Tests y lint

- Tests: `sh tests/run.sh`. Usan tmux real en un socket aislado (`tmux -L <socket>`), sin mocks; cada test mata su servidor al terminar.
- Los tests del modelo usan un `claude` falso (`CLAUDE_TMUX_TITLE_CMD`), sin red; la verificación con el `claude` real es aparte (tarea 5.4 de `describe-tmux-window-title`).
- Lint: `guix shell -m manifest.scm -- shellcheck plugins/tmux-window-title/hooks/set-title.sh tests/*.sh`

## Variables de entorno del plugin

- `CLAUDE_TMUX_TITLE_LLM=0` desactiva el modelo (queda el nombre base); `CLAUDE_TMUX_TITLE_EVERY` (3) y `CLAUDE_TMUX_TITLE_TIMEOUT` (30 s) ajustan la cadencia y el tiempo límite; `CLAUDE_TMUX_TITLE_CMD` (`claude`) cambia el binario (lo usan los tests).
- `CLAUDE_TMUX_TITLE_BG` es interna: guarda contra recursión de hooks; no definirla a mano.

## Flujo de trabajo: OpenSpec (spec-driven)

- Configuración en `openspec/config.yaml` (`schema: spec-driven`; sin contexto ni reglas por artefacto definidos aún).
- `openspec/specs/` = specs vigentes. `openspec/changes/` = cambios en curso; `openspec/changes/archive/` = cambios terminados.
- Los cambios se gestionan con los skills/comandos de `.claude/`: `/opsx:propose`, `/opsx:explore`, `/opsx:apply`, `/opsx:update`, `/opsx:sync`, `/opsx:archive` (y los skills `openspec-*` equivalentes). Propón el cambio antes de implementar.
