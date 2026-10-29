# Design

## Context

Ver `proposal.md` (Why). Estado tras `add-tmux-window-title` (commit `fd062f1`): `set-title.sh` renombra por evento con seis hooks; hay arnés de tests con tmux real en socket aislado (`tests/lib.sh`), 84 asserts en verde y p95 de 28,8 ms por invocación. El estado de restauración vive en opciones de ventana (`@claude_prev_auto`, `@claude_prev_name`).

Observado en `claude --help` (v2.1.312), no probado todavía para este uso: `-p`, `--model`, `--tools ""`, `--no-session-persistence`, `--disable-slash-commands`. `--bare` omite los hooks, pero solo autentica con `ANTHROPIC_API_KEY` o `apiKeyHelper` (no OAuth ni keychain), y el usuario usa OAuth de Claude Pro, así que no sirve como guarda contra recursión. Spikes 1.1 y 1.2 (claude 2.1.312, Linux, 2026-10-28, un plugin temporal que vuelca stdin y entorno):
- El JSON de `SessionStart` trae `session_id`, `cwd`, `hook_event_name`, `source`; el de `UserPromptSubmit` trae además `prompt`, `prompt_id`, `permission_mode`. Confirmado con volcado real.
- El entorno del hook incluye `TMUX` y `TMUX_PANE`, y también se heredan al `claude -p` hijo.
- `claude -p --model haiku --tools "" --no-session-persistence --disable-slash-commands "<prompt>" </dev/null` funciona: responde una línea (3 ejecuciones: 5 s, 3 s, 4 s de pared; n=3, no es una medida de percentiles). Sin `</dev/null` avisa por stderr de falta de stdin tras 3 s, así que el hijo debe lanzarse con stdin redirigido.
- Con esas flags el hijo **sí dispara** `SessionStart` y `UserPromptSubmit` de los plugins cargados: la guarda `CLAUDE_TMUX_TITLE_BG` es necesaria, no preventiva.
- No probado: que la variable de guarda llegue al hijo (se verifica en la tarea 3.6) ni el comportamiento con el plugin instalado desde un marketplace.

Restricciones de plataforma: macOS trae `sh` (bash 3.2 en modo POSIX), `date` y `sed` BSD, y no trae `flock`, `setsid` ni `timeout`. Aquí solo se puede ejecutar Linux.

## Goals / Non-Goals

**Goals:**
- Un nombre por ventana que identifique el tema, estable, y que cambie solo si el tema cambió.
- Hooks síncronos baratos; todo lo lento va en segundo plano y falla en silencio.
- Un solo script POSIX sh, portable a Linux y macOS.

**Non-Goals:**
- Detectar el cambio de tema sin modelo.
- Transliterar acentos (la lista permitida los descarta; se pide al modelo ASCII).
- Distinguir panes dentro de una ventana.

## Decisions

**1. Tres eventos.** `SessionStart` pone el nombre base; `UserPromptSubmit` cuenta prompts y lanza la evaluación; `SessionEnd` restaura. `PreToolUse`, `Notification` y `Stop` se quitan de `hooks.json`: ya no aportan al nombre y el hook por herramienta era el de mayor coste. Alternativa descartada: conservarlos como no-op, que sigue pagando un fork por herramienta.

**2. Nombre base local.** `cwd` del JSON → raíz git (`git -C "$cwd" rev-parse --show-toplevel`) o el propio `cwd`; basename más la rama (`git symbolic-ref --short HEAD`) si no es `main` ni `master`. Se calcula una vez, en `SessionStart`. Sin `jq` o sin `cwd`, se usa `$PWD`. Alternativa descartada: usar palabras del primer prompt como base, que da nombres ruidosos y duplica lo que hará el modelo.

**3. Refinado por `claude -p` en segundo plano.** Prompt al modelo: instrucciones fijas más el nombre actual y el prompt truncado a 500 caracteres, delimitados como datos; respuesta esperada: una línea, `KEEP` o un nombre de hasta 28 caracteres en ASCII, en el idioma del prompt. Invocación candidata: `claude -p --model haiku --tools "" --no-session-persistence --disable-slash-commands` (a verificar en el spike). El hook lanza un subshell en segundo plano con fds redirigidos y vuelve de inmediato. El nombre de la salida pasa por el mismo saneado que la heurística (lista permitida, tope 28, nombre tras `--`).

Contrato implementado (fijado por los tests): el texto es el último argumento y lleva instrucciones fijas, la línea `Current name: <nombre>` y el prompt (500 caracteres) entre `<prompt>` y `</prompt>`; `@claude_n` cuenta solo prompts sustanciales; el cerrojo guarda el pid en `<lock>/pid`; variables `CLAUDE_TMUX_TITLE_EVERY` y `CLAUDE_TMUX_TITLE_TIMEOUT` (valores inválidos caen a 3 y 30). Un renombrado manual se detecta cuando responde el modelo; desde entonces no se vuelve a llamar. Pendiente conocido: una carrera pequeña en el vigilante (TERM entre `sleep` y el registro del pid) podría dejar un `sleep` huérfano hasta el tiempo límite; no se ha observado tras el arreglo.

**4. Cuándo evaluar.** Contador `@claude_n` en la ventana. Se evalúa si el prompt es sustancial (no empieza por `/` y tiene al menos 10 caracteres) y `n` es 0 (primero) o múltiplo de N; N = 3 por defecto, ajustable con `CLAUDE_TMUX_TITLE_EVERY`. "Cambio de tema" lo decide el modelo comparando el nombre actual con el prompt; no hay detección local. Alternativa descartada: evaluar en cada prompt, que multiplica coste y latencia de red por poco beneficio.

**5. Respeto del renombrado manual.** Se guarda en `@claude_title` el último nombre puesto. Antes de aplicar, si `#{window_name}` difiere de `@claude_title`, el usuario renombró: se activa `@claude_manual` y no se vuelve a renombrar. Alternativa descartada: comparar contra `automatic-rename`, que ya está en `off` por nuestro propio `rename-window`.

**6. Un vuelo por pane y descarte al terminar.** Cerrojo atómico con `mkdir` en `${TMPDIR:-/tmp}/claude-tmux-title-$(id -u)/<pane>.lock` con el pid dentro; un cerrojo cuyo pid no responde a `kill -0` se considera viejo y se reemplaza. Al volver el modelo, el subshell aplica el nombre solo si `@claude_prev_auto` sigue definida (sesión viva) y `@claude_manual` no está; si no, descarta. Sin `flock` por portabilidad.

**7. Tiempo límite, sin reintentos.** POSIX no trae `timeout`; se usa un vigilante: lanzar `claude` en segundo plano, y otro subshell que hace `sleep 30` y `kill` sobre su pid. Sin reintentos: una evaluación fallida se repite sola en la siguiente ocasión; el efecto es idempotente (poner un nombre) y cosmético. Se descarta añadir dependencia de `gtimeout`.

**8. Guarda contra recursión.** El subshell exporta `CLAUDE_TMUX_TITLE_BG=1` al proceso `claude`; `set-title.sh` sale con 0 al instante si la variable está definida. `--bare` descartado por la autenticación (ver Context). Variante a comprobar en el spike: que el `claude -p` hijo cargue el plugin y dispare hooks, que es lo que la guarda previene.

**9. Desactivar y degradar.** `CLAUDE_TMUX_TITLE_LLM=0` o ausencia de `claude`/`jq` en el PATH dejan solo el nombre base. Todo fallo termina en 0 y en silencio (fallo disponible: el nombre es cosmético).

**10. Tope de 28 caracteres.** Con 24 un tema descriptivo queda cortado (`pagos: timeout cobro` ya son 20). 28 deja margen sin saturar una barra con varias ventanas. Es una elección de lectura en la barra, no medida; se puede revisar con uso real.

**11. Portabilidad.** Solo POSIX sh y utilidades presentes en ambos sistemas (`tr`, `cut`, `head`, `sed` sin `-i`, `mkdir`, `kill`, `sleep`). `tests/lib.sh` sustituye `date +%s%N` por `mktemp -d` para el nombre del socket. Tmux: solo se ha probado 3.8 (`tests/test_tmux_assumptions.sh` cubre `rename-window`, `automatic-rename`, y opciones de usuario `@x` con `set-option -w` y `-u`); un mínimo inferior no se ha verificado y no se afirma. Sin verificar en macOS. Verificación en macOS: flujo de CI con matriz Linux/macOS que ejecute `tests/run.sh`; no se puede probar localmente y no hay remoto git todavía, así que su resultado queda sin verificar hasta publicarlo.

**12. Tests del modelo sin red.** El binario se invoca mediante `${CLAUDE_TMUX_TITLE_CMD:-claude}`; los tests apuntan a un script falso que responde `KEEP`, un nombre, basura, o se cuelga, sobre un tmux real. Es la frontera propia que envuelve la herramienta de terceros. Una verificación aparte, con el `claude` real, comprueba el comportamiento de extremo a extremo.

## Risks / Trade-offs

- [El prompt se envía a la API en cada evaluación; coste de tokens y privacidad] → truncado a 500 caracteres, solo nombre actual y prompt, modelo pequeño, variable para desactivar; los secretos alfanuméricos del prompt igual se envían, como ya ocurre con el prompt de la sesión; se documenta en el README.
- [Recursión de hooks si el `claude -p` hijo carga el plugin] → variable `CLAUDE_TMUX_TITLE_BG` y test con un `claude` falso que invoca el hook.
- [Carreras entre resúmenes y con el fin de sesión] → un vuelo por pane, descarte si la sesión terminó, comprobación de `@claude_manual` antes de aplicar.
- [El nombre pasa por el saneado pero el modelo puede dar nombres malos o en otro idioma] → el prompt fija formato y ASCII; salida ilegible o vacía deja el nombre como está.
- [Prompt malicioso que intenta dirigir al modelo (inyección)] → el modelo solo produce un texto corto que pasa por la lista permitida y el tope; sin herramientas (`--tools ""`), así que el daño se limita a un nombre feo.
- [Acentos descartados] → se pide ASCII al modelo; un nombre base con acentos (carpeta) los pierde; limitación aceptada.
- [Procesos en segundo plano huérfanos si se cierra el terminal] → el vigilante de 30 s los mata; cerrojos viejos se reemplazan por `kill -0`.
- [macOS sin verificar localmente] → tests portables y CI en matriz; hasta que corra en macOS el soporte es una afirmación sin comprobar.
- [Dependencia de `claude -p` y sus flags, que pueden cambiar] → un spike fija las flags usadas; el binario va detrás de una variable, y el degradado es el nombre base.

## Migration Plan

1. Archivar `add-tmux-window-title` (5.3 queda como no verificada) para que `tmux-window-title` exista en `openspec/specs/`.
2. Implementar este cambio sobre el mismo plugin; `hooks.json` pasa a tres eventos.
3. Rollback: volver al commit `fd062f1`; el estado en opciones `@claude_*` es compatible (se conservan `@claude_prev_auto` y `@claude_prev_name`; las nuevas `@claude_title`, `@claude_n`, `@claude_manual` se ignoran por la versión vieja).

## Open Questions

- N (3) y el tiempo límite (30 s) son valores iniciales; ajustarlos con uso real no cambia spec ni tareas.
- Un marcador aparte para "espera input" podría volver como cambio futuro; fuera de alcance aquí.

## Medición de latencia (tarea 4.2)

- Carga: 200 ejecuciones seguidas de `set-title.sh UserPromptSubmit` con un prompt sustancial y `CLAUDE_TMUX_TITLE_EVERY=1`, contra un tmux real en socket aislado y un `claude` falso en segundo plano; el reloj mide el proceso del hook (`perf_counter_ns`, sin el arranque de Python). Dos escenarios: *slow* (el falso duerme 2 s, así que casi todas las ejecuciones encuentran el cerrojo ocupado y descartan) y *fast* (el falso responde al instante; el cerrojo se libera entre ejecuciones y el hook lanza el refinado en parte de ellas).
- Entorno: Linux 7.2.7, 16 CPU, tmux 3.8, sh de Guix; sin otras cargas de tests en paralelo (hay un healthcheck de podman cada 5 s que no se aisló).
- Antes de optimizar (11 procesos en el camino con cerrojo ocupado), 3 repeticiones: slow mediana 42–45 ms, p95 56–66 ms (no cumplía el presupuesto), fast p95 41 ms.
- Después de unir las tres lecturas de opciones en un `display-message`, leer el pid con `read` y evitar el `mkdir -p` redundante (7 procesos): slow mediana 27–30 ms, p95 35,7–40,2 ms, p99 38,7–44,2 ms, máx 39,8–45,2 ms; fast mediana 26–27 ms, p95 32,2 ms, p99 33–34 ms (3 repeticiones propias, coherentes con las 3 del implementer). Presupuesto p95 < 50 ms: se cumple en este entorno y con este benchmark.
- No medido: macOS, un tmux con muchas ventanas/sesiones, máquina cargada. Las ráfagas de ejecuciones lentas vistas antes de optimizar no se atribuyeron a una causa. El caso `SessionStart` (git, jq) no se midió aquí.

## Revisión de portabilidad (tareas 5.1 y 5.2)

- 5.1: una búsqueda de `flock`, `setsid`, `timeout`/`gtimeout`, `sed -i`, `date +%N`, `echo -e`, `[[`, `local` y `readlink -f` en `set-title.sh` y `tests/*.sh` solo encontró la palabra «timeout» en nombres de prueba y ramas; ningún uso de esas utilidades. `shellcheck --shell=sh` sobre el hook y los tests: rc 0.
- Utilidades que se usan y cuya compatibilidad con macOS **no se ha comprobado**: `head -c`, `sleep 0.1` (solo en tests), `env -u` (tests), `mktemp -d <plantilla>`, `tr -cd` con `LC_ALL=C`, `git init -b` (git ≥ 2.28, tests).
- 5.2: `.github/workflows/test.yml` ejecuta shellcheck y `sh tests/run.sh` en `ubuntu-latest` y `macos-latest` (instalando tmux, jq y shellcheck con apt o Homebrew). Solo se validó que el YAML se parsea; el flujo **no se ha ejecutado** en ninguno de los dos sistemas: no hay remoto git. Hasta que corra en macOS, el soporte de macOS sigue sin verificar.

## Verificación en sesión interactiva real (tarea 5.4)

Entorno: claude 2.1.312 con `--plugin-dir`, modelo del hook y de la sesión `haiku`, tmux 3.8 en socket aislado (`-L verif54`), Linux, repo temporal `api-pagos` en la rama `fix/timeout`, sesiones lanzadas con `send-keys`. 2026-10-29.

Observado:
- Nombre base real: la ventana pasó a `api-pagos fix/timeout` al abrir la sesión (en las 4 ventanas probadas).
- Primer prompt sustancial (ventana 1): `api-pagos fix/timeout` → `fix timeout cobro tarjeta`, `@claude_n=1`. Prompts 2 y 3: nombre igual, `@claude_n` 2 y 3.
- Dos sesiones con temas distintos (ventanas 1 y 2) tuvieron nombres distintos y descriptivos. Ventana 2 con `CLAUDE_TMUX_TITLE_EVERY=1`: `explicacion git rebase` → tras un cambio de tema explícito, `renombrar fotos por fecha`.
- Restauración: `/exit` con `automatic-rename` activo devolvió `bash` y `auto=1`; con ventana de nombre explícito devolvió `bash` y `auto=0`; en ambos casos sin opciones `@claude_*`. Sin cerrojos ni procesos residuales en `/tmp/claude-tmux-title-1000`.
- `kill -9` de `claude`: la ventana conserva `api-pagos fix/timeout`, `automatic-rename` off y el estado guardado, como dice la limitación del README.

Hallazgos:
- **El modelo no es determinista y a veces dice `KEEP` ante un cambio de tema.** Ventana 1, 4.º prompt (`olvida lo anterior: ... documentar la API de reembolsos`): el nombre no cambió. Repetí a mano la misma llamada con el texto del hook: una respuesta fue `documentar API reembolsos` y la otra `KEEP`. Es un efecto del prompt de decisión y del modelo, no de la mecánica del plugin; afinar las instrucciones queda fuera de este cambio y es una mejora posible.
- Renombrado manual: tras `rename-window mi-trabajo` y un prompt nuevo (con `EVERY=1`) el nombre se mantuvo, pero `@claude_manual` quedó vacío, así que no se puede distinguir si el modelo respondió `KEEP` o si el nombre quedó protegido por la guarda. El comportamiento de la guarda sí lo cubre `tests/test_manual.sh`; aquí no quedó demostrado en vivo.
- Con la sesión real el Enter enviado junto al texto con `send-keys` no siempre envía el prompt; hubo que enviarlo aparte. Es una particularidad del arnés de esta verificación, no del plugin.

No se pudo comprobar:
- `tdd-gate.sh` (hook de `~/.claude`, solo actúa en repos con `.claude/tdd-gate.conf`): no se comparó el efecto de sus decisiones con y sin el plugin. Solo hay un argumento estructural: el plugin ya solo engancha `SessionStart`, `UserPromptSubmit` y `SessionEnd`, y no emite decisiones.
- macOS; sesiones con varios panes en una ventana; un tmux distinto de 3.8; coste en tokens medido de las evaluaciones.
- Efecto lateral: aceptar el diálogo de confianza dejó registrado el directorio temporal del scratchpad como carpeta de confianza en la configuración de Claude.
