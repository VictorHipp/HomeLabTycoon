# DEVELOPMENT_WORKFLOW — Flujo de desarrollo

> Antes era `docs/architecture/05-development-workflow.md`. Contiene los hechos verificados al preparar el entorno (Hito 0, 2026-11-15).

## Entorno (verificado el 2026-11-15)

| Herramienta | Versión | Cómo se obtiene |
|---|---|---|
| Godot | 4.7.2 stable | `winget install --id GodotEngine.GodotEngine` (zip portable; shims `godot`, `godot_console`) |
| uv / uvx | 0.13.8 | `winget install --id astral-sh.uv` |
| Godot AI (plugin) | 4.4.1 | release de GitHub `hi-godot/godot-ai`, asset `godot-ai-v4-plugin.zip`; sha256 del zip y de cada uno de sus 325 archivos verificados contra el `manifest.json` de la release (la **firma** del manifest no se verificó) |
| Blender | 5.3.0 | `winget install --id BlenderFoundation.Blender` (MSI, requiere elevación) |
| Git | 2.56 | ya instalado |

Si una herramienta no se encuentra en PATH tras instalarla, abre una shell nueva o ejecuta `tools\open_editor.ps1`, que reconstruye PATH desde el registro.

## Bucle de trabajo diario

1. `tools\open_editor.ps1` (abre el editor con el cwd correcto y la telemetría de Godot AI desactivada).
2. Claude Code se lanza **desde la raíz del proyecto** (`C:\A_HomLab\HomeLabTycoon`) para que lea `CLAUDE.md`, `.claude/skills/` y `.mcp.json`.
3. Cambio → `project_run` → `logs_read` → corregir → repetir.
4. `tools\check_project.ps1` en verde antes de terminar.
5. Commit (cuando el usuario lo pida).

## Documentación

- **Índice, vocabulario y etiquetas:** [README.md](README.md).
- **Al terminar una tarea:**
  - actualiza el documento dueño del tema;
  - si cambia una decisión que afecta a varios sistemas, añade un ADR en [adr/](adr/);
  - si un `[SPIKE]` se resuelve, anota el resultado en su documento.
- **Las propuestas** (`[PROPUESTA]`) no se implementan hasta que el usuario las aprueba. Hay dos niveles: decisiones individuales de ROADMAP §5, y diseño por defecto del hito, que se aprueba al aprobar el hito (ver [README.md](README.md)). Cuando se aprueban, la etiqueta pasa a `[CONFIRMADO]`, con la fecha.

## Godot AI MCP

- **Arquitectura:** plugin en el editor ⇄ WebSocket `127.0.0.1:9500` ⇄ servidor Python (HTTP `127.0.0.1:8000`, autenticado) ⇄ cliente MCP (Claude Code) mediante `godot-ai attach` por stdio. Todo en loopback.
- **Scope de proyecto:** el ajuste de editor `godot_ai/mcp_client_scope = project` hace que *Configure* ejecute `claude mcp add --scope project …`, que escribe `.mcp.json` en el **directorio de trabajo del editor**. Por eso el editor se abre siempre con `tools\open_editor.ps1`.
- **Primera vez en Claude Code:** aprobar el servidor `godot-ai` del proyecto cuando `claude` lo pregunte; si no aparecen las herramientas, reiniciar la sesión.
- **Actualizar el plugin:** solo con el botón *Update* del dock. Nunca extraer un zip encima.
- **Telemetría:** el plugin la tiene activada por defecto; aquí está desactivada (`godot_ai/telemetry_enabled = false` en los ajustes del editor y `GODOT_AI_DISABLE_TELEMETRY=1` en `open_editor.ps1`).
- **Solo desarrollo:** `addons/godot_ai/` y el autoload `_mcp_game_helper` no deben ir en una exportación.

## Validación por línea de comandos

`tools\check_project.ps1` ejecuta tres pasos y falla (exit 1) si cualquiera imprime errores:

1. `--import` (importa recursos, registra clases globales).
2. `tests/smoke_test.gd`: carga **todos** los `.gd/.tscn/.tres` del proyecto (salvo `addons/`) y comprueba el catálogo y la escena principal.
3. Ejecuta la escena principal 120 frames (`--quit-after`).

Dato verificado: `--import` y ejecutar la escena principal **no** detectan errores de parseo en scripts sin referencias; solo el paso 2 lo hace.

## Modelos 3D (Blender → Godot)

Flujo en [ART_STYLE.md](ART_STYLE.md) §8; resultado del primer *spike* en §11.

```powershell
# Regenerar todos los modelos provisionales (o solo algunos con --only)
& "C:\Program Files\Blender Foundation\Blender 5.3\blender.exe" --background --factory-startup `
    --python tools\blender\build_prototype_models.py -- --root . --only switch_16p_1u
# Reimportar y comprobar (incluye tests/check_models.gd)
powershell -ExecutionPolicy Bypass -File tools\check_project.ps1
# Revisar visualmente
powershell -ExecutionPolicy Bypass -File tools\view_showcase.ps1      # ventana interactiva
powershell -ExecutionPolicy Bypass -File tools\capture_showcase.ps1   # PNG en docs\images\showcase\
```

- **Blender** genera `assets/models/<categoría>/<id>.glb` y `art_source/<categoría>/<id>.blend`. Un `.blend` editado a mano deja de coincidir con el script: si se retoca a mano, se exporta a mano y se deja de regenerar con el script.
- **La captura abre una ventana** (el modo *headless* no dibuja).

## Git

- Rama `main`. Commits pequeños con prefijo convencional en inglés.
- Se versionan `.uid` e `.import`; no `.godot/` ni `.mcp.json`.
- Archivos binarios grandes (`.blend`, texturas): valorar Git LFS cuando el repositorio supere unos cientos de MB (no instalado todavía).

## Exportar (futuro)

Antes de exportar: quitar el plugin `godot_ai` y el autoload `_mcp_game_helper`; comprobar que `CLAUDE.md`, `docs/`, `tools/`, `tests/` y `art_source/` quedan fuera del paquete (filtros de exportación).
