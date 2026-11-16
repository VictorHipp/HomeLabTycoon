# TEST_PLAN — Pruebas y criterios de aceptación

> **Estado:**
> - **Existe hoy:**
>   - `tests/smoke_test.gd`: carga todos los `.gd`, `.tscn` y `.tres` propios y comprueba el catálogo y la escena principal;
>   - `tests/check_models.gd`: tamaño en metros, Y hacia arriba, marcadores y su orientación en cada `.glb`;
>   - `tests/run_tests.gd`: *runner* propio (decisión 4) con pruebas sin ventana (`tests/unit/`, `tests/integration/`): IPv4, catálogo y fichas de la tienda, frontera `sim/`, terminal, cámara, la misión completa con dos soluciones y casos negativos, la colocación del rack (espacio de trabajo, alcance del cable de corriente, mover y recoger), entregas, guardado (también de partidas v1), recorridos de cable ordenados en otra sala, cableado guiado y cancelación, y la economía (libro que cuadra, XP una vez, ingresos pasivos con tope, segunda mano siempre con pérdida);
>   - `tools/check_project.ps1`: importación, smoke test, modelos, pruebas y ejecución de la escena principal; falla con cualquier `ERROR`;
>   - `tools/walkthrough.ps1`: recorrido automático de la primera misión **solo por la vía de entrada real**. No llama directamente a ningún método del juego; usa:
>     - clics sintéticos sobre posiciones 3D proyectadas;
>     - clics en el centro de los botones reales, comprobando que emiten `pressed`;
>     - órdenes tecleadas tecla a tecla con Enter;
>     - arrastre con el botón derecho y con el central (el giro cambia y el siguiente clic izquierdo sigue caminando).
>
>     Ejecuta 4 escenarios de colocación del rack. Cada escenario debe terminar con la misión completada, y el script falla si no llega a la línea `WALKTHROUGH <escenario> OK`:
>     - `basic`: además gira la cámara arrastrando mientras coloca;
>     - `wall`: rechazo con motivo y giro; al final, epílogo con «Desconectar todos los cables», «Recoger rack» rechazado con motivo, «Desmontar» ×2 y «Recoger rack»;
>     - `far`: el cable no llega, se desconecta con clic derecho y se mueve el rack;
>     - `blocking`: «no puedo llegar» y se mueve el rack con clic derecho.
>     - `furniture` (2026-11-16, sin misión): reorganiza la habitación con clics reales. Mueve la alfombra, la cama (antes, un rechazo sobre el escritorio), la mesilla con el router, el escritorio girado con el PC y la regleta, y el router al escritorio (antes, un rechazo en el sitio del monitor). Después comprueba que todo se dibuja donde dice la simulación, que nada atraviesa nada y que ningún cable atraviesa otro. Luego usa el PC (ping al router), abre de cerca el router y guarda, cambia y carga la distribución.
>
>     En todos (2026-11-16): anillo bajo el puntero en cada clic y rojo en un clic en el vacío; ficha de producto (foto, miniatura, especificaciones, opiniones) y compra por la cesta; guía del cable «Paso 1 de 2 / 2 de 2», tomas iluminadas y flechas; cada cable dibujado se recorre con una esfera de su radio contra muebles, paredes, rodapié y equipos, y ningún equipo, monitor, teclado ni pila de cajas atraviesa otro objeto. En `basic`, además: un cable a medias se cancela al sentarse al ordenador y otro con Esc; ingreso pasivo cobrado a la hora con ×4; «Mi cuenta»; venta en «Segunda mano». En `wall`, el rack junto a la pared necesita los cables de corriente de 5 m.
>
>     Guarda capturas y un registro en `build/walkthrough/` (sin versionar). Comprobado a 1600×900 (`play.ps1`) y a 1280×720 (F5 en el editor) con `-Resolution`.
>   - `tools/play.ps1`: comprobado a mano (2026-11-15). El proceso sigue vivo, la ventana responde y el registro `user://logs/godot.log` sale sin errores;
>   - `tools/capture_showcase.ps1`: capturas para la revisión visual.
> - **Diseño:** todo lo demás.

## 1. Principios `[CONFIRMADO]`

- Desarrollo con pruebas: el motor técnico se prueba **automáticamente, sin escena 3D**.
- Comprobar el comportamiento en Godot, revisar errores y documentar las limitaciones.
- **Nunca** dar por implementada una mecánica que no funciona de verdad.

## 2. Niveles de prueba `[PROPUESTA]`

| Nivel | Qué cubre | Cómo | Cuándo |
|---|---|---|---|
| Unitarias | Módulos de `sim/` (reglas, comandos, consultas), órdenes de terminal, conversores (cuaderno), validadores de datos | *Runner* *headless*, sin nodos | En cada cambio |
| Integración | Escenarios completos de simulación: montar, cablear, encender, configurar, `ping`; misiones con varias soluciones; guardar/cargar | *Runner* *headless* con constructor de escenarios | En cada cambio |
| Escena | Las escenas cargan, sus nodos funcionales existen (tomas = puertos del catálogo), director de cámara, movimiento del personaje en *headless* con física avanzando | Scripts `SceneTree` que instancian y hacen avanzar fotogramas | En cada cambio |
| Aceptación interactiva | Lo visual y la sensación: transiciones, legibilidad, cables | Con el editor abierto, `project_run` + `editor_screenshot` + `logs_read` (Godot AI MCP); y prueba manual | Al cerrar cada hito |
| Usuario | Lista de comprobación jugable (§5) | El usuario juega | Al cerrar cada hito |
| Rendimiento | FPS, tiempo de *tick*, carga | Medición en escenas de estrés | Hitos 4, 5 y 7 |

## 3. Herramientas y convenciones `[PROPUESTA]`

**Runner** (decisión 4 de [ROADMAP.md](ROADMAP.md) §5): `tests/run_tests.gd`, propio y mínimo, sin addons.
- Descubre `tests/unit/**/test_*.gd` y `tests/integration/**/test_*.gd`, que extienden una clase base `TestCase` con `assert_*`.
- Ejecuta los métodos `test_*`, informa de cada fallo con archivo, línea y mensaje, y termina con código 0 o 1.
- `check_project.ps1` lo ejecuta como un paso más.
- Alternativa: GUT, un addon externo que requiere aprobación.

**Constructor de escenarios:** API de pruebas para montar un mundo en pocas líneas.

```gdscript
var w := Scenario.new().room().device(&"pc", &"pc_old").device(&"sw", &"switch_16p") \
	.cable(&"pc:eth0", &"sw:1", &"cable_cat6_3m").power_all().build()
```

**Convenciones:**
- **Determinismo:** semillas fijas; ninguna prueba depende del reloj real.
- **Salidas de referencia («golden»):** en `tests/golden/` para la terminal y las trazas de red. Cambiar una referencia exige revisar el diff.
- **Regresión:** cada error corregido añade una prueba que lo reproduce.
- **Frontera simulación/vista:** una prueba falla si algo en `sim/` contiene `extends Node`, `get_node`, `$` o carga escenas.
- **Errores visibles:** el *runner* y `check_project.ps1` tratan cualquier `SCRIPT ERROR` o `ERROR` como fallo.

**Pruebas de honestidad** (específicas de este proyecto):
1. Toda orden implementada tiene manual, pruebas y entrada del cuaderno.
2. Toda orden u opción citada en el cuaderno o en el manual está implementada.
3. Toda orden real no implementada responde con el mensaje honesto ([TERMINAL_DESIGN.md](TERMINAL_DESIGN.md) §6).
4. Todo `requires_features` del cuaderno existe en el registro de funcionalidades.
5. Catálogo válido ([HARDWARE_CATALOG.md](HARDWARE_CATALOG.md) §9).
6. Toda misión tiene al menos dos soluciones probadas.

## 4. Criterios de aceptación por hito

Identificadores `H<hito>-<nn>`. Tipo de comprobación: **A** = automática, **M** = manual o MCP.

### Hito 1 — Habitación, cámara y movimiento

| Id | Criterio | Tipo |
|---|---|---|
| H1-01 | La escena de partida carga sin errores ni avisos nuevos | A |
| H1-02 | La cámara arranca en vista de tres cuartos con el personaje en pantalla | A (proyección del personaje dentro del encuadre) + M |
| H1-03 | Zoom, giro e inclinación respetan los límites; el foco no sale de la habitación | A |
| H1-04 | Clic en un punto alcanzable: el personaje llega a ≤ 0,2 m en un tiempo razonable sin atravesar obstáculos | A (física en *headless*) |
| H1-05 | Clic en un punto inalcanzable: aviso y sin movimiento | A |
| H1-06 | Las paredes que miran a la cámara se cortan; los tres modos funcionan | M |
| H1-07 | 60 FPS en la habitación a 1080p en el equipo de desarrollo | M |

### Hito 2 — Interacción y transiciones

| Id | Criterio | Tipo |
|---|---|---|
| H2-01 | Pasar el ratón resalta el objeto y muestra nombre y estado | M |
| H2-02 | Clic: el personaje va al punto de interacción y mira al objeto | A |
| H2-03 | La transición termina exactamente en el ancla, sin saltos (posición continua y monótona en el tiempo) y en ≤ 0,8 s | A |
| H2-04 | `Esc` devuelve la cámara a la pose de vista general guardada | A |
| H2-05 | «Reducir movimiento» sustituye el viaje por un fundido | A + M |
| H2-06 | Pantalla del PC a pantalla completa, texto nítido a 1080p, ratón y teclado funcionan | M (*spike* S2) |
| H2-07 | Vista de rack: frontal y trasera, desplazamiento por U | M |

### Hito 3 — Tienda, inventario y colocación

| Id | Criterio | Tipo |
|---|---|---|
| H3-01 | El catálogo del prototipo pasa el validador | A |
| H3-02 | La tienda lista los productos por categoría con precio y ficha, desde los datos | A + M |
| H3-03 | Pagar descuenta el importe exacto; sin saldo, rechazo con motivo | A |
| H3-04 | El pedido cambia de estado con el reloj; «saltar» lleva a la entrega | A |
| H3-05 | El paquete aparece en el punto de entrega con las instancias correctas | A + M |
| H3-06 | Abrir y recoger pasa las instancias al inventario | A |
| H3-07 | Colocar valida solapes y superficie; el objeto queda en el estado con su posición | A |
| H3-08 | Tras colocar, la navegación se actualiza y el personaje rodea el objeto | A |

### Hito 4 — Racks, puertos y cableado

| Id | Criterio | Tipo |
|---|---|---|
| H4-01 | Montar respeta la ocupación por U, la cabida y la profundidad; rechazo con motivo | A |
| H4-02 | Desmontar con cables conectados avisa o impide | A |
| H4-03 | Cada escena de dispositivo tiene tantas tomas como puertos su definición | A |
| H4-04 | Cable: solo puertos compatibles; la longitud insuficiente se rechaza con la longitud necesaria | A |
| H4-05 | Un extremo pendiente persiste y se completa en otro equipo | A + M |
| H4-06 | Los cables se ven, se desconectan y vuelven al inventario | M |
| H4-07 | 200 cables en escena mantienen el objetivo de FPS | M (*spike* S4) |

### Hito 5 — Motor de red y encendido

| Id | Criterio | Tipo |
|---|---|---|
| H5-01 | Sin cable de alimentación no enciende; con él, arranca en el tiempo previsto | A |
| H5-02 | Enlace ACTIVO solo si se cumplen las condiciones de NETWORK_SIMULATION §5; si no, el motivo correcto | A (tabla de casos) |
| H5-03 | La velocidad negociada es la mayor común, limitada por el cable | A |
| H5-04 | Dos hosts en la misma subred y el mismo switch: `ping` OK; quitar un cable, apagar el switch o cambiar de subred lo rompe con el paso de fallo correcto en la traza | A (*golden*) |
| H5-05 | DHCP: el PC obtiene una IP del rango si hay camino L2 con el router | A |
| H5-06 | Los LED de alimentación y de puerto reflejan el estado simulado | A (eventos) + M |
| H5-07 | Misma semilla y mismos comandos dan la misma captura | A |

### Hito 6 — Terminal

| Id | Criterio | Tipo |
|---|---|---|
| H6-01 | Cada orden del prototipo pasa sus pruebas unitarias y *golden* | A |
| H6-02 | Lexer y parser: comillas, escapes, `;`, `&&`, `\|\|`, redirecciones; errores de sintaxis como en bash | A |
| H6-03 | 10 000 líneas aleatorias no cuelgan ni rompen el intérprete | A |
| H6-04 | Órdenes y opciones no implementadas responden con el mensaje honesto | A |
| H6-05 | Crear un archivo → guardar → cargar → existe con el mismo contenido y permisos | A |
| H6-06 | `ip address add` en el servidor y `ping` desde el PC funcionan solo con todo correcto (integración con el motor) | A |
| H6-07 | La terminal es legible y cómoda (historial con flechas, copiar y pegar) | M |

### Hito 7 — Misión, cuaderno, recompensas y guardado

| Id | Criterio | Tipo |
|---|---|---|
| H7-01 | «Primer servidor» se completa con dos soluciones distintas y no se completa si falta cualquier requisito | A |
| H7-02 | Las recompensas se aplican una sola vez y la competencia queda registrada | A |
| H7-03 | Cuaderno: índice, búsqueda (sin tildes ni mayúsculas), enlaces, marcadores e historial | A + M |
| H7-04 | Pruebas de honestidad del cuaderno en verde | A |
| H7-05 | Guardar → cargar → guardar produce una captura idéntica; el archivo lleva la versión | A |
| H7-06 | Cargar restaura personaje, dinero, inventario, posiciones, cableado, IP, archivos y misión | A + M |
| H7-07 | Recorrido completo de los 20 puntos sin errores en `logs_read` | M |

## 5. Cómo comprobarlo tú (al cerrar cada hito)

1. Ejecuta `powershell -ExecutionPolicy Bypass -File tools\check_project.ps1`. Debe terminar en `CHECK PASSED`.
2. Abre el juego (`tools\open_editor.ps1` y luego F5, o desde el editor).
3. Sigue la **lista de comprobación del hito**, que Claude entrega al cerrarlo: pasos jugables y lo que debes ver.

   Ejemplo del Hito 1:
   - «Gira con Q/E; acerca con la rueda; haz clic junto a la cama: el personaje la rodea; haz clic dentro del armario: aviso».
4. Si algo falla, anota qué hiciste y qué esperabas (§6).

## 6. Informe de errores

Plantilla:
- **Hito y versión:**
- **Pasos:**
- **Resultado esperado:**
- **Resultado obtenido:**
- **Captura o mensaje:**
- **¿Se repite siempre?**

Cada error corregido añade su prueba de regresión.

## 7. Integración continua `[PROPUESTA]`

Por ahora, `check_project.ps1` en local antes de cada commit. Cuando exista un repositorio remoto, la misma comprobación en *headless* en un servicio de CI. Requiere aprobación: implica un servicio externo.
