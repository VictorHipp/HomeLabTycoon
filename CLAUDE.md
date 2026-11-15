# HomeLab Tycoon — instrucciones permanentes

Simulador 3D de construcción y administración de infraestructura informática. El jugador empieza en su habitación con un ordenador antiguo y una conexión doméstica, y progresa hasta centros de datos. Se **aprende construyendo** sistemas que funcionan: comprar, desembalar, montar, cablear, configurar y diagnosticar.

**Visión oficial:** documento maestro del usuario (2026-11-15), resumido en `docs/GDD.md`.

## Estado actual

- **Hito 0 (entorno) completado.**
- **Hito 1 iniciado el 2026-11-15** (aprobado por el usuario).
  - **Hecho:** reestructuración de carpetas (`sim/`, `game/`) y *spike* visual con 16 modelos provisionales.
  - **Pendiente:** director de cámara, personaje con navegación, corte de paredes, *runner* de pruebas y esqueleto de simulación y guardado (`docs/ROADMAP.md` §2).
- **Código existente:**
  - escena provisional `game/main/main.tscn`;
  - `HardwareDefinition` y `PortDefinition` (`sim/hardware/`) y un item de catálogo;
  - escena de muestra de modelos `game/showcase/model_showcase.tscn` (herramienta de desarrollo);
  - modelos `.glb` en `assets/models/` generados por `tools/blender/build_prototype_models.py` (fuentes `.blend` en `art_source/`);
  - pruebas `tests/smoke_test.gd` y `tests/check_models.gd`.
- **El resto de `docs/` es diseño.**

## Decisiones confirmadas por el usuario (reglas vigentes)

1. **Tercera persona elevada** (tres cuartos, zoom y giro, clic para mover). Al interactuar, la cámara se acerca con una transición fluida y rápida a una **vista cercana**. Parece primera persona solo durante la interacción ([ADR 0005](docs/adr/0005-third-person-camera-closeups.md)).
2. **Estilo 3D low-poly estilizado, semi-cartoon, original.** Modelos provisionales hasta tener los definitivos ([ART_STYLE](docs/ART_STYLE.md)).
3. **Todo simulado.** Sin SO, VM, contenedores ni descargas reales ([ADR 0006](docs/adr/0006-fully-simulated-systems.md)).
4. **Terminal profunda y persistente sobre estado simulado.** Lo no implementado **se declara**, nunca se finge.
5. **Motor de red separado de la vista**, probado sin escena, incremental. Nada se comunica «por magia».
6. **Cableado interactivo y técnicamente relevante** (sistema prioritario).
7. **Catálogo por datos**, con productos ficticios de especificaciones coherentes.
8. **Progresión en 6 etapas** (Hogar → Centros de datos). Dinero, nivel, XP, reputación, competencias **demostradas** y desbloqueos. Sin esperas artificiales ni farmeo. Modos **Carrera, Sandbox y Desafíos técnicos**.
9. **Misiones validadas por el estado** de la infraestructura, con varias soluciones válidas.
10. **Cuaderno voluntario** con tres niveles de ayuda (información, pistas, tutorial), ligado a lo realmente implementado.
11. **Tiempos simplificados pero creíbles**, acelerables o saltables.
12. **Español de España** primero, localización preparada; **Windows** primero; sin monetización ([ADR 0007](docs/adr/0007-spanish-first-localization.md)).
13. **Un jugador.** El impacto de un futuro multijugador está documentado, no implementado.
14. **Guardado versionado y ampliable.**
15. **Método:** hitos pequeños con versión jugable, pruebas, documentación, Git y nada de herramientas innecesarias.
16. **Juego extenso** (2026-11-15): muchas partes (etapas → capítulos → misiones, más metas de carrera), con puntos y recompensas. **Los créditos ganados se gastan en la tienda para comprar material nuevo** (`docs/PROGRESSION.md` §10).
17. **Decisiones de `docs/ROADMAP.md` §5 confirmadas el 2026-11-15:** todas las recomendaciones salvo la 5 (tipografías: no se descarga ninguna) y la 18 (subagente). La identidad visual (16) está aprobada.
18. **Prueba jugable de la primera misión** (2026-11-15): misión completa con tienda, personaje que camina y giro de cámara con el ratón, **sin cuaderno ni guardado** por ahora.
19. **Git/GitHub:** repositorio **público** https://github.com/VictorHipp/HomeLabTycoon (`origin`, rama `main`).
    - Identidad solo de este repo: `VictorHipp` con el correo *noreply* de GitHub. No uses otra.
    - Antes de cada push: comprueba que no se suben datos personales y respeta las licencias de terceros (el addon `godot_ai` es MIT y lleva su `LICENSE`).
    - Commit y push al cerrar cada etapa estable, con `check_project.ps1` en verde.

## Propuestas: cómo se aprueban

Lo marcado `[PROPUESTA]` en `docs/` se aprueba en **dos niveles**:

1. **Decisiones individuales:** la lista numerada de `docs/ROADMAP.md` §5, agrupada por el hito que la necesita. Cada una requiere una **respuesta explícita** del usuario antes de empezar ese hito.
2. **Diseño por defecto de un hito:** el resto de `[PROPUESTA]` de los documentos que usa un hito. Queda aprobado cuando el usuario **aprueba empezar ese hito**, tras leer su resumen. Si durante el hito algo de ese diseño resulta inviable o hay que cambiarlo de forma importante, se consulta antes de cambiarlo.

**Nada `[PROPUESTA]` se implementa antes de esa aprobación.** Tras aprobar, cambia la etiqueta a `[CONFIRMADO: fecha]` en el documento dueño.

## Stack (verificado en el Hito 0)

| Pieza | Versión / ubicación |
|---|---|
| Motor | Godot **4.7.2 stable**, GDScript, renderer Forward+ |
| Godot AI (MCP) | plugin v4.4.1 en `addons/godot_ai/`; servidor lanzado por `uvx` |
| Runtime del servidor | uv 0.13.8 (gestiona su propio Python 3.11) |
| Modelado 3D | Blender 5.3.0 — `C:\Program Files\Blender Foundation\Blender 5.3\blender.exe` (no está en PATH) |
| Control de versiones | Git, rama `main` (sin commits todavía) |
| Shell | Windows PowerShell 5.1: no uses `&&`, `\|\|` ni `2>&1` con ejecutables nativos |

Ejecutables de Godot (shims de winget): `godot` (GUI) y `godot_console` (consola, para scripts). En una shell abierta antes de instalar, el PATH no los incluye: usa `tools\godot-common.ps1`, que lo reconstruye.

## Idioma

- Conversación con el usuario y documentación: **español de España**.
- Código, identificadores, comentarios de código y mensajes de commit: **inglés**.
- Todo texto visible para el jugador pasa por `tr("CLAVE")`; nada de cadenas de interfaz literales en el código.

## Comandos esenciales

```powershell
# Validar sin abrir el editor (importa, smoke test, ejecuta la escena principal)
powershell -ExecutionPolicy Bypass -File tools\check_project.ps1

# Abrir el editor (cwd correcto, PATH refrescado, telemetría de Godot AI desactivada)
powershell -ExecutionPolicy Bypass -File tools\open_editor.ps1

# Sintaxis de un único script
godot_console --headless --path . --check-only --script res://game/ruta.gd

# Regenerar los modelos provisionales con Blender (los .glb se reimportan con check_project)
& "C:\Program Files\Blender Foundation\Blender 5.3\blender.exe" --background --factory-startup `
    --python tools\blender\build_prototype_models.py -- --root . [--only id1,id2]

# Ver la muestra de modelos (ventana) / generar capturas en docs\images\showcase\
powershell -ExecutionPolicy Bypass -File tools\view_showcase.ps1
powershell -ExecutionPolicy Bypass -File tools\capture_showcase.ps1
```

`check_project.ps1` incluye `tests/check_models.gd`, que comprueba tamaño en metros, Y hacia arriba, marcadores (`PORT_*`, `CAM_*`…) y su orientación.

`check_project.ps1` **debe terminar en `CHECK PASSED` antes de dar una tarea por hecha**. Detecta errores de parseo de cualquier `.gd` propio, porque `--import` y ejecutar la escena no parsean scripts que nadie referencia.

## Documentación (`docs/`)

Índice, vocabulario común y etiquetas en `docs/README.md`. Un documento dueño por tema:

| Documento | Tema |
|---|---|
| `GDD.md` | Visión y sistemas de juego |
| `ART_STYLE.md` | Arte y flujo Blender → Godot |
| `ARCHITECTURE.md` | Software, guardado, carpetas |
| `CAMERA_SYSTEM.md` | Cámara y movimiento |
| `INTERACTION_SYSTEM.md` | Interacciones |
| `HARDWARE_CATALOG.md` | Catálogo, tienda, inventario |
| `NETWORK_SIMULATION.md` | Electricidad, cableado y red |
| `TERMINAL_DESIGN.md` | SO simulado y terminal |
| `TUTORIAL_SYSTEM.md` | Cuaderno |
| `PROGRESSION.md` | Economía, etapas y misiones |
| `TECH_RESEARCH.md` | Investigación |
| `ROADMAP.md` | Hitos |
| `TEST_PLAN.md` | Pruebas |
| `DEVELOPMENT_WORKFLOW.md` | Herramientas |
| `adr/` | Decisiones registradas |

**Etiquetas:** `[CONFIRMADO]` (usuario), `[PROPUESTA]` (pendiente), `[SPIKE]` (experimento por hacer), `[VERIFICADO: fuente, fecha]`, `[POR VERIFICAR]`.

**Un dato `[POR VERIFICAR]` no se usa en reglas del simulador ni en el cuaderno.** Antes hay que verificarlo según `docs/TECH_RESEARCH.md`.

## Reglas de arquitectura

**Confirmadas por el usuario** (documento maestro):
1. **La simulación no depende de la vista.** Nada en `sim/` usa `Node`, `SceneTree`, `$`, `get_node` ni carga escenas. La presentación vive en `game/` y lee estado, escucha eventos y envía comandos ([ADR 0003](docs/adr/0003-simulation-decoupled-from-scene.md), [ADR 0009](docs/adr/0009-folder-structure-sim-game.md)).
2. **Datos fuera del código.** Precios, unidades U, vatios, puertos, paquetes, misiones y textos del cuaderno van en datos (`data/`).
3. **No duplicar lógica por dispositivo.** Los componentes y los controladores de vista cercana son genéricos y leen datos.
4. **Honestidad.** Nunca se aparenta que algo funciona. Lo no implementado se declara (terminal, cuaderno, interfaz).

**Convenciones técnicas del Hito 0** (propuestas por Claude al preparar el entorno; vigentes salvo que el usuario diga otra cosa):
5. **Señales hacia arriba, llamadas hacia abajo.** Autoloads mínimos (`docs/ARCHITECTURE.md` §14).
6. **Simulación determinista.** Paso fijo, RNG con semilla propia, sin `randf()` global ni reloj real dentro de la simulación.
7. **Ids estables.** `StringName` snake_case en los datos. No se guardan nodos ni rutas de escena.
8. **Dinero siempre entero.**

**Confirmada el 2026-11-15** (decisión 20 de `docs/ROADMAP.md` §5):
9. Cada módulo nace serializable (`save_state` / `load_state`) desde el Hito 1, aunque la interfaz de guardado llegue en el Hito 7.

## Estilo GDScript

- Tipado estático **en todo**: variables, parámetros y retornos. Arrays tipados.
- Archivos y variables `snake_case`; clases `PascalCase`; constantes `UPPER_SNAKE`; señales en pasado; miembros privados con `_`.
- Un `class_name` por archivo. Orden: `class_name`, `extends`, docstring `##`, señales, enums, constantes, `@export`, variables, `_ready`, métodos públicos, privados.
- Tabuladores (`.editorconfig`); líneas de 100 columnas como máximo; composición antes que herencia profunda.

## Flujo con Godot AI MCP

- El MCP **vive en el editor**: las herramientas `mcp__godot-ai__*` solo funcionan con el editor abierto (`tools\open_editor.ps1`) y tras aprobar el servidor en Claude Code.
- **Con MCP:** `project_run`; empieza por `current_run_errors`; luego `logs_read` (`source="editor"` para errores de arranque y parseo); y `editor_screenshot` para comprobar lo visual.
- **Sin MCP:** ficheros y `tools\check_project.ps1`.
- No edites `project.godot` ni escenas abiertas a mano con el editor abierto.
- `addons/godot_ai/`: no se modifica; se actualiza con el botón *Update* del dock.
- `.mcp.json` es local (en `.gitignore`); se regenera con *Configure* en el dock (scope `project`).
- El plugin añade el autoload `_mcp_game_helper`: **solo desarrollo**, excluir de las exportaciones.

## Git

- Commits pequeños, en inglés, con prefijo convencional (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`, `test:`).
- Nunca se versionan `.godot/` ni `.mcp.json`. Los `.uid` e `.import` sí.
- **Commits y push:** el usuario pidió (2026-11-15) guardar en local y en su GitHub. Haz commit y push al cerrar cada etapa estable, con `check_project.ps1` en verde. **No** cambies la configuración de Git (identidad, remotos) ni hagas `push --force` sin que lo pida.

## Skills del proyecto (`.claude/skills/`)

| Skill | Úsala para… |
|---|---|
| `godot-development` | GDScript, escenas, recursos, cámara, interacciones; ejecutar y validar con Godot y el MCP |
| `hardware-catalog` | Añadir o modificar equipos del catálogo; esquema, ids, equilibrio |
| `homelab-simulation` | Electricidad, cableado, red, hosts simulados, terminal, servicios, paquetes, guardado del estado |
| `game-design` | Mecánicas, progresión, misiones, UX, alcance, evaluar ideas nuevas |

## Reglas de trabajo

- **Antes de implementar un hito:**
  - lee su sección en `docs/ROADMAP.md`, sus criterios en `docs/TEST_PLAN.md` y los documentos dueño de los sistemas que tocas;
  - investiga primero los temas P0 que necesita (`docs/TECH_RESEARCH.md`).
- **Cambios pequeños y verificables:** implementar → pruebas → `check_project.ps1` (o `project_run` + `logs_read`) → corregir → resumir.
- **Si un cambio contradice una decisión,** escribe un ADR nuevo en `docs/adr/` en vez de saltártela.
- **No instales** software, addons, plugins, fuentes, servidores MCP ni servicios externos sin explicar su utilidad y consecuencias y obtener autorización explícita.
- **No añadas cientos de archivos sin razón;** nada de dispositivos decorativos sin función técnica.
- **Si algo no se pudo verificar, dilo claramente.**
