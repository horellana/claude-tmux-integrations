# Proposal

## Why

Al probar `add-tmux-window-title` con varias sesiones de Claude abiertas, las ventanas se ven `claude: idle` o `claude: Edit foo.ts`: dicen en qué estado está cada sesión, no de qué trata, así que no se sabe cuál es cuál. El nombre debe describir el tema de la sesión (por ejemplo `tmux-plugin: nombres`) y cambiar solo cuando el tema cambia, no en cada evento. El plugin también debe funcionar en Linux y en macOS.

## What Changes

- **BREAKING** (respecto a `add-tmux-window-title`, ya implementado): se eliminan los nombres por estado (`claude: idle`, `claude: <Tool> <objetivo>`, `claude: ESPERA INPUT`). El nombre de la ventana describe el tema de la sesión.
- Nombre híbrido: un nombre base inmediato por heurística local (carpeta del proyecto y rama git, tomadas del `cwd` del hook) y un refinado posterior por un LLM en segundo plano (`claude -p` con modelo pequeño) que resume el tema en pocas palabras.
- El LLM recibe el nombre actual y el prompt nuevo, y responde `KEEP` o un nombre nuevo: solo renombra si juzga que el tema cambió. Se evalúa en el primer prompt sustancial y luego cada N prompts, no en cada evento.
- Se respeta el nombre que el usuario ponga a mano: si el nombre de la ventana difiere del último que puso el plugin, deja de renombrar esa ventana.
- Los hooks pasan de seis eventos a tres: `SessionStart` (nombre base), `UserPromptSubmit` (evaluación del tema) y `SessionEnd` (restauración). Desaparece el hook síncrono en `PreToolUse`.
- La llamada al LLM es asíncrona, de un solo vuelo por pane, con tiempo límite explícito, sin reintentos y con guarda contra recursión de hooks.
- Se sube el tope de largo del nombre (de 24 a 28 caracteres, ver design) y se mantiene la lista permitida de caracteres, que ahora también se aplica a la salida del LLM.
- Portabilidad: POSIX sh sin `flock`, `setsid`, `timeout` ni `date +%s%N`; los tests dejan de usar `date +%s%N`.
- Sin cambios en `~/.tmux.conf` del usuario.

Fuera de alcance: título de pane / `pane-border-status`, servidor MCP, indicador de espera de input (podría volver como marcador aparte), detección local de cambio de tema sin LLM, y soporte de acentos en el nombre.

## Capabilities

### New Capabilities

### Modified Capabilities
- `tmux-window-title`: pasa de reflejar la actividad por evento a nombrar la ventana por el tema de la sesión (heurística más LLM), con evaluación periódica, respeto del renombrado manual y portabilidad Linux/macOS. Requiere que `add-tmux-window-title` se archive antes, para que este spec exista en `openspec/specs/tmux-window-title/`.

## Impact

- Código: se reescribe la lógica de nombre en `plugins/tmux-window-title/hooks/set-title.sh` y se reduce `hooks/hooks.json`. Se reutilizan `tests/lib.sh`, `tests/run.sh`, `test_harness.sh`, `test_tmux_assumptions.sh` y, con ajustes, `test_restore.sh`, `test_sanitize.sh` y `test_silent.sh`; se reemplaza `test_events.sh`. Detalle en `design.md` y `tasks.md`.
- Dependencias: `tmux` y `jq` (en macOS vía Homebrew) y el binario `claude` en el PATH para el refinado; sin `claude` o con el LLM desactivado queda el nombre base.
- Privacidad y coste: cada evaluación envía el nombre actual y el prompt (truncado) a la API con la cuenta del usuario, y gasta tokens del modelo pequeño. Se puede desactivar con una variable de entorno.
- Precondición de proceso: archivar `add-tmux-window-title` antes de validar o archivar este cambio.
