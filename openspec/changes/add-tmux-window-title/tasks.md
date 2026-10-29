# Tasks

## 1. Andamiaje y arnés de tests

- [x] 1.1 Crear `.claude-plugin/marketplace.json` y `plugins/tmux-window-title/.claude-plugin/plugin.json`; verificar con `claude plugin validate .` y `claude plugin validate plugins/tmux-window-title` sin errores
- [x] 1.2 Crear `manifest.scm` y `.envrc` con tmux, jq y shellcheck (skill `guix-dev-env`); verificar que `tmux -V`, `jq --version` y `shellcheck --version` responden dentro del entorno
- [x] 1.3 Escribir `tests/lib.sh` (arranca `tmux -L <socket único> -f /dev/null new-session -d`, exporta `TMUX`/`TMUX_PANE`, mata el servidor al terminar, ayudantes `assert_eq`) y `tests/run.sh`; verificar con un test trivial que crea una ventana, lee su nombre y no deja servidores tmux vivos (`tmux -L <socket> ls` falla después)
- [x] 1.4 Spike: comprobar en tmux 3.8 que `rename-window` pone `automatic-rename` en `off` y que `set-window-option automatic-rename on` lo reactiva; dejarlo como test en `tests/test_tmux_assumptions.sh` y anotar el resultado en `design.md` (Risks) sustituyendo el "no verificado"

## 2. Nombre según el evento

- [x] 2.1 Test rojo, luego `hooks/set-title.sh`: `SessionStart` y `Stop` dan `claude: idle`, y `UserPromptSubmit` da `claude: <inicio del prompt>`; verificar con `tests/test_events.sh` pasando JSON por stdin contra un tmux aislado
- [x] 2.2 Test rojo y luego implementación: `PreToolUse` da `claude: Edit foo.ts` (basename de `file_path`), `claude: Bash npm test` (dos primeras palabras) y solo el nombre de la herramienta sin objetivo o con JSON ilegible; verificar con los escenarios de herramienta en `tests/test_events.sh`
- [x] 2.3 Test rojo y luego implementación: `Notification` da `claude: ESPERA INPUT`; verificar con su caso en `tests/test_events.sh`
- [x] 2.4 Que el objetivo sea `-t "$TMUX_PANE"`: test con dos ventanas, foco en la 2, evento desde la 1; verificar que solo cambia el nombre de la 1, y que dos ventanas con sesiones distintas guardan cada una su estado
- [x] 2.5 Caso de varios panes: dos panes en una ventana emiten eventos en orden; verificar que el nombre es el del último evento

## 3. Saneado

- [x] 3.1 Tests rojos y luego implementación del saneado (lista permitida `A-Za-z0-9 ._:/-`, tope de 24 caracteres con prefijo, nombre tras `--`): prompt de 200 caracteres, saltos de línea, `#{...}`, `$(...)`, comillas, secuencias de escape y un prompt que empieza por `-`; verificar con `tests/test_sanitize.sh` que el nombre resultante cumple largo y caracteres en todos los casos y que tmux no expande ningún formato
- [x] 3.2 Verificar con `shellcheck hooks/set-title.sh tests/*.sh` sin avisos

## 4. Restauración y salida silenciosa

- [x] 4.1 Test rojo y luego guardado de estado en opciones de ventana (`@claude_prev_auto`, `@claude_prev_name`) solo si no existen, y `SessionEnd` que restaura; verificar con `tests/test_restore.sh` los dos casos: `automatic-rename on` vuelve a `on`, y `off` con nombre propio recupera nombre y `off`, y que las opciones `@claude_*` desaparecen
- [x] 4.2 Test rojo y luego salida silenciosa: sin `TMUX_PANE`, con `TMUX_PANE` pero servidor tmux caído, y sin `jq` en el PATH; verificar con `tests/test_silent.sh` código 0, stdout y stderr vacíos, y que sin `TMUX_PANE` no se invoca tmux
- [x] 4.3 Verificar que el hook no emite decisión: con `PreToolUse`, stdout vacío y código 0 (`tests/test_silent.sh`), de modo que no altera permisos ni entrada de la herramienta

## 5. Cableado en Claude Code, medición y documentación

- [x] 5.1 Escribir `hooks/hooks.json` con los seis eventos apuntando a `"${CLAUDE_PLUGIN_ROOT}/hooks/set-title.sh <evento>"`; verificar con `claude plugin validate plugins/tmux-window-title` y confirmar que `${CLAUDE_PLUGIN_ROOT}` se resuelve (hook ejecutado en una sesión real con `claude --plugin-dir plugins/tmux-window-title` dentro de tmux)
- [x] 5.2 Medir la latencia: ejecutar el script 200 veces para `PreToolUse` contra un tmux real; registrar en `design.md` workload, entorno, mediana, p95 y p99, y comparar con el presupuesto de 50 ms. Si lo supera, abrir una tarea para el segundo plano antes de seguir
- [ ] 5.3 Verificación de integración en una sesión real: la ventana pasa por `idle`, prompt, herramienta y `ESPERA INPUT`, vuelve a `ld-linux-...` al salir, y tus hooks de `tdd-gate.sh` siguen ejecutándose y decidiendo igual; anotar lo observado y lo que no se pudo comprobar (por ejemplo, el cierre con `kill -9`)
- [x] 5.4 Escribir `plugins/tmux-window-title/README.md` (instalación con `/plugin install tmux-window-title --marketplace <owner>/<repo>`, dependencia de `jq`, mapa de eventos, limitaciones: varios panes, cierre brusco, secretos alfanuméricos en el prompt) y actualizar `CLAUDE.md` con lenguaje (POSIX sh), estructura de carpetas y `tests/run.sh` como comando de tests; verificar que `tests/run.sh` documentado corre en verde de principio a fin
