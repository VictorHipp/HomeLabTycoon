# ADR 0003 — Simulación desacoplada de la escena 3D

- **Estado:** aceptada
- **Fecha:** 2026-11-15

## Contexto

El corazón del juego es un modelo de energía, red, calor y economía. Si el estado vive en los nodos, es difícil probarlo, guardarlo, acelerar el tiempo y razonar sobre él.

## Decisión

El código de simulación (`sim/` desde el 2026-11-15, [ADR 0009](0009-folder-structure-sim-game.md); antes `scripts/simulation/` y `scripts/core/`) contiene clases `RefCounted` sin dependencia de `Node`, `SceneTree` ni UI. La escena 3D es una **vista**: observa eventos y envía **comandos**. El mundo avanza con un tick fijo y RNG con semilla.

## Consecuencias

- Pruebas de simulación en headless, rápidas y deterministas.
- Guardar/cargar = serializar el mundo (`snapshot`), no recorrer el árbol de escena.
- Habilita deshacer/rehacer y repeticiones mediante registro de comandos.
- Coste: algo más de código de "pegamento" (adaptadores que traducen eventos a nodos).
- Regla verificable: `sim/` no debe contener `extends Node`, `get_node`, `$` ni `preload` de escenas.

## Alternativas descartadas

- Estado en nodos (`Device` como `Node3D` con lógica): rápido al principio, caro en guardado y pruebas.
