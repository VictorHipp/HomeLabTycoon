# Documentación de HomeLab Tycoon

> Revisión: 2026-11-15. Fuente de verdad del diseño: el **documento maestro** del usuario (2026-11-15), resumido y trazado en [GDD.md](GDD.md).

## Etiquetas (búscalas con grep)

| Etiqueta | Significado |
|---|---|
| `[CONFIRMADO]` | Decisión del usuario (documento maestro). Es regla vigente. |
| `[PROPUESTA]` | Recomendación técnica **pendiente de aprobación**. No es regla hasta que el usuario la apruebe. |
| `[SPIKE]` | Hipótesis técnica que se valida con un experimento pequeño antes de construir encima. |
| `[VERIFICADO: fuente, fecha]` | Dato contrastado con la fuente indicada. |
| `[POR VERIFICAR]` | Dato plausible aún sin contrastar. No se usa para reglas del simulador hasta verificarlo ([TECH_RESEARCH.md](TECH_RESEARCH.md)). |

**Todo dato técnico sin etiqueta cuenta como `[POR VERIFICAR]`** (por ejemplo, detalles de protocolos o mensajes de herramientas que aún no se han contrastado).

**Cómo se aprueba una `[PROPUESTA]`.** Hay dos niveles:
1. Las **decisiones individuales** de [ROADMAP.md](ROADMAP.md) §5 necesitan una respuesta explícita del usuario antes del hito que las usa.
2. El **resto del diseño de un hito** queda aprobado cuando el usuario aprueba empezar ese hito.

Tras aprobar, la etiqueta pasa a `[CONFIRMADO: fecha]`.

**Estado de implementación (2026-11-15, Hito 1 iniciado).** Existen:
- la escena provisional `game/main/main.tscn`;
- los recursos `HardwareDefinition` y `PortDefinition` (`sim/hardware/`) y un item de catálogo (`rack_42u_basic`);
- 16 modelos provisionales low-poly (`assets/models/`) y la escena de muestra `game/showcase/model_showcase.tscn` ([ART_STYLE.md](ART_STYLE.md) §11);
- el smoke test, la comprobación de modelos y las herramientas de validación.

Todo lo demás que describen estos documentos es **diseño**.

## Mapa de documentos (un dueño por tema)

| Documento | Fuente de verdad de… |
|---|---|
| [GDD.md](GDD.md) | Visión, pilares, modos, sistemas de juego (resumen), análisis de cambios y preguntas abiertas |
| [ART_STYLE.md](ART_STYLE.md) | Identidad visual, paleta, materiales, proporciones, presupuestos y flujo Blender → Godot |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Capas, módulos, núcleo de simulación, guardado, tiempo, localización, multijugador futuro, carpetas |
| [CAMERA_SYSTEM.md](CAMERA_SYSTEM.md) | Cámara de vista general, movimiento del personaje y transiciones a vistas cercanas |
| [INTERACTION_SYSTEM.md](INTERACTION_SYSTEM.md) | Selección, acciones, vistas cercanas (rack, pantalla, caja), colocación y UX del cableado |
| [HARDWARE_CATALOG.md](HARDWARE_CATALOG.md) | Categorías, esquema de datos, tienda, pedidos, inventario, reglas de montaje en rack |
| [NETWORK_SIMULATION.md](NETWORK_SIMULATION.md) | Electricidad, capa física (puertos, cables, enlaces), red L2/L3, servicios de red, diagnóstico y averías |
| [TERMINAL_DESIGN.md](TERMINAL_DESIGN.md) | Ordenador simulado, terminal, sistema de archivos, usuarios, procesos, servicios, paquetes |
| [TUTORIAL_SYSTEM.md](TUTORIAL_SYSTEM.md) | Cuaderno, niveles de ayuda, contenido educativo y su honestidad |
| [PROGRESSION.md](PROGRESSION.md) | Economía, nivel, experiencia, reputación, competencias, etapas, misiones y modos |
| [TECH_RESEARCH.md](TECH_RESEARCH.md) | Método de investigación, índice de tecnologías y datos verificados o pendientes |
| [ROADMAP.md](ROADMAP.md) | Hitos, tareas, dependencias y trazabilidad del primer prototipo |
| [TEST_PLAN.md](TEST_PLAN.md) | Estrategia de pruebas y criterios de aceptación por hito |
| [DEVELOPMENT_WORKFLOW.md](DEVELOPMENT_WORKFLOW.md) | Herramientas instaladas, MCP, validación por CLI, Git y exportación |
| [adr/](adr/) | Decisiones de arquitectura registradas (ADR) |

**Regla:** si un dato aparece en dos documentos, uno lo define y el otro enlaza. Si cambias una decisión, actualiza su documento dueño y, si afecta a varios sistemas, añade un ADR.

## Vocabulario común

### Hitos del primer prototipo `[CONFIRMADO]`

| Hito | Nombre |
|---|---|
| 0 | Entorno de desarrollo (completado el 2026-11-15) |
| 1 | Habitación, cámara y movimiento |
| 2 | Interacción con objetos y transiciones de cámara |
| 3 | Tienda, inventario y colocación de equipos |
| 4 | Racks, puertos y cableado |
| 5 | Motor básico de red y encendido |
| 6 | Ordenador y terminal simulada |
| 7 | Misión, tutorial, recompensas y guardado |

**«Hito» significa siempre hito de desarrollo.** Las partes del juego son etapas, capítulos, misiones y metas de carrera (abajo).

### Partes del juego `[CONFIRMADO: juego extenso, 2026-11-15]` · cantidades `[PROPUESTA]`

| Nivel | Qué es |
|---|---|
| Etapa | Gran fase de la carrera (6 en total, tabla siguiente) |
| Capítulo | Bloque temático dentro de una etapa (4–6 por etapa) |
| Misión | Contrato o proyecto con requisitos validados por el estado; la última de cada capítulo es un proyecto final |
| Meta de carrera | Logro transversal con recompensa propia |
| Desafío técnico | Escenario cerrado de construcción o diagnóstico |

Detalle en [PROGRESSION.md](PROGRESSION.md) §10.

### Etapas de progresión `[CONFIRMADO]`

| Etapa | Nombre |
|---|---|
| 1 | Hogar |
| 2 | Homelab avanzado |
| 3 | Pequeñas empresas |
| 4 | Empresas medianas |
| 5 | Grandes empresas |
| 6 | Centros de datos |

### Módulos (sección 25 del documento maestro)

| Módulo | Capa | Documento dueño |
|---|---|---|
| Control del personaje | Presentación | CAMERA_SYSTEM |
| Cámaras | Presentación | CAMERA_SYSTEM |
| Transiciones | Presentación | CAMERA_SYSTEM |
| Interacciones | Presentación | INTERACTION_SYSTEM |
| Objetos 3D | Presentación | ART_STYLE (aspecto) · INTERACTION_SYSTEM (comportamiento) |
| Inventario | Simulación + UI | HARDWARE_CATALOG |
| Tienda | App del ordenador simulado | HARDWARE_CATALOG |
| Pedidos | Simulación | HARDWARE_CATALOG |
| Hardware | Simulación + datos | HARDWARE_CATALOG |
| Racks | Simulación (reglas) + presentación (vista) | HARDWARE_CATALOG · INTERACTION_SYSTEM |
| Cableado | Simulación (reglas) + presentación (UX) | NETWORK_SIMULATION · INTERACTION_SYSTEM |
| Electricidad | Simulación | NETWORK_SIMULATION |
| Motor de red | Simulación | NETWORK_SIMULATION |
| Terminal | Simulación + UI | TERMINAL_DESIGN |
| Sistemas operativos simulados | Simulación | TERMINAL_DESIGN |
| Servicios | Simulación | TERMINAL_DESIGN (gestión) · NETWORK_SIMULATION (comportamiento en red) |
| Virtualización simulada | Simulación (futuro) | TERMINAL_DESIGN §12 |
| Economía | Simulación | PROGRESSION |
| Misiones | Simulación + datos | PROGRESSION |
| Tutoriales | Datos + UI | TUTORIAL_SYSTEM |
| Guardado | Aplicación | ARCHITECTURE |

### Términos

- **Vista general:** cámara de tercera persona elevada (tres cuartos) con el personaje visible.
- **Vista cercana:** perspectiva próxima, casi a la altura de los ojos, durante una interacción (rack, pantalla, caja…).
- **Punto de interacción:** lugar y orientación donde se coloca el personaje para usar un objeto.
- **Ancla de cámara:** posición, orientación y FOV que adopta la cámara en una vista cercana.
- **Definición vs. instancia:** la *definición* es el dato de catálogo (`HardwareDefinition`); la *instancia* es un equipo concreto que el jugador posee, con su id único y su estado.
- **Comando / evento:** el comando es la orden de la presentación a la simulación, que esta valida antes de aplicarla. El evento es un hecho ya ocurrido que la simulación notifica.
- **Host simulado:** cualquier equipo con sistema operativo simulado (PC, servidor, NAS, router con CLI…).

## Cambios de ubicación (2026-11-15)

Copia de seguridad del estado anterior: `C:\A_HomLab\_respaldos\2026-11-15_antes-vision-maestra\`.

| Antes | Ahora |
|---|---|
| `docs/architecture/README.md` | este archivo (`docs/README.md`) |
| `docs/architecture/01-overview.md` | [ARCHITECTURE.md](ARCHITECTURE.md) §1–3 |
| `docs/architecture/02-folder-structure.md` | [ARCHITECTURE.md](ARCHITECTURE.md) §13 |
| `docs/architecture/03-simulation-architecture.md` | [ARCHITECTURE.md](ARCHITECTURE.md) §4 y [NETWORK_SIMULATION.md](NETWORK_SIMULATION.md) |
| `docs/architecture/04-data-model.md` | [HARDWARE_CATALOG.md](HARDWARE_CATALOG.md) §3 |
| `docs/architecture/05-development-workflow.md` | [DEVELOPMENT_WORKFLOW.md](DEVELOPMENT_WORKFLOW.md) |
| `docs/architecture/adr/*.md` | [adr/](adr/) |
| `docs/design/game-design-document.md` | [GDD.md](GDD.md) |
