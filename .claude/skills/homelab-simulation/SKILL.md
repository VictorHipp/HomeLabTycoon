---
name: homelab-simulation
description: "Úsala para diseñar o implementar la simulación técnica de HomeLab Tycoon: electricidad, cables y enlaces, red L2/L3, servicios de red, hosts simulados (sistema de archivos, usuarios, procesos, servicios, paquetes), la terminal y sus órdenes, averías, redundancia, reloj de simulación, comandos/eventos y guardado del estado. No es para datos de catálogo (hardware-catalog) ni para escenas 3D o UI (godot-development)."
---

# Simulación técnica

## Documentos dueño (léelos antes de tocar código)

| Tema | Documento |
|---|---|
| Núcleo (SimWorld, comandos, eventos, reloj, guardado) | `docs/ARCHITECTURE.md` §4, §7, §8 |
| Electricidad, cableado, enlaces, L2/L3, servicios de red, diagnóstico, averías | `docs/NETWORK_SIMULATION.md` |
| Hosts, terminal, sistema de archivos, servicios, paquetes | `docs/TERMINAL_DESIGN.md` |
| Datos técnicos y su estado de verificación | `docs/TECH_RESEARCH.md` |
| Pruebas y criterios | `docs/TEST_PLAN.md` |

## Reglas confirmadas (no negociables)

1. **Todo simulado.** No se ejecuta ni descarga software real ([ADR 0006](../../../docs/adr/0006-fully-simulated-systems.md)).
2. **Separado de la vista:**
   - el código de simulación no usa `Node`, escenas ni UI;
   - toda modificación entra como **comando** validado;
   - la vista se entera por **eventos**.
3. **Nada por magia:** sin enlace correcto no hay comunicación; las configuraciones incorrectas tienen consecuencias comprensibles.
4. **Determinista:** paso fijo, RNG con semilla, sin reloj real.
5. **Honesto:** si una orden, opción o protocolo no está implementado, se dice. **Nunca** se inventa una salida correcta.
6. **Persistente:** todo estado (archivos, servicios, configuración de red, cables) se guarda y restaura igual.
7. **Incremental:** cada capa o protocolo entra con sus pruebas y con reglas verificadas.

**Propuestas pendientes de aprobación** (no las implementes sin ella):
- resolución analítica con trazas ([ADR 0008](../../../docs/adr/0008-analytic-network-simulation.md));
- configuración en archivos del VFS como fuente de verdad;
- emulación de `LANG`;
- extremo de cable pendiente;
- DHCP en el prototipo.

Lista completa: `docs/ROADMAP.md` §5.

## Antes de implementar una regla técnica

1. Busca el tema en `docs/TECH_RESEARCH.md`. Si sus datos están `[POR VERIFICAR]`, **verifícalos primero** con la jerarquía de fuentes y la plantilla, marcando fuente y fecha.
2. Escribe la regla como función pura sobre el estado y documenta la simplificación aceptada.
3. Escribe las pruebas: casos que funcionan, casos que fallan **con el motivo correcto** y trazas de referencia si aplica.
4. Implementa, ejecuta `tools\check_project.ps1` y actualiza el documento dueño.

## Cómo añadir una orden de terminal

1. Clase `ShellCommand` sin nodos; usa solo la API del host simulado (`docs/TERMINAL_DESIGN.md` §5).
2. Implementa **solo** las opciones que vas a probar. Registra las opciones reales conocidas no implementadas para que respondan con el mensaje honesto (§6).
3. Escribe la página `man` con las opciones implementadas y el enlace a su entrada del cuaderno.
4. Pruebas unitarias y salida de referencia («golden»). Los mensajes de error deben imitar los de la herramienta real según `LANG` (por verificar en cada orden).
5. Si la orden viene de un paquete, solo está disponible con el paquete instalado.

## Cómo añadir una capacidad de red o un servicio

1. Estado mínimo en el host o el equipo, más su (de)serialización.
2. Regla de resolución y pasos de traza con motivos de fallo legibles.
3. Indicadores visuales afectados: el evento que debe emitir.
4. Avería asociada (causa, pista observable, camino de diagnóstico).
5. Pruebas: escenario que funciona, escenario roto con el motivo correcto, ida y vuelta de guardado.

## Antipatrones

- Leer nodos o la escena desde la simulación.
- Usar cifras «de memoria» sin `[VERIFICADO]`.
- Devolver éxito por defecto en algo no implementado.
- Simular por paquete sin un ADR que lo justifique.
- Guardar referencias a `Resource` o nodos en el estado.
