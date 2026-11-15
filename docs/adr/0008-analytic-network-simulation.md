# ADR 0008 — Simulación de red analítica con trazas

- **Estado:** **propuesta** (pendiente de aprobación del usuario)
- **Fecha:** 2026-11-15

## Contexto

El motor de red debe:
- dar resultados que dependan de la configuración real (cableado, IP, rutas, VLAN, firewall);
- explicar los fallos de forma comprensible;
- probarse sin escena;
- escalar desde una habitación hasta un centro de datos.

Hay dos familias de soluciones:
1. **Simulación de eventos discretos por paquete:** cada trama y paquete viaja con su tiempo.
2. **Resolución analítica:** se mantiene el estado y se responden consultas recorriendo la topología según las reglas de cada capa.

## Decisión propuesta

**Resolución analítica con trazas** ([NETWORK_SIMULATION.md](../NETWORK_SIMULATION.md) §2):
- El estado (topología física, configuración) se guarda.
- Los datos derivados (alimentación, enlaces, dominios L2) se recalculan cuando algo cambia.
- Consultas como `ping` o una conexión de aplicación producen una **traza paso a paso** con el punto exacto y el motivo del fallo.
- Los intercambios de protocolo con valor educativo (DHCP, ARP) se representan como **pasos de la traza**.
- El rendimiento (ancho de banda, latencia) se calcula de forma analítica cuando haga falta.

## Consecuencias

- **A favor:**
  - determinista y barato;
  - pruebas pequeñas y legibles;
  - cada fallo tiene explicación, lo que sirve de base para el diagnóstico y el cuaderno;
  - escala bien.
- **En contra:** no reproduce fenómenos que solo emergen del tiempo de paquete (ráfagas, colas detalladas). Se modelarán de forma analítica o como eventos cuando aporten aprendizaje.
- **Reversible a coste moderado:** se podría añadir simulación por paquete para una herramienta concreta (captura detallada) sin cambiar el modelo de estado.

## Alternativa descartada (por ahora)

Simulación de eventos discretos por paquete en todo el motor: más fiel en tiempos, pero mucho más costosa de implementar, de ejecutar a escala y de explicar al jugador.
