# Tasks

Reutiliza de `add-tmux-window-title`: `tests/lib.sh`, `tests/run.sh`, `test_harness.sh`, `test_tmux_assumptions.sh`, saneado y escritura con `-t "$TMUX_PANE"` y `--`, guardado y restauración en `@claude_prev_*`, salida silenciosa. Se reemplaza: el mapa evento→nombre de `set-title.sh` y `tests/test_events.sh`. Se ajustan: `test_sanitize.sh` (tope 28), `test_restore.sh`, `test_silent.sh` y `hooks.json`.

## 1. Spikes y portabilidad del arnés

- [x] 1.1 Volcar el JSON real de `SessionStart` y `UserPromptSubmit` con un hook temporal en una sesión real y confirmar que `cwd` y `prompt` están presentes; anotar el resultado en `design.md` (Context) y verificar con el archivo volcado
- [x] 1.2 Probar el `claude -p --model haiku --tools "" --no-session-persistence --disable-slash-commands` real con un prompt de ejemplo: respuesta de una línea, latencia, y si el hijo dispara los hooks del plugin; anotar flags definitivas y medidas en `design.md`
- [x] 1.3 Reemplazar `date +%s%N` en `tests/lib.sh` por un nombre de socket con `mktemp -d`; verificar con `sh tests/run.sh` en verde y con `shellcheck` sin avisos, sin sockets residuales en `/tmp/tmux-<uid>/`
- [x] 1.4 Fijar el tmux mínimo (opciones `@x`, `set-option -w -u`) y anotarlo en `design.md` y en el README; verificar que `tests/test_tmux_assumptions.sh` cubre cada comando de tmux usado

## 2. Nombre base

- [x] 2.1 Test rojo y luego implementación: `SessionStart` con `cwd` en un repo en `main`, en rama `fix/timeout` y fuera de repo da `<repo>`, `<repo> fix/timeout`, `<dir>`; verificar con `tests/test_base_name.sh` sobre repos git temporales
- [x] 2.2 Eliminar de `set-title.sh` los nombres por estado; verificar que `tests/test_events.sh` se reemplaza por tests de este cambio y que ningún test espera `claude: idle`, `ESPERA INPUT` ni `<Tool> <objetivo>`
- [x] 2.3 Reducir `hooks/hooks.json` a `SessionStart`, `UserPromptSubmit` y `SessionEnd`; verificar con `claude plugin validate plugins/tmux-window-title` sin errores

## 3. Refinado por modelo

- [x] 3.1 Test rojo y luego implementación de la evaluación con un `claude` falso (`CLAUDE_TMUX_TITLE_CMD`): el primer prompt sustancial renombra con la respuesta del modelo, `KEEP` deja el nombre, y el cuerpo del hook vuelve sin esperar; verificar con `tests/test_refine.sh` contra tmux real, midiendo que el hook termina antes de que responda un falso que duerme 2 s
- [x] 3.2 Test rojo y luego implementación de la cadencia: prompts triviales (`/x`, menos de 10 caracteres) no evalúan; se evalúa en el primero y cada N; verificar con un falso que cuenta invocaciones
- [x] 3.3 Test rojo y luego implementación del saneado de la salida del modelo (tope 28, lista permitida, `#{...}`, saltos de línea, primer carácter `-`, vacío) y del prompt truncado a 500 caracteres enviado al modelo; verificar con `tests/test_sanitize.sh` ajustado y con un falso que vuelca su entrada
- [x] 3.4 Test rojo y luego implementación de renombrado manual: tras `tmux rename-window mi-trabajo`, nuevas evaluaciones no cambian el nombre; verificar con `tests/test_manual.sh`
- [x] 3.5 Test rojo y luego implementación del cerrojo por pane, tiempo límite con vigilante y descarte tras `SessionEnd`: un solo vuelo, un falso colgado muere a los 30 s (configurable por variable para el test) y la respuesta tardía no renombra; verificar con `tests/test_background.sh` sin procesos huérfanos (`ps`) ni cerrojos residuales
- [x] 3.6 Test rojo y luego implementación de la guarda contra recursión y de la desactivación: con `CLAUDE_TMUX_TITLE_BG=1` el hook sale sin acción; con `CLAUDE_TMUX_TITLE_LLM=0` o sin `claude` queda el nombre base, siempre con código 0 y sin salida; verificar con `tests/test_silent.sh` ajustado

## 4. Restauración, silencio y latencia

- [x] 4.1 Ajustar `tests/test_restore.sh`: con el nuevo estado (`@claude_title`, `@claude_n`, `@claude_manual`) `SessionEnd` restaura `automatic-rename` o el nombre previo y elimina todas las opciones `@claude_*`; verificar con los dos casos (on, y off con nombre propio)
- [x] 4.2 Medir la latencia del hook síncrono de `UserPromptSubmit` (200 ejecuciones, tmux real, con el modelo falso en segundo plano): registrar en `design.md` workload, entorno, mediana, p95 y p99 frente a un presupuesto de p95 < 50 ms
- [x] 4.3 Verificar con `shellcheck` sobre `hooks/set-title.sh` y `tests/*.sh` sin avisos, y `sh tests/run.sh` en verde, incluyendo que no quedan servidores tmux ni sockets de test

## 5. Portabilidad y documentación

- [x] 5.1 Revisar `set-title.sh` y los tests contra la lista de utilidades POSIX de la decisión 11 (sin `flock`, `setsid`, `timeout`, `sed -i`, `date +%N`); verificar con una búsqueda de esos nombres en el código y con `shellcheck --shell=sh`
- [x] 5.2 Añadir un flujo de CI en `.github/workflows/test.yml` con matriz `ubuntu-latest` y `macos-latest` que instale `tmux`, `jq` y `shellcheck` y ejecute `sh tests/run.sh`; verificar que el YAML valida localmente. Su ejecución en macOS queda sin verificar hasta publicar en un remoto
- [x] 5.3 Actualizar `plugins/tmux-window-title/README.md` (nombre descriptivo, mapa de eventos, variables `CLAUDE_TMUX_TITLE_LLM`, `_EVERY`, `_CMD`, privacidad y coste, macOS con Homebrew, limitaciones: acentos, varios panes, cierre brusco) y `CLAUDE.md` (estructura, tests); verificar que lo documentado coincide con el comportamiento del script y que `sh tests/run.sh` corre en verde
- [x] 5.4 Verificación en una sesión interactiva real con varias ventanas: nombre base, nombre descriptivo tras el primer prompt, cambio al cambiar de tema, respeto a un renombrado manual, restauración al salir y `tdd-gate.sh` sin cambios en sus decisiones; anotar lo observado y lo que no se pudo comprobar (macOS, `kill -9`)

## Workflow follow-up

- Archivar `add-tmux-window-title` antes de validar este cambio.
- Archivar este cambio después de la verificación 5.4.
