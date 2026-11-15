# HomeLab Tycoon

Simulador 3D de construcción y gestión de homelabs, hecho con **Godot 4.7** y GDScript.

## Empezar

```powershell
# Requisitos: Godot 4.7.2, uv, Git (y Blender 5.3 para los modelos)
winget install --id GodotEngine.GodotEngine --version 4.7.2 --exact
winget install --id astral-sh.uv --exact

# Abrir el editor (cwd correcto + telemetría de Godot AI desactivada)
powershell -ExecutionPolicy Bypass -File tools\open_editor.ps1

# Validar sin abrir el editor
powershell -ExecutionPolicy Bypass -File tools\check_project.ps1
```

Para usar Claude Code con el editor: abre Godot con `tools\open_editor.ps1`, pulsa **Configure** junto a *Claude Code* en el dock *Godot AI* (genera `.mcp.json`, no versionado) y lanza `claude` desde esta carpeta.

## Documentación

- [`CLAUDE.md`](CLAUDE.md) — instrucciones permanentes para Claude Code
- [`docs/README.md`](docs/README.md) — índice de la documentación, vocabulario y etiquetas
- [`docs/GDD.md`](docs/GDD.md) — diseño del juego (visión v1)
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — arquitectura del software · [`docs/adr/`](docs/adr) — decisiones
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — hitos del prototipo y decisiones pendientes
- [`docs/TEST_PLAN.md`](docs/TEST_PLAN.md) — pruebas y criterios de aceptación
- [`.claude/skills/`](.claude/skills) — skills del proyecto (`godot-development`, `hardware-catalog`, `homelab-simulation`, `game-design`)
