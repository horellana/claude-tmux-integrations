# tmux-window-title Specification

## Purpose

Nombrar la ventana de tmux de una sesión de Claude Code para distinguir varias sesiones en la barra de estado, y devolver a la ventana su nombre automático al terminar la sesión.

## Requirements

### Requirement: Largo y caracteres del nombre
El nombre de la ventana SHALL tener como máximo 28 caracteres y SHALL contener solo caracteres de una lista permitida (letras, dígitos, espacio y `.` `_` `-` `/` `:`). Los demás caracteres MUST descartarse o sustituirse antes de pasar el texto a tmux, tanto si el nombre viene de la heurística como si viene del modelo.

#### Scenario: Prompt largo
- **WHEN** el prompt tiene 200 caracteres
- **THEN** el nombre de la ventana no supera 28 caracteres

#### Scenario: Prompt con caracteres de control o formato de tmux
- **WHEN** el prompt, o la respuesta del modelo, contiene saltos de línea, secuencias de escape o expresiones `#{...}`
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
Cuando una ventana contiene varios panes, el sistema SHALL aplicar el último nombre calculado sin intentar distinguir entre panes.

#### Scenario: Dos panes con Claude en la misma ventana
- **WHEN** dos sesiones de Claude comparten una ventana y la segunda aplica un nombre después de la primera
- **THEN** la ventana muestra el nombre aplicado más recientemente

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

### Requirement: Nombre base por proyecto
Al iniciar la sesión, el sistema SHALL poner a la ventana un nombre base derivado de la carpeta del proyecto (raíz del repositorio git, o el directorio de trabajo si no hay repositorio) y, si existe, la rama git cuando no es `main` ni `master`.

#### Scenario: Sesión en un repositorio con rama de trabajo
- **WHEN** arranca una sesión con directorio de trabajo dentro del repositorio `api-pagos` en la rama `fix/timeout`
- **THEN** la ventana se llama `api-pagos fix/timeout` (truncado al largo máximo)

#### Scenario: Sesión en la rama principal
- **WHEN** arranca una sesión en un repositorio `api-pagos` en la rama `main`
- **THEN** la ventana se llama `api-pagos`

#### Scenario: Sesión fuera de un repositorio
- **WHEN** arranca una sesión en el directorio `/home/ana/notas` que no es un repositorio git
- **THEN** la ventana se llama `notas`

### Requirement: Nombre descriptivo del tema
El sistema SHALL refinar el nombre de la ventana con un resumen del tema de la sesión, de pocas palabras, generado por un modelo a partir del nombre actual y del prompt reciente. El nombre MUST describir el tema y MUST NOT indicar estado de actividad (inactivo, herramienta en uso, espera de input).

#### Scenario: El primer prompt define el tema
- **WHEN** el usuario envía como primer prompt `arregla el timeout al cobrar con tarjeta en el servicio de pagos`
- **THEN** cuando el modelo responde, la ventana pasa a un nombre descriptivo como `pagos: timeout cobro`

#### Scenario: Sin estados en el nombre
- **WHEN** Claude usa una herramienta, termina su turno o espera input
- **THEN** el nombre de la ventana no cambia por ese motivo

### Requirement: Decidir cuándo renombrar
El sistema SHALL evaluar el tema en el primer prompt sustancial de la sesión y después cada N prompts (N configurable, 3 por defecto), y SHALL cambiar el nombre solo si el modelo juzga que el tema cambió. Si el modelo responde que el tema se mantiene, el nombre queda igual.

#### Scenario: El tema se mantiene
- **WHEN** se alcanza la evaluación periódica y el modelo responde que el tema sigue siendo el mismo
- **THEN** el nombre de la ventana no cambia

#### Scenario: El tema cambia
- **WHEN** el usuario pasa de trabajar en un bug de pagos a documentar la API y se alcanza la evaluación
- **THEN** la ventana toma un nombre nuevo que describe la documentación de la API

#### Scenario: Prompt trivial
- **WHEN** el prompt es un comando de barra, o tiene menos de 10 caracteres
- **THEN** no se hace evaluación del tema por ese prompt

### Requirement: Respeto del renombrado manual
Si el nombre de la ventana difiere del último nombre que puso el sistema, el sistema SHALL tratarlo como un renombrado hecho por el usuario y MUST NOT volver a renombrar esa ventana durante la sesión.

#### Scenario: El usuario renombra la ventana
- **WHEN** el usuario renombra la ventana a `mi-trabajo` y luego envía otro prompt
- **THEN** la ventana sigue llamándose `mi-trabajo`, aunque se alcance una evaluación del tema

### Requirement: Refinado en segundo plano acotado
El refinado SHALL ejecutarse sin bloquear a Claude Code, con a lo sumo una evaluación en curso por pane, con tiempo límite explícito y sin reintentos. Si la evaluación falla, expira o la sesión ya terminó, el sistema MUST dejar el nombre como está y no escribir nada en stdout ni stderr.

#### Scenario: El modelo tarda o falla
- **WHEN** la llamada al modelo excede el tiempo límite o devuelve error
- **THEN** el nombre de la ventana no cambia y el hook ya había terminado con código 0

#### Scenario: Evaluación en curso
- **WHEN** llega un prompt mientras hay otra evaluación en curso para el mismo pane
- **THEN** no se lanza una segunda evaluación

#### Scenario: La sesión termina durante la evaluación
- **WHEN** la sesión emite el fin de sesión y después llega la respuesta del modelo
- **THEN** la respuesta se descarta y la ventana conserva el nombre restaurado

### Requirement: Sin recursión de hooks
La llamada al modelo que hace el sistema MUST NOT disparar el renombrado de la ventana. El hook SHALL terminar de inmediato, sin salida, cuando lo ejecuta esa misma llamada.

#### Scenario: El resumen dispara hooks
- **WHEN** el proceso del modelo lanzado por el sistema emite eventos de hook
- **THEN** el hook termina con código 0 sin renombrar ni lanzar otra evaluación

### Requirement: Desactivar el refinado por modelo
El sistema SHALL permitir desactivar el refinado por modelo con una variable de entorno, y en ese caso SHALL conservar el nombre base. Sin el binario `claude` en el PATH, el sistema SHALL comportarse igual.

#### Scenario: Refinado desactivado
- **WHEN** la variable de desactivación está definida y el usuario envía prompts
- **THEN** no se invoca al modelo y la ventana conserva el nombre base

#### Scenario: Sin binario claude
- **WHEN** `claude` no está en el PATH
- **THEN** la ventana conserva el nombre base y el hook termina con código 0 sin salida

### Requirement: Privacidad del texto enviado al modelo
El sistema MUST limitar a 500 caracteres el prompt que envía al modelo, y MUST enviar solo ese texto y el nombre actual de la ventana. El prompt SHALL tratarse como dato y no como instrucciones del resumen.

#### Scenario: Prompt largo
- **WHEN** el prompt tiene 5000 caracteres
- **THEN** al modelo se envían como máximo 500 caracteres del prompt

### Requirement: Compatibilidad con Linux y macOS
El sistema SHALL funcionar con las utilidades estándar de Linux y de macOS, sin depender de herramientas que solo existen en una de las dos plataformas, y sus tests SHALL ejecutarse en ambas.

#### Scenario: Ejecución en macOS
- **WHEN** los hooks se ejecutan en macOS con el `sh`, `tr`, `cut`, `head` y `sed` del sistema, `tmux` y `jq` de Homebrew
- **THEN** el comportamiento es el mismo que en Linux

### Requirement: Hooks sin interferencia ni espera
El sistema MUST NOT bloquear ni alterar ninguna acción de Claude Code ni la decisión de otros hooks, y los hooks síncronos SHALL completarse con baja latencia en cada evento, sin esperar a ningún modelo.

#### Scenario: Hook sobre el envío de un prompt
- **WHEN** el hook se ejecuta al enviar un prompt
- **THEN** no emite decisión ni modifica el prompt, y termina sin esperar la respuesta del modelo

#### Scenario: Latencia
- **WHEN** el hook síncrono se ejecuta contra un tmux en funcionamiento
- **THEN** su duración medida queda por debajo del presupuesto fijado en el diseño
