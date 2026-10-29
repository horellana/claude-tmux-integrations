## ADDED Requirements

### Requirement: Nombre de ventana según la actividad
El sistema SHALL renombrar la ventana de tmux que contiene el pane de la sesión de Claude Code con el formato `claude: <estado>`, donde `<estado>` refleja la actividad actual: `idle`, el inicio del prompt, la herramienta en uso con su objetivo, o `ESPERA INPUT`.

#### Scenario: Sesión recién iniciada
- **WHEN** arranca una sesión de Claude Code dentro de tmux
- **THEN** la ventana se llama `claude: idle`

#### Scenario: El usuario envía un prompt
- **WHEN** el usuario envía el prompt `arregla el bug del login en auth.ts`
- **THEN** la ventana se llama `claude: ` seguido de las primeras palabras del prompt, truncado al largo máximo

#### Scenario: Claude usa una herramienta
- **WHEN** Claude va a ejecutar `Edit` sobre `src/foo.ts`
- **THEN** la ventana se llama `claude: Edit foo.ts`

#### Scenario: Claude usa una herramienta sin objetivo identificable
- **WHEN** Claude ejecuta una herramienta cuya entrada no tiene archivo ni comando reconocible
- **THEN** la ventana se llama `claude: ` seguido solo del nombre de la herramienta

#### Scenario: Claude espera una respuesta del usuario
- **WHEN** Claude emite una notificación de que necesita input o permiso
- **THEN** la ventana se llama `claude: ESPERA INPUT`

#### Scenario: Claude termina su turno
- **WHEN** Claude termina de responder
- **THEN** la ventana se llama `claude: idle`

### Requirement: Largo y caracteres del nombre
El nombre de la ventana SHALL tener como máximo 24 caracteres y SHALL contener solo caracteres de una lista permitida (letras, dígitos, espacio y `.` `_` `-` `/` `:`). Los demás caracteres MUST descartarse o sustituirse antes de pasar el texto a tmux.

#### Scenario: Prompt largo
- **WHEN** el prompt tiene 200 caracteres
- **THEN** el nombre de la ventana no supera 24 caracteres

#### Scenario: Prompt con caracteres de control o formato de tmux
- **WHEN** el prompt contiene saltos de línea, secuencias de escape o expresiones `#{...}`
- **THEN** el nombre resultante no contiene esos caracteres y tmux no expande ningún formato

#### Scenario: Prompt con un secreto
- **WHEN** el prompt contiene una cadena con símbolos como `sk-ant-...=` o `p@ss$word`
- **THEN** los caracteres fuera de la lista permitida no aparecen en el nombre

### Requirement: Objetivo es la ventana de Claude
El sistema SHALL dirigir el renombrado a la ventana que contiene el pane indicado por `$TMUX_PANE`, no a la ventana activa en ese momento.

#### Scenario: Otra ventana tiene el foco
- **WHEN** Claude trabaja en la ventana 1 y el usuario tiene activa la ventana 2
- **THEN** solo se renombra la ventana 1

#### Scenario: Varias sesiones de Claude
- **WHEN** dos sesiones de Claude corren en ventanas distintas
- **THEN** cada ventana muestra el estado de su propia sesión

### Requirement: Varios panes en una ventana
Cuando una ventana contiene varios panes, el sistema SHALL aplicar el último evento recibido sin intentar distinguir entre panes.

#### Scenario: Dos panes con Claude en la misma ventana
- **WHEN** dos sesiones de Claude comparten una ventana y la segunda emite un evento después de la primera
- **THEN** la ventana muestra el estado del evento más reciente

### Requirement: Restauración al terminar la sesión
Al terminar la sesión de Claude Code, el sistema SHALL devolver la ventana al renombrado automático de tmux, de modo que no conserve el último estado.

#### Scenario: Cierre normal de la sesión
- **WHEN** la sesión de Claude termina y se emite el fin de sesión
- **THEN** la ventana vuelve a tener `automatic-rename` activo y su nombre lo decide tmux

#### Scenario: La ventana tenía renombrado automático desactivado
- **WHEN** el usuario había desactivado `automatic-rename` en la ventana antes de iniciar Claude
- **THEN** al terminar la sesión se restaura el nombre y el valor de `automatic-rename` que tenía la ventana al iniciar

### Requirement: Ejecución fuera de tmux
Fuera de tmux, el sistema MUST terminar con código de salida 0 y sin escribir en stdout ni stderr.

#### Scenario: Claude corre sin tmux
- **WHEN** `$TMUX_PANE` está vacío o no definido
- **THEN** el hook termina con código 0 sin salida y sin invocar tmux

#### Scenario: El servidor tmux no responde
- **WHEN** `$TMUX_PANE` está definido pero el comando de tmux falla
- **THEN** el hook termina con código 0 sin salida y sin interrumpir a Claude

### Requirement: Sin interferencia con Claude ni con otros hooks
El sistema MUST NOT bloquear ni alterar ninguna acción de Claude Code ni la decisión de otros hooks, y SHALL completarse con baja latencia en cada evento.

#### Scenario: Hook sobre PreToolUse
- **WHEN** el hook se ejecuta antes de una herramienta
- **THEN** no emite decisión de permiso ni modifica la entrada de la herramienta, y la herramienta continúa según los demás hooks y permisos

#### Scenario: Latencia
- **WHEN** el hook se ejecuta contra un tmux en funcionamiento
- **THEN** su duración medida queda por debajo del presupuesto fijado en el diseño
