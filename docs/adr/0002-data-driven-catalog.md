# ADR 0002 — Catálogo de hardware guiado por datos

- **Estado:** aceptada
- **Fecha:** 2026-11-15

## Contexto

El juego tendrá decenas o cientos de items (racks, servidores, switches, routers, cables…). Los precios, consumos y puertos se ajustarán constantemente durante el equilibrado.

## Decisión

Cada item es un `HardwareDefinition` (Resource) guardado como `.tres` individual en `data/catalog/`, con `id` estable. El código de gameplay nunca contiene constantes de hardware. Los puertos son `PortDefinition` agrupados.

## Consecuencias

- Equilibrar = editar datos, no código; los diffs son pequeños y revisables.
- El editor de Godot sirve como editor del catálogo (inspector); el MCP puede crear/modificar recursos.
- Las partidas guardadas referencian `id` → los ids son un contrato público.
- Se necesita un validador de catálogo (Hito 3, ver `docs/ROADMAP.md`) para detectar errores de datos pronto.
- *Nota 2026-11-15:* la evolución del esquema hacia composición (`DeviceSpec`) está propuesta en `docs/HARDWARE_CATALOG.md` §3.2, pendiente de aprobación. No cambia esta decisión, la refina.
- Los items con comportamiento especial no se resuelven con subclases del recurso, sino con **datos que los sistemas de simulación interpretan** (p. ej. `CableSpec`).

## Alternativas descartadas

- Un único JSON/CSV: más fácil de editar masivamente, pero sin tipado ni integración con el inspector; se podrá añadir importador CSV → `.tres` si hace falta.
- Subclases por tipo de dispositivo: duplican lógica y complican guardados.
