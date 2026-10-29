# Design

## Context

Ver `proposal.md` (Why). Estado observado en la máquina del usuario (Guix, tmux 3.8): `automatic-rename` está `on` y `automatic-rename-format` es `#{?pane_in_mode,[tmux],#{pane_current_command}}...`; la ventana de Claude se llama `ld-linux-x86-64.so.2`. La sesión corre dentro de tmux y hereda `$TMUX_PANE`. `jq`, `sh` y `bash` están en el perfil del usuario; `shellcheck` no.

Los hooks de comando de Claude Code reciben un JSON por stdin (`hook_event_name`, `tool_name`, `tool_input`, `prompt`, según el evento). El usuario ya tiene hooks propios en `PreToolUse`/`PostToolUse` (`~/.claude/hooks/tdd-gate.sh`) en `settings.json`.

## Goals / Non-Goals

**Goals:**
- Un único script `set-title.sh`, invocado por `hooks.json` con el evento como argumento, que calcula el nombre y llama a tmux.
- Fallo disponible: cualquier problema (sin tmux, sin `jq`, tmux caído) termina en 0 y en silencio. El nombre de ventana es cosmético y nunca debe frenar a Claude.
- Estado de restauración guardado en la propia ventana de tmux, no en archivos.

**Non-Goals:**
- Distinguir panes dentro de una ventana (último evento gana).
- Configurar o leer `~/.tmux.conf`.
- Internacionalización del nombre: se descartan los caracteres fuera de la lista permitida, acentos incluidos.

## Decisions

**1. POSIX sh más `jq`.** El JSON de stdin se lee con `jq`; sin `jq` el script no renombra y sale en 0. Alternativa descartada: parsear JSON con `sed`/`grep`, frágil con comillas y saltos de línea dentro del prompt. Alternativa descartada: un binario en otro lenguaje, desproporcionado para un `tmux rename-window`. `jq` se documenta como dependencia en el README del plugin.

**2. Un solo script con el evento como argumento.** `hooks.json` mapea cada evento a `"${CLAUDE_PLUGIN_ROOT}/hooks/set-title.sh <evento>"`. Así la lógica de saneado y de salida silenciosa vive en un sitio. Alternativa descartada: un script por evento, que duplica el saneado.

**3. Objetivo `-t "$TMUX_PANE"`.** tmux resuelve un id de pane a su ventana, y `rename-window -t %2` renombra la ventana de ese pane aunque otra tenga el foco. Se pasa el nombre tras `--` para que un nombre que empiece por `-` no se lea como opción.

**4. Saneado en dos pasos, en este orden:** truncar el texto bruto a un margen y luego filtrar con `tr -cd 'A-Za-z0-9 ._:/-'`, y por último recortar a 24 caracteres con el prefijo `claude: ` incluido. La lista permitida (positiva) sustituye a una lista de caracteres prohibidos: deja fuera `#`, `$`, `` ` ``, `=`, comillas y control, que son los de formato de tmux y los típicos de un secreto. No elimina secretos alfanuméricos: el prompt se muestra tal cual en sus primeras palabras. Es una limitación asumida y se documenta en el README.

**5. Objetivo de la herramienta.** `Edit`/`Write`/`Read`: `basename` de `tool_input.file_path`. `Bash`: primera palabra del comando más la siguiente. Otra herramienta: solo el nombre. Entrada ilegible: solo el nombre.

**6. Restauración con estado en opciones de ventana.** En `SessionStart` y antes del primer renombrado, si la ventana no tiene `@claude_prev_auto`, se guardan `@claude_prev_auto` (valor de `automatic-rename`) y `@claude_prev_name` (nombre actual) con `set-option -w`. En `SessionEnd`: si `prev_auto` era `on`, `set-window-option automatic-rename on`; si era `off`, se renombra a `prev_name` y se deja `automatic-rename off`; después se eliminan las opciones `@claude_*`. Con "último evento gana" y varias sesiones en una ventana, el primer `SessionEnd` restaura aunque quede otra sesión; es el comportamiento A acordado. Alternativa descartada: archivo de estado en `$XDG_RUNTIME_DIR`, que añade limpieza y carreras sin beneficio.

**7. Latencia.** Presupuesto propuesto: p95 por debajo de 50 ms por invocación (un `jq` más uno o dos comandos de tmux), medido con un tmux real y reportado con workload, entorno y percentil. Si se supera en `PreToolUse`, la mitigación es lanzar el tmux en segundo plano, con el riesgo de reordenar eventos; no se adopta de antemano.

**8. Tests con tmux real y runner en sh.** Cada test arranca `tmux -L <socket único> -f /dev/null new-session -d`, exporta `TMUX` y `TMUX_PANE` apuntando a ese servidor, ejecuta el script con un JSON de ejemplo y consulta `display-message -p '#{window_name}'`. El servidor se mata al final. Sin mocks de tmux. Alternativa descartada: `bats`, una dependencia más que no está en el perfil.

## Risks / Trade-offs

- [`rename-window` desactiva `automatic-rename`] → verificado en tmux 3.8 (`tests/test_tmux_assumptions.sh`): `rename-window` lo pone en off y `set-window-option automatic-rename on` lo reactiva. `SessionEnd` restaura.
- [Cierre brusco (`kill -9`, cierre del terminal) omite `SessionEnd` y la ventana queda con el último nombre] → se acepta; el usuario puede reactivar con `set-window-option automatic-rename on`. Se documenta. La restauración perezosa queda como mejora futura.
- [Convivencia con `tdd-gate.sh`] → no se verificó que los hooks del plugin y los de `settings.json` se sumen sin interferir; una tarea lo comprueba en una sesión real y registra el resultado.
- [`${CLAUDE_PLUGIN_ROOT}` en `hooks.json`] → no verificado en esta versión (2.1.312); `claude plugin validate` y una sesión real lo confirman.
- [Prompt visible en la barra de estado y en capturas de pantalla] → saneado y truncado a 24 caracteres; no es un control de secretos.
- [Hook síncrono en cada tool] → medir según la decisión 7.

## Measurements

**Latencia de `PreToolUse` (tarea 5.2).** Workload: 200 invocaciones secuenciales de `sh set-title.sh PreToolUse` con `{"tool_name":"Edit","tool_input":{"file_path":"/a/b/foo.ts"}}` por stdin, contra un tmux 3.8 real en un socket aislado (servidor vacío, una ventana). Entorno: Linux 7.2.7 (Guix), 16 CPU, máquina en uso normal. Método: `date +%s%N` antes y después de cada invocación (incluye el `printf` y dos forks de `date`, unos pocos ms de sobrecosto). Resultado: mediana 26.8 ms, p95 28.8 ms, p99 31.6 ms, máximo 47.7 ms. Cumple el presupuesto de p95 < 50 ms; no se adopta el segundo plano. No medido: servidor con muchas sesiones/ventanas, ni carga de CPU alta.

**Sesión real (tareas 5.1 y 5.3, parcial).** `claude -p --plugin-dir plugins/tmux-window-title "<leer manifest.scm>"` dentro de un tmux aislado, sondeando el nombre de ventana cada 0,2 s. Secuencia observada: `tmux` → `claude: idle` → `claude: Use the Read too` → `claude: Read manifest.sc` → `ld-linux-x86-64.so.2` (con `automatic-rename` otra vez en 1). Conclusiones: `${CLAUDE_PLUGIN_ROOT}` se resuelve (los hooks se ejecutaron, con la ruta entre comillas que pide el validador); `SessionEnd` restaura. No observado: `claude: idle` tras `Stop` (el sondeo no lo capturó), `ESPERA INPUT` (`Notification` no se dispara en modo `-p`), convivencia con `tdd-gate.sh`, y cierre con `kill -9`. Requiere una sesión interactiva.
