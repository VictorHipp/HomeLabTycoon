# ADR 0009 — Carpetas `sim/` · `game/` · `data/`

- **Estado:** aceptada (decisión 1 aprobada por el usuario el 2026-11-15; aplicada el mismo día)
- **Fecha:** 2026-11-15

## Contexto

La estructura actual separa `scenes/` de `scripts/`. Con los 21 módulos de la arquitectura, cada funcionalidad quedaría repartida en varias carpetas paralelas. Además, la frontera entre simulación y presentación ([ADR 0003](0003-simulation-decoupled-from-scene.md)) no se ve en el árbol de archivos.

## Decisión propuesta

Reorganizar antes del Hito 1, cuando solo hay tres scripts:

- `sim/` — motor técnico puro (`RefCounted` y `Resource`, sin `Node`), por módulos de dominio.
- `game/` — presentación por funcionalidad, con escena y script juntos.
- `data/` — contenido (catálogo, paquetes, misiones, cuaderno, terminal, traducciones).
- `tests/` dividido en `unit/`, `integration/` y `scene/`.

Detalle en [ARCHITECTURE.md](../ARCHITECTURE.md) §13.

## Consecuencias

- **La frontera se verifica con una prueba:** nada en `sim/` puede contener `extends Node`, `get_node`, `$` ni cargar escenas.
- **Cada funcionalidad de presentación vive en una carpeta**, lo que facilita leerla, moverla o borrarla.
- **Coste:** mover tres scripts y sus `.uid` y actualizar las rutas de la escena principal y del smoke test, validando con `check_project.ps1`.
- **Si no se aprueba,** se mantiene la estructura actual. La regla de frontera se aplica igual sobre `scripts/simulation/` y `scripts/core/`.
