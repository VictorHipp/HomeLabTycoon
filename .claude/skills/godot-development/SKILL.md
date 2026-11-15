---
name: godot-development
description: "Úsala al escribir o modificar GDScript, escenas (.tscn), recursos (.tres), señales, shaders o configuración del proyecto Godot 4.7 de HomeLab Tycoon, y para ejecutar, depurar y validar el juego (CLI headless o herramientas Godot AI MCP). No es para decidir reglas de simulación ni datos de hardware (usa homelab-simulation / hardware-catalog)."
---

# Desarrollo en Godot 4.7 (GDScript)

## Antes de empezar

1. Lee `CLAUDE.md` (decisiones confirmadas, reglas de arquitectura y estilo) y el documento dueño del sistema que tocas:
   - personaje y cámara: `docs/CAMERA_SYSTEM.md`;
   - interacciones y vistas cercanas: `docs/INTERACTION_SYSTEM.md`;
   - capas, módulos, guardado y carpetas: `docs/ARCHITECTURE.md`;
   - arte e importación: `docs/ART_STYLE.md`;
   - criterios de aceptación: `docs/TEST_PLAN.md`.
2. Respeta las etiquetas. Lo `[PROPUESTA]` no se implementa sin aprobación del usuario (dos niveles: decisiones de `docs/ROADMAP.md` §5 y diseño del hito al aprobar su inicio; ver `CLAUDE.md`). Lo `[SPIKE]` se valida con un experimento pequeño antes de construir encima, y el resultado se anota en el documento.
3. Comprueba si las herramientas `mcp__godot-ai__*` están disponibles. Si lo están, el editor está abierto: úsalas. Si no, trabaja con ficheros y valida con `tools\check_project.ps1`.

## Patrones del proyecto (diseño en `docs/`)

- **Una sola `Camera3D`**, dirigida por un director de cámara. Las vistas cercanas son **anclas** (`Marker3D` `CAM_<modo>`) en la escena de cada objeto. No crees cámaras por dispositivo.
- **Interacción genérica:** componente `Interactable` + punto `STAND_POINT` + controlador de vista cercana por **modo** (rack, pantalla, caja, inspección, colocación). No escribas lógica de interacción específica de un modelo.
- **Las vistas no guardan estado:** leen la simulación, escuchan eventos y envían comandos.
- **Escena envoltorio por dispositivo:** el modelo visual es un hijo intercambiable; tomas, LED y botones son nodos funcionales.

## Escribir GDScript

- **Tipado estático en todo.** `var count: int = 0`, `func place(def: HardwareDefinition) -> bool:`, `Array[StringName]`. Usa `:=` solo cuando el tipo es evidente por el lado derecho.
- Usa `@export` para datos ajustables desde el inspector y `@onready var _x: Node = $X` para nodos hijos (nunca `$X` repetido en bucles).
- Una responsabilidad por script; si un script supera ~300 líneas, divídelo en componentes (nodos hijos o `RefCounted`).
- `StringName` (`&"id"`) para ids y claves de diccionario que se comparan a menudo.
- Señales: declara con parámetros tipados, nombre en pasado (`link_state_changed(link: Link)`). Conéctalas con `signal.connect(callable)`, nunca con strings.
- No uses `get_node()` con rutas largas entre sistemas distintos: inyecta dependencias (`setup(world)`) o emite señales.
- `await` solo en código de UI/efectos, nunca dentro de la simulación.
- No dejes `print()` de depuración (la única traza deliberada es la línea de arranque de `main.gd`). Para avisos permanentes usa `push_warning()` / `push_error()`.

## Escenas y recursos

- Una escena por entidad reutilizable, con escena y script juntos por funcionalidad en `game/` (p. ej. `game/devices/server_1u_entry/`). El nodo raíz lleva el script principal. Nada de lógica de simulación en `game/`: va en `sim/` ([ADR 0009](../../../docs/adr/0009-folder-structure-sim-game.md)).
- Crea las carpetas cuando reciben su primer archivo; no dejes carpetas vacías.
- Los datos van en `Resource` personalizados (`sim/<dominio>/`, como `sim/hardware/hardware_definition.gd`), no en diccionarios sueltos ni JSON ad hoc.
- Los modelos `.glb` vienen de Blender (`tools/blender/`, `docs/ART_STYLE.md` §8) y se usan como **hijo visual** de una escena envoltorio. Sus marcadores (`PORT_*`, `CAM_*`, `STAND_POINT`…) tienen convenciones de orientación; `tests/check_models.gd` las comprueba.
- Edita `.tscn`/`.tres` **a mano solo para cambios triviales** (valores, rutas) y solo con el editor cerrado. Para estructura de nodos usa el MCP (`node_manage`, `scene_manage`, `batch_execute`).
- No renombres ni muevas archivos fuera del editor/MCP: se rompen los `uid://`. Si es inevitable, muévelo junto con su `.uid` y valida.
- Los `.uid` y `.import` se commitean; `.godot/` no.

## Ejecutar y verificar (obligatorio tras cada cambio)

### Con Godot AI MCP (editor abierto)
1. `project_run` (`mode="main"`, o `mode="custom"` + `scene="res://…"`). Su respuesta ya trae `current_run_errors` y `recent_errors`: **empieza por ahí**.
2. `logs_read` con `include_details=true`. `source="game"` = stdout/stderr del juego; `source="editor"` = errores de parseo/carga y pestaña *Debugger → Errors* (los errores de arranque **no** salen en `game`); `source="all"` junta ambos.
3. Si el juego se para por un error, `game_status.status` pasa a `"break"`: lee el motivo en `game_status.break.reason` y para el juego.
4. `editor_screenshot` para comprobar el resultado visual.
5. `project_manage op="stop"` al terminar; `editor_manage op="logs_clear"` antes de una nueva ronda.

Verificado en este proyecto con una escena de prueba temporal: `push_error` y una llamada a `null` aparecen con archivo, línea y mensaje. Para pruebas transitorias, `filesystem_manage op="write_text"` crea archivos con su limpieza y `op="remove"` los borra (van a la papelera de Windows).

### Sin MCP (CLI, verificado en este equipo)
```powershell
powershell -ExecutionPolicy Bypass -File tools\check_project.ps1        # importa + smoke test + modelos + ejecuta main
godot_console --headless --path . --check-only --script res://game/x.gd      # sintaxis de un script
godot_console --headless --path . --quit-after 300                      # ejecuta la escena principal 300 frames
```
- Los errores salen por stderr con prefijos `SCRIPT ERROR:`, `ERROR:` y `Parse Error`; las rutas y líneas vienen en la línea `at:`.
- **`--import` y ejecutar `main` no revelan errores de parseo en scripts que nadie referencia.** Por eso `tests/smoke_test.gd` carga todos los `.gd/.tscn/.tres` del proyecto. Si añades una carpeta nueva de código, comprueba que el smoke test la cubre.
- No uses `ResourceLoader.CACHE_MODE_IGNORE` sobre el script que se está ejecutando: Godot se cuelga con `0xC0000005`.

## Tests

- Test rápido de humo: `tests/smoke_test.gd` (extiende `SceneTree`, termina con `quit(0|1)`; imprime `SMOKE FAIL: …` por cada fallo).
- Para lógica de simulación, escribe tests de lógica pura (sin escena) y ejecútalos igual: `godot_console --headless --path . --script res://tests/x.gd`. Godot AI también ofrece `test_run`.
- No añadas frameworks de test (GUT, gdUnit) sin justificarlo y pedir autorización.

## Trampas habituales

- Autoloads: el plugin Godot AI añade `_mcp_game_helper`; no lo borres mientras desarrollas, pero no debe ir en exportaciones.
- `DirAccess` sobre `res://` en un juego exportado ve archivos `.remap`; carga recursos por ruta conocida o usa un índice, no escanees directorios en runtime.
- `rotation_degrees` escrito a mano en un `.tscn` se aplica al cargar (verificado en `tests/smoke_test.gd` con la luz `Sun`).
- Los `class_name` se registran globalmente: un nombre duplicado rompe el proyecto entero. Prefijo `Mcp*` está reservado por el plugin.
- Godot en esta máquina muestra los mensajes de progreso en español; los prefijos de error (`ERROR:`, `SCRIPT ERROR:`) son siempre en inglés.
- Si dudas de una API de 4.7, **verifica ejecutándola** (script de prueba headless) antes de asumirla; no la inventes.

## Checklist de cierre

- [ ] `check_project.ps1` → `CHECK PASSED` (o `logs_read` sin errores tras `project_run`)
- [ ] Tipado estático completo, sin `print()` sueltos
- [ ] Datos de gameplay en recursos, no hardcodeados
- [ ] Sin cambios accidentales en `project.godot` / `addons/`
- [ ] Documentación actualizada si cambió una decisión de arquitectura (ADR)
