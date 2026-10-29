# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Estado del proyecto

Objetivo: alojar N integraciones entre Claude (Claude Code) y tmux. Entorno: Linux (GNU Guix), tmux 3.8. No es un repo git todavía (sin ramas de integración/producción definidas).

Primera integración: plugin `tmux-window-title` (renombra la ventana de tmux según la actividad de Claude; ver su `README.md`).

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
tests/{lib.sh,run.sh,test_*.sh}
manifest.scm + .envrc     # entorno Guix: tmux, jq, shellcheck
.shellcheckrc
```

## Tests y lint

- Tests: `sh tests/run.sh`. Usan tmux real en un socket aislado (`tmux -L <socket>`), sin mocks; cada test mata su servidor al terminar.
- Lint: `guix shell -m manifest.scm -- shellcheck plugins/tmux-window-title/hooks/set-title.sh tests/*.sh`

## Flujo de trabajo: OpenSpec (spec-driven)

- Configuración en `openspec/config.yaml` (`schema: spec-driven`; sin contexto ni reglas por artefacto definidos aún).
- `openspec/specs/` = specs vigentes. `openspec/changes/` = cambios en curso; `openspec/changes/archive/` = cambios terminados.
- Los cambios se gestionan con los skills/comandos de `.claude/`: `/opsx:propose`, `/opsx:explore`, `/opsx:apply`, `/opsx:update`, `/opsx:sync`, `/opsx:archive` (y los skills `openspec-*` equivalentes). Propón el cambio antes de implementar.
