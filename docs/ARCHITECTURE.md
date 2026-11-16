# ARCHITECTURE — Arquitectura del software

> **Estado:** diseño.
>
> **Implementado:**
> - `HardwareDefinition` y `PortDefinition` (`sim/hardware/`);
> - estructura de carpetas `sim/` · `game/` (ADR 0009, aceptada el 2026-11-15);
> - modelos provisionales y escena de muestra (`assets/models/`, `game/showcase/`);
> - escena provisional;
> - `tests/smoke_test.gd`;
> - `tools/check_project.ps1`.
>
> **Aprobación:**
> - El núcleo de §4 (SimWorld, reloj, comandos/eventos), §7 (guardado), §8 (tiempo) y §10 (entrada) quedan aprobados para el Hito 1 al aprobar el usuario su inicio (2026-11-15).
> - El resto de `[PROPUESTA]` se aprueba con el hito que lo use ([README.md](README.md)).

## 1. Principios

1. **La representación gráfica no controla las reglas técnicas** `[CONFIRMADO]`. Cambiar cámara, personaje o modelo 3D no altera la simulación ([ADR 0003](adr/0003-simulation-decoupled-from-scene.md)).
2. **Todo se simula** `[CONFIRMADO]`. No se ejecutan SO, VM, contenedores ni descargas reales ([ADR 0006](adr/0006-fully-simulated-systems.md)).
3. **Dispositivos definidos por datos reutilizables** `[CONFIRMADO]` ([ADR 0002](adr/0002-data-driven-catalog.md)).
4. **El motor técnico se prueba automáticamente** sin abrir escenas 3D `[CONFIRMADO]`.
5. **Modular e incremental** `[CONFIRMADO]`. Cada módulo entra con pruebas y documentación; nada de cientos de archivos sin motivo.
6. **Nunca fingir** `[CONFIRMADO]`. Si algo no está implementado, el juego lo dice.

## 2. Capas

```
┌────────────────────────────────────────────────────────────────────┐
│ PRESENTACIÓN (Nodos de Godot)                                       │
│ personaje · cámaras · transiciones · interacciones · objetos 3D ·  │
│ vistas cercanas · UI (HUD, cuaderno, escritorio simulado)          │
├──────────────── lee estado / recibe eventos ↑ · envía comandos ↓ ──┤
│ APLICACIÓN (servicios del juego)                                    │
│ sesión de juego · guardado · reloj · localización · ajustes        │
├────────────────────────────────────────────────────────────────────┤
│ SIMULACIÓN (RefCounted puro, sin Node; probado en headless)        │
│ hardware · racks · cableado · electricidad · red · hosts (SO,      │
│ terminal, servicios, paquetes) · inventario · pedidos · economía · │
│ misiones · progresión                                              │
├────────────────────────────────────────────────────────────────────┤
│ DATOS (Resources y ficheros de contenido)                           │
│ catálogo · paquetes de software · misiones · cuaderno · traducciones│
└────────────────────────────────────────────────────────────────────┘
```

**Regla de dependencia:** cada capa solo conoce las inferiores. La simulación no importa nodos, escenas ni UI, y no conoce la cámara ni el personaje.

## 3. Módulos

Estado de todos los módulos: nada implementado, salvo lo indicado en la cabecera.

| Módulo | Responsabilidad | Capa | Depende de | Doc |
|---|---|---|---|---|
| Control del personaje | Mover al personaje por navegación hasta un punto | Presentación | Cámaras (rayos), navegación de Godot | CAMERA_SYSTEM |
| Cámaras | Vista general (zoom, giro, desplazamiento) y anclas | Presentación | — | CAMERA_SYSTEM |
| Transiciones | Interpolar entre vista general y vistas cercanas | Presentación | Cámaras | CAMERA_SYSTEM |
| Interacciones | Selección, acciones, flujo acercarse → enfocar → usar → salir | Presentación | Personaje, Transiciones | INTERACTION_SYSTEM |
| Objetos 3D | Escenas envoltorio de dispositivos y muebles (visual + nodos funcionales) | Presentación | Hardware (lectura) | ART_STYLE · INTERACTION_SYSTEM |
| Inventario | Qué posee el jugador y dónde está cada instancia | Simulación | Hardware | HARDWARE_CATALOG |
| Tienda | Catálogo navegable, carrito y pago (app del escritorio simulado) | Presentación + Simulación | Inventario, Pedidos, Economía | HARDWARE_CATALOG |
| Pedidos | Estado y tiempos de entrega, paquetes | Simulación | Reloj, Inventario | HARDWARE_CATALOG |
| Hardware | Instancias de dispositivos, estado (encendido, averías) | Simulación | Datos (catálogo) | HARDWARE_CATALOG |
| Racks | Ocupación por U, montaje y desmontaje | Simulación | Hardware | HARDWARE_CATALOG |
| Cableado | Cables como instancias, conexiones entre puertos | Simulación | Hardware | NETWORK_SIMULATION |
| Electricidad | Grafo de alimentación, capacidad, encendido | Simulación | Cableado | NETWORK_SIMULATION |
| Motor de red | Enlaces, L2, L3, servicios de red, trazas | Simulación | Electricidad, Cableado, Hosts | NETWORK_SIMULATION |
| Terminal | Intérprete de órdenes sobre un host | Simulación (+ UI) | Hosts | TERMINAL_DESIGN |
| SO simulados (Hosts) | Archivos, usuarios, procesos, servicios, paquetes, configuración de red | Simulación | Motor de red | TERMINAL_DESIGN |
| Servicios | Unidades tipo *init*, comportamiento en red de cada servicio | Simulación | Hosts, Motor de red | TERMINAL_DESIGN · NETWORK_SIMULATION |
| Virtualización simulada | Hosts virtuales sobre hosts físicos (futuro, Etapa 2+) | Simulación | Hosts, Hardware | TERMINAL_DESIGN §12 |
| Economía | Dinero, ingresos y costes | Simulación | — | PROGRESSION |
| Misiones | Definiciones, validadores sobre el estado y recompensas | Simulación + Datos | Todos los consultables | PROGRESSION |
| Tutoriales (Cuaderno) | Contenido, índice, búsqueda, marcadores, niveles de ayuda | Datos + UI | Registro de funcionalidades | TUTORIAL_SYSTEM |
| Guardado | Capturar y restaurar el estado de todos los módulos, versionado | Aplicación | Todos | §7 |

## 4. Núcleo de simulación `[PROPUESTA]`

```
SimWorld
 ├─ clock: SimClock          tiempo de juego, escala ×N, pausa, «saltar hasta evento»
 ├─ rng: RandomNumberGenerator   semilla guardada
 ├─ ids: IdAllocator         ids de instancia int (únicos y estables en la partida)
 ├─ modules: módulos de dominio, cada uno dueño de su parte del estado:
 │    HardwareModule, RackModule, CablingModule, PowerModule, NetworkModule,
 │    HostModule (SO), InventoryModule, OrderModule, EconomyModule,
 │    MissionModule, ProgressionModule
 └─ events: cola de SimEvent emitida tras cada comando o tick
```

**Comandos:** `SimWorld.execute(cmd) -> CommandResult` (`ok`, o `rechazado` con un motivo legible por el jugador). Ejemplos: `PurchaseItems`, `OpenPackage`, `PlaceObject`, `MountInRack`, `ConnectCable`, `PressPowerButton`, `RunShellLine`.
- Toda modificación del estado pasa por un comando. La interfaz nunca toca el estado directamente.
- Los comandos son datos: se pueden registrar para deshacer, reproducir o enviar por red en el futuro (§12).

**Eventos:** hechos ya ocurridos, como `device_powered_on`, `link_state_changed`, `package_delivered`, `money_changed` o `mission_completed`. La presentación se suscribe a ellos para actualizar LED, cables y HUD.

**Consultas:** funciones de solo lectura que usan la UI, las misiones y la terminal: `reachable(a, b)`, `link_state(port)`, `rack_free_slots(rack)`.

**Tiempo:**
- Paso fijo (p. ej. 1 s de juego por *tick*). El juego llama a `advance(delta_real)`, que aplica la escala y ejecuta los *ticks* que correspondan, con un tope por fotograma.
- Las operaciones largas (arranques, instalaciones, transferencias, entregas) son **trabajos** con duración en tiempo de juego que emiten progreso.

**Determinismo:** misma semilla y mismos comandos dan el mismo resultado. No se usa `randf()` global ni el reloj real dentro de la simulación.

**Recalcular solo lo necesario:** cada módulo marca como «sucio» lo que cambió (un cable, una IP) y los datos derivados (dominios L2, alimentación) se recalculan bajo demanda. Se optimiza solo tras medir.

## 5. Presentación `[PROPUESTA]`

- **Escena raíz de partida:** `GameSession` posee el `SimWorld` y llama a `advance()`. Contiene el mundo 3D (sitio y habitaciones), el personaje, el director de cámara, el gestor de interacciones y las capas de UI.
- **Vista de dispositivo** (`DeviceView`): adaptador que, dado un id de instancia, instancia la escena envoltorio del modelo, escucha eventos de ese id (LED, ventiladores, puertos) y traduce clics en comandos. **No guarda estado propio.**
- **Componentes reutilizables** (sin duplicar lógica por dispositivo): `Interactable`, `PortSocket`, `LedIndicator`, `PowerButton`, `CableView`. Las vistas cercanas son **controladores genéricos por modo** (rack, pantalla, caja) que leen los datos del dispositivo. Ver [INTERACTION_SYSTEM.md](INTERACTION_SYSTEM.md).

## 6. Datos `[PROPUESTA]`

| Contenido | Formato | Ubicación propuesta |
|---|---|---|
| Hardware | `.tres` (Resources tipados) | `data/catalog/` |
| Paquetes de software | `.tres` | `data/packages/` |
| Misiones | `.tres` | `data/missions/` |
| Cuaderno | Markdown restringido con metadatos | `data/notebook/<idioma>/` |
| Traducciones | gettext `.po` | `data/i18n/` |
| Órdenes de terminal (ayuda, opciones conocidas) | `.tres` | `data/terminal/` |

Todo contenido se valida con pruebas automáticas: ids únicos, referencias que existen y coherencia con lo implementado.

## 7. Guardado `[CONFIRMADO: versionado y ampliable]` · diseño `[PROPUESTA]`

**Qué se guarda** (lista del usuario): personaje, dinero, experiencia, nivel, misiones, inventario, pedidos, dispositivos, posiciones, cableado, configuraciones de red, archivos simulados, paquetes instalados, servicios, estado de los sistemas y avance educativo.

**Diseño:**
- `SaveService` (aplicación) pide a cada módulo `save_state() -> Dictionary` y luego llama a `load_state(dict)`. **Cada módulo es dueño de su sección.**
- Archivo con cabecera `{format_version, game_version, created_at, play_time, slot_name}` y secciones por módulo, cada una con su propia `version`.
- Las migraciones son funciones encadenadas por versión. Nunca se rompe una partida antigua sin una migración probada.
- **Solo ids y datos planos:** nunca nodos, rutas de escena ni objetos `Resource`. El catálogo se referencia por `id`.
- Formato JSON legible en `user://saves/`. Compresión opcional con `FileAccess.open_compressed` `[VERIFICADO: el método existe en Godot 4.7.2 (sonda ClassDB), 2026-11-15]` si los sistemas de archivos simulados crecen.
- Escritura atómica: se escribe a un temporal y se renombra, con autoguardado rotativo.
- Prueba obligatoria: guardar → cargar → guardar produce **la misma captura**.

**Momento:** cada módulo nace serializable desde el Hito 1. La interfaz de ranuras y carga llega en el Hito 7 ([ROADMAP.md](ROADMAP.md)). Si el guardado se dejara para el final, obligaría a reescribir módulos.

**Implementado:** formato `homelab-tycoon-save` (`sim/core/save_game.gd`). La versión 1 (2026-11-15) es la primera. La versión 2 (2026-11-16) añade la sección `economy` (libro de movimientos e ingresos pasivos), `used` en cada equipo y `rewarded` en la misión. Una partida v1 se migra rellenando valores por defecto y se comprueba en `tests/integration/test_economy.gd`. La versión 3 (2026-11-16) añade la sección `furniture` (sitio y giro de cada mueble) y `furniture` en cada equipo (el mueble con el que va). Una partida v1 o v2 carga con la distribución inicial (`tests/integration/test_furniture.gd`, [ADR 0013](adr/0013-furniture-as-simulation-state.md)). La sección `session` (presentación) guarda además el aspecto del personaje (`appearance`: una opción por ranura). Sin ella, o con valores desconocidos, se usa el aspecto por defecto, que es el de antes ([ADR 0014](adr/0014-title-menu-and-character-look.md)).

## 8. Tiempo de juego `[CONFIRMADO: simplificado, acelerable o saltable]` · diseño `[PROPUESTA]`

- Reloj de juego con escala: pausa, ×1, ×2, ×4 y «saltar hasta el siguiente evento» (p. ej. la entrega), solo cuando no hay nada que el jugador esté haciendo.
- Duraciones en tiempo de juego, definidas en los datos (entrega por clase de envío, arranque por equipo, instalación según tamaño y velocidad de red).
- Escala por defecto a ×1: 1 s real = 1 min de juego. Se ajustará jugando.

## 9. Localización `[CONFIRMADO: es_ES inicial, inglés después]` · diseño `[PROPUESTA]`

- Toda cadena visible usa `tr("CLAVE")`; nada de literales en el código.
- Catálogos gettext (`.po`) por dominio: `ui`, `catalog`, `terminal`, `notebook`. Gettext admite plurales y contexto y es el formato habitual para traductores.
- El cuaderno se escribe por idioma (`data/notebook/es/`, `en/`) en lugar de traducir párrafos sueltos.
- La terminal emula la variable `LANG` del host: ver [TERMINAL_DESIGN.md](TERMINAL_DESIGN.md) §10.

## 10. Entrada y controles `[CONFIRMADO: teclado y ratón; alternativas en el futuro]`

- Acciones con nombre en el *Input Map*: `move_to`, `select`, `context_menu`, `camera_rotate`, `camera_zoom`, `camera_pan`, `close_interaction`, `time_speed_*`.
- **Nunca se leen teclas directamente**, para poder reasignar controles y añadir mando en el futuro.
- La entrada se enruta según el estado de interacción: vista general, vista cercana o UI con foco de texto (la terminal captura el teclado).

## 11. Rendimiento `[PROPUESTA]`

- **Objetivo:** 60 FPS a 1080p en el equipo de referencia (por definir).
- *Tick* de simulación de la Etapa 1 por debajo de 2 ms.
- Carga de partida en menos de 5 s.
- Se mide antes de optimizar. Estructuras indexadas por id y recálculo por cambios (§4).
- Cables y LED baratos de dibujar: mallas generadas una vez y uniforms por instancia ([ART_STYLE.md](ART_STYLE.md) §5).

## 12. Multijugador futuro: impacto por sistema `[CONFIRMADO: documentar, no implementar]`

| Sistema | Qué habría que cambiar | Qué ya ayuda |
|---|---|---|
| Núcleo de simulación | Servidor autoritativo; los clientes envían comandos y reciben eventos y estado | Patrón comando/evento; determinismo; separación de la vista |
| Ids | Asignación centralizada en el servidor | Ids de instancia, no rutas de nodos |
| Tiempo | Acordar pausa y velocidad (votación o anfitrión) | Reloj único en la simulación |
| Interacciones | Bloqueos: dos jugadores en el mismo rack o puerto; reservas temporales | Comandos validados por la simulación |
| Personaje y cámara | Varios personajes; la cámara sigue siendo local | Cámara fuera de la simulación |
| Terminal | Sesiones por jugador; el estado del host es compartido | Sesiones separadas del host |
| Inventario y economía | ¿Compartido o por jugador? Decisión de diseño | Módulo propio |
| Misiones | Recompensas y competencias por jugador | Validadores sobre el estado del mundo |
| Guardado | Partida del anfitrión; identidad de cada jugador | Secciones por módulo |
| UI | Indicadores de qué hace cada compañero | — |

## 13. Estructura de carpetas

**Vigente** `[CONFIRMADO: 2026-11-15]` ([ADR 0009](adr/0009-folder-structure-sim-game.md)): frontera visible entre simulación y presentación, y la presentación agrupada por funcionalidad, con escena y script juntos.

- Aplicada el 2026-11-15: `game/main/`, `game/showcase/`, `sim/hardware/`.
- Las demás carpetas se crean **cuando reciben su primer archivo**, nunca vacías.

Estructura objetivo:

```
sim/                      motor técnico puro (sin Node), probado en headless
  core/ hardware/ racks/ cabling/ power/ network/ hosts/ terminal/
  services/ packages/ inventory/ orders/ economy/ missions/ progression/
game/                     presentación: escenas + scripts juntos por funcionalidad
  session/ world/ character/ camera/ interaction/ devices/ rack/ cabling/
  computer/ notebook/ ui/
data/                     contenido: catalog/ packages/ missions/ notebook/ terminal/ i18n/
assets/ art_source/ tests/ (unit/ integration/ scene/) tools/ docs/ addons/
```

- **Regla verificable por prueba:** nada en `sim/` contiene `extends Node`, `get_node`, `$`, ni carga escenas. La prueba se añade con el *runner* del Hito 1.

**Convenciones de nombres** (vigentes):

| Elemento | Convención | Ejemplo |
|---|---|---|
| Archivos y carpetas | `snake_case` | `server_nx1_1u.tscn` |
| Clases (`class_name`) | `PascalCase` | `HardwareDefinition` |
| Ids de datos | `snake_case`, estables | `switch_16p_basic` |
| Escena ↔ script | Mismo nombre base | `rack.tscn` + `rack.gd` |
| Señales | En pasado | `link_state_changed` |
| Constantes | `UPPER_SNAKE` | `MAX_RACK_UNITS` |

**Carpetas fuera de Godot:** `art_source/`, `docs/` y `tools/` llevan un `.gdignore` vacío, así que Godot no las escanea ni importa. Los `.blend` se exportan a `.glb` ([ART_STYLE.md](ART_STYLE.md) §8).

**Qué se versiona:** código, `.tscn` y `.tres`, `.uid`, `.import`, `assets/`, `addons/godot_ai/` y `docs/`. No se versionan `.godot/` ni `.mcp.json` (ver `.gitignore`).

## 14. Autoloads `[PROPUESTA]`

Mínimos: `GameSession` (o escena raíz sin autoload), `SaveService`, `Settings` y `Localization`. El catálogo vive dentro de la simulación (`CatalogRegistry` que posee el `SimWorld`), no en un autoload global, para que las pruebas lo construyan sin escena.

El plugin Godot AI añade `_mcp_game_helper`, que es **solo de desarrollo** y se excluye de las exportaciones.

## 15. Pruebas

Estrategia y criterios: [TEST_PLAN.md](TEST_PLAN.md).

## 16. Decisiones registradas

| ADR | Decisión | Estado |
|---|---|---|
| [0001](adr/0001-godot-gdscript.md) | Godot 4.7 + GDScript tipado | Aceptada |
| [0002](adr/0002-data-driven-catalog.md) | Catálogo guiado por datos | Aceptada |
| [0003](adr/0003-simulation-decoupled-from-scene.md) | Simulación separada de la escena | Aceptada |
| [0004](adr/0004-godot-ai-mcp-project-scope.md) | Godot AI MCP con scope de proyecto | Aceptada |
| [0005](adr/0005-third-person-camera-closeups.md) | Tercera persona con transiciones a vistas cercanas | Aceptada (usuario, 2026-11-15) |
| [0006](adr/0006-fully-simulated-systems.md) | Todos los sistemas simulados | Aceptada (usuario, 2026-11-15) |
| [0007](adr/0007-spanish-first-localization.md) | Español de España primero, localización preparada | Aceptada (usuario, 2026-11-15) |
| [0008](adr/0008-analytic-network-simulation.md) | Simulación de red analítica con trazas | **Propuesta** |
| [0009](adr/0009-folder-structure-sim-game.md) | Carpetas `sim/` · `game/` · `data/` | Aceptada (usuario, 2026-11-15) |
