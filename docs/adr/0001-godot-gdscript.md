# ADR 0001 — Godot 4.7 con GDScript tipado

- **Estado:** aceptada
- **Fecha:** 2026-11-15

## Contexto

Se necesita un motor 3D que permita iterar rápido, con escenas editables por código y herramientas, y que encaje con un flujo asistido por IA (Claude Code + MCP). El equipo es una persona.

## Decisión

Usar **Godot 4.7.2 estable** con **GDScript** y **tipado estático obligatorio**. Renderer Forward+ (PC). Blender 5.3 solo para modelar; se exporta a `.glb`.

## Consecuencias

- Ciclo de edición/ejecución muy corto; escenas y recursos en texto (diffs legibles en Git).
- Godot AI MCP exige Godot 4.7+, compatible con esta decisión.
- GDScript es más lento que C#/C++ para cálculo intensivo: la simulación debe diseñarse eficiente (estructuras indexadas) y medir antes de optimizar. Si algún sistema lo requiere, podría extraerse a GDExtension (nueva ADR).
- No se usa C#: el plugin Godot AI trata C# solo como texto y no compila en el editor.

## Alternativas descartadas

- Unity/Unreal: más pesados y menos adecuados para texto/diff y automatización con MCP.
- Godot con C#: mayor rendimiento, pero peor soporte del plugin y más tooling (.NET).
