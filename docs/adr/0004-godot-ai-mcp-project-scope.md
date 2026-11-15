# ADR 0004 — Godot AI MCP con scope de proyecto

- **Estado:** aceptada
- **Fecha:** 2026-11-15

## Contexto

Claude Code necesita manipular el editor de Godot (escenas, nodos, ejecución, logs, capturas). El plugin [Godot AI](https://github.com/hi-godot/godot-ai) lo ofrece como servidor MCP. Por defecto registra el servidor en el ámbito `user` (`~/.claude.json`), cargándolo en **todos** los proyectos, incluso los que no son de Godot.

## Decisión

- Un único MCP para el motor: **Godot AI v4.4.1** (no se instalan MCP redundantes).
- Registro en ámbito **project** (`godot_ai/mcp_client_scope = project` ⇒ `.mcp.json` en la raíz del proyecto). `~/.claude.json` global queda sin servidores de Godot.
- El editor se abre siempre con `tools\open_editor.ps1` para que el directorio de trabajo sea la raíz del proyecto.
- `.mcp.json` **no** se versiona: contiene rutas absolutas del equipo; se regenera con *Configure*.
- Telemetría del plugin desactivada.
- `uv` (no Node ni Python global) como runtime del servidor; `uvx` lo descarga y fija la versión.

## Consecuencias

- El MCP solo está disponible con el editor abierto y tras aprobar el servidor en Claude Code.
- Trabajo en la raíz `C:\A_HomLab\HomeLabTycoon`: Claude Code debe lanzarse desde ahí.
- Hay que excluir `addons/godot_ai/` y el autoload `_mcp_game_helper` de las exportaciones.
- El plugin se actualiza solo con su botón *Update*.

## Alternativas descartadas

- Scope `user`: simple, pero carga el servidor en proyectos ajenos.
- Escribir `.mcp.json` a mano: el plugin lo desaconseja porque su comando fija versión, puertos y dominios de herramientas.
- MCP de terceros adicionales para Godot: redundantes con Godot AI.
