# ADR 0006 — Todos los sistemas informáticos simulados

- **Estado:** aceptada (decisión del usuario, documento maestro §10, §12, §23)
- **Fecha:** 2026-11-15

## Contexto

El juego enseña redes, sistemas operativos, servicios y virtualización. Se podría intentar integrar entornos reales (máquinas virtuales, contenedores, intérpretes). Eso tiene problemas de seguridad, de portabilidad, de requisitos del equipo del jugador y de control de la experiencia.

## Decisión

Todo es **simulado**: hardware, redes, sistemas operativos, terminal, servicios, paquetes, almacenamiento, virtualización, fallos, rendimiento y dependencias.

- No se arrancan VM reales, no se instalan SO auténticos, no se ejecutan servicios externos y **no se descarga ni ejecuta software real de Internet**.
- La simulación tiene un **estado interno real** y reglas de funcionamiento suficientes para reproducir correctamente los conceptos que se enseñan.
- Integrar entornos reales aislados podría estudiarse en el futuro, fuera del desarrollo inicial.

## Consecuencias

- Se puede probar todo en *headless* y de forma determinista. El juego funciona sin conexión y sin privilegios.
- **Hay que construir cada comportamiento** (intérprete, sistema de archivos, servicios, motor de red). Por eso el avance es incremental y cada pieza entra con pruebas.
- **Riesgo de que el jugador aprenda algo incorrecto.** Mitigación: investigación con fuentes ([TECH_RESEARCH.md](../TECH_RESEARCH.md)), simplificaciones documentadas y regla de honestidad (lo no implementado se declara).
