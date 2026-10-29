# Proposal

## Why

Dentro de tmux, la ventana de una sesión de Claude Code aparece en la barra de estado como `1:ld-linux-x86-64.so.2*`: `automatic-rename` usa `#{pane_current_command}` y, en GNU Guix, `claude` se ejecuta a través del cargador dinámico. El nombre no dice nada y con varias ventanas no se distingue cuál sesión trabaja, cuál espera input y cuál terminó. Es la primera integración del repositorio y, al ser solo shell, sirve también de esqueleto para fijar estructura y estrategia de tests.

## What Changes

- Nuevo plugin `tmux-window-title` que renombra la ventana de tmux de la sesión de Claude según lo que hace, mediante hooks de comando en shell POSIX.
- Mapa de eventos a nombre: `SessionStart` y `Stop` → `claude: idle`; `UserPromptSubmit` → `claude: <primeras palabras del prompt>`; `PreToolUse` → `claude: <Tool> <objetivo>`; `Notification` → `claude: ESPERA INPUT`; `SessionEnd` → restaura `automatic-rename`.
- El nombre se acota (~24 caracteres) y se sanea con una lista permitida de caracteres, porque el prompt puede contener secretos.
- El objetivo es siempre la ventana de Claude (`-t "$TMUX_PANE"`), no la activa. Sin `$TMUX_PANE` el hook sale sin error ni salida.
- Estructura del repositorio como marketplace con N plugins: `.claude-plugin/marketplace.json` en la raíz y `plugins/tmux-window-title/`.
- Tests contra un tmux real en un socket aislado (`tmux -L <socket>`), sin mocks.
- Sin cambios en `~/.tmux.conf` del usuario.

Fuera de alcance: título de pane / `pane-border-status`, servidor MCP, orquestación multi-agente, mods de function hooks (API TypeScript inestable) y el comportamiento "solo renombrar si hay un único pane" (con varios panes en una ventana gana el último evento).

## Capabilities

### New Capabilities
- `tmux-window-title`: nombre de la ventana de tmux que refleja la actividad de la sesión de Claude Code y su restauración al terminar.

### Modified Capabilities

## Impact

- Código nuevo: `.claude-plugin/marketplace.json`, `plugins/tmux-window-title/` (manifiesto, `hooks/hooks.json`, script `set-title.sh`) y sus tests.
- Se actualiza `CLAUDE.md` con lenguaje (POSIX sh), estructura y comando de tests, hoy marcados como pendientes.
- Dependencias: `tmux` ≥ 3.x en el PATH; nada más.
- Convive con los hooks que el usuario ya tiene en `PreToolUse` y `PostToolUse` (`tdd-gate.sh`): los hooks de un plugin se suman a los de `settings.json`, sin sustituirlos (por confirmar en la verificación).
- Coste en `PreToolUse`: se ejecuta en cada tool; hay que medir la latencia del hook.
