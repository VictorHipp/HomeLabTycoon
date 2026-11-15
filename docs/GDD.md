# GDD — Documento de diseño del juego

> **Estado:** visión v1 (2026-11-15). Sustituye al GDD v0 (`docs/design/game-design-document.md`, mismo día) en todo lo que contradiga. Fuente: documento maestro del usuario. Etiquetas en [README.md](README.md).

## 1. Visión `[CONFIRMADO]`

HomeLab Tycoon es un simulador 3D de construcción y administración de infraestructura informática. El jugador empieza en una habitación con un ordenador antiguo, una conexión doméstica y poco dinero. Termina diseñando y operando infraestructuras empresariales y centros de datos.

Combina tres elementos:
1. **Construcción y gestión:** comprar, recibir, instalar y organizar equipos.
2. **Simulación técnica:** configurar redes, servidores, sistemas operativos y servicios con reglas coherentes con la realidad.
3. **Aprendizaje:** se aprende construyendo sistemas que funcionan, con misiones, experimentación y tutoriales ilustrados. **No es un test disfrazado de simulador.**

La dificultad aumenta de forma progresiva: el juego no debe resultar excesivamente complicado al principio.

## 2. Principios irrenunciables `[CONFIRMADO]`

Los 20 principios de la sección 34 del documento maestro, agrupados:

| Grupo | Principio |
|---|---|
| Perspectiva | Control principal en **tercera persona**; la cámara se **acerca progresivamente** para las interacciones detalladas |
| Arte | **3D low-poly estilizado**, original y coherente |
| Construcción | La construcción física es esencial; el **cableado es interactivo y técnicamente relevante** |
| Simulación | Terminal **profunda, persistente y funcional**; **todo simulado** (sin SO, VM ni contenedores reales); realismo basado en **reglas verificables** |
| Aprendizaje | Se aprende construyendo y resolviendo problemas; **cuaderno ilustrado** con tres niveles de ayuda |
| Herramientas | Diagnóstico visual y diseñador de topologías |
| Escala | Redundancia y recuperación en niveles avanzados; progresión **de una habitación a centros de datos**; libertad para experimentar |
| Alcance | Individual al principio (multijugador posible en el futuro); tiempos simplificados pero creíbles; arquitectura ampliable |
| Método | **Nunca fingir** que una mecánica funciona; no desarrollar todo de golpe; versiones pequeñas, estables, jugables y comprobables |

## 3. Fantasía del jugador y público

- **Fantasía:** «mi propio homelab, construido y entendido por mí». Orden, luces que parpadean, cables bien puestos y servicios que funcionan porque los he configurado bien. Más adelante, la del profesional al que las empresas confían su infraestructura.
- **Público:** aficionados a la tecnología y a los juegos de gestión, estudiantes de informática y redes, y profesionales que quieren experimentar sin hardware real.

## 4. Pilares de diseño

1. **Construir es el juego.** Comprar, desembalar, montar y cablear tiene que ser claro, táctil y satisfactorio.
2. **Aprender haciendo.** Una competencia se demuestra con una infraestructura que funciona, no respondiendo preguntas.
3. **Realismo verificable.** Las reglas técnicas son reales o simplificaciones documentadas. Nada funciona «por magia»: un equipo sin enlace correcto no se comunica.
4. **Progresión extensa y justa.** Se premia la capacidad técnica, no las esperas ni la repetición.
5. **Libertad para experimentar.** Varias soluciones válidas para cada problema, un modo Sandbox y errores que enseñan.

## 5. Experiencia de juego

### 5.1. Perspectiva y control `[CONFIRMADO]` → [CAMERA_SYSTEM.md](CAMERA_SYSTEM.md)

Cámara elevada en tres cuartos, al estilo de los simuladores sociales, con zoom y giro. El personaje se mueve con clic y caminando solo hasta el destino. Al interactuar con un objeto, el personaje se acerca y la cámara hace una transición fluida y rápida a una vista cercana. Esa vista puede parecer primera persona, pero **solo durante la interacción**.

### 5.2. Bucles

| Bucle | Duración | Contenido |
|---|---|---|
| Corto | minutos | Comprar → recibir → desembalar → montar → cablear → encender → comprobar |
| Medio | una sesión | Completar un contrato: planificar, presupuestar, construir, configurar y validar |
| Largo | semanas | Subir de etapa, ganar competencias y reputación, desbloquear equipos, espacios y tipos de cliente |

### 5.3. Modos `[CONFIRMADO]`

- **Carrera:** progresión por etapas con contratos, presupuesto y recompensas.
- **Sandbox:** experimentación libre. `[PROPUESTA]` Dinero y desbloqueos configurables y sin misiones obligatorias.
- **Desafíos técnicos:** escenarios cerrados de construcción con restricciones o de diagnóstico de averías.

### 5.4. Una sesión del primer prototipo (relato de referencia)

Empiezas en tu habitación. Haces clic en el escritorio y tu personaje se sienta frente al PC antiguo; la cámara se acerca hasta que la pantalla ocupa la vista. Abres la tienda, comparas switches y compras un rack pequeño, un switch y un servidor.

Vuelves a la vista general. Al rato llaman a la puerta: los paquetes están en la entrada. Abres las cajas, colocas el rack junto a la pared y te acercas a él. Montas el switch y el servidor en sus unidades U, conectas la alimentación y tiras un cable del servidor al switch y otro del switch al router.

Enciendes los equipos y los LED cobran vida. Abres la consola del servidor y asignas una IP con la terminal, apoyándote en el cuaderno si lo necesitas. Desde el PC haces `ping` al servidor y responde. La misión se completa: cobras, ganas experiencia y guardas la partida.

Ese relato son los 20 puntos del prototipo, trazados en [ROADMAP.md](ROADMAP.md) §3.

## 6. Sistemas de juego (resumen y documento dueño)

| Sistema | Qué aporta al jugador | Documento |
|---|---|---|
| Tienda, pedidos y desembalaje | Comparar, decidir, esperar con sentido, la satisfacción de abrir la caja | HARDWARE_CATALOG |
| Montaje en rack | Organización física con consecuencias técnicas (espacio, alimentación, acceso a puertos) | HARDWARE_CATALOG · INTERACTION_SYSTEM |
| Cableado **(prioritario)** | Conectar con intención: compatibilidad, longitud, velocidad, PoE, fibra, parcheo | NETWORK_SIMULATION · INTERACTION_SYSTEM |
| Electricidad | Encendido real, capacidad de regletas/PDU/UPS y, más adelante, redundancia | NETWORK_SIMULATION |
| Motor de red | Conectividad resultante de la configuración real | NETWORK_SIMULATION |
| Ordenador simulado | Tienda, terminal, documentación y administración «dentro del mundo» | TERMINAL_DESIGN |
| Terminal **(gran profundidad)** | Administrar sistemas con comandos sobre un estado persistente | TERMINAL_DESIGN |
| Paquetes y software | Instalar, configurar y mantener servicios, con dependencias y errores reales | TERMINAL_DESIGN |
| Diagnóstico visual | LED, ventiladores, alarmas y herramientas para investigar averías | NETWORK_SIMULATION §9 |
| Diseñador de topologías | Planificar antes de construir y comparar el plan con la instalación real | NETWORK_SIMULATION §11 |
| Redundancia y recuperación | Diseñar para el fallo: UPS, RAID, copias, HA, recuperación ante desastres | NETWORK_SIMULATION §10 · PROGRESSION |
| Averías y mantenimiento | Problemas con causa definida e investigable | NETWORK_SIMULATION §10 |
| Cuaderno | Aprender a tu ritmo con tres niveles de ayuda | TUTORIAL_SYSTEM |
| Misiones y progresión | Retos con presupuesto y varias soluciones, competencias demostradas | PROGRESSION |
| Gestión técnica y económica | Dimensionar: dinero, espacio, energía, refrigeración, CPU, RAM, almacenamiento, red | PROGRESSION · NETWORK_SIMULATION |

## 7. Tiempo de juego `[CONFIRMADO]`

Las duraciones son simplificadas pero creíbles: entregas, arranques, instalaciones con progreso y transferencias que dependen de la velocidad simulada. Se pueden acelerar o saltar cuando tenga sentido. La duración debe aportar jugabilidad, no frustración. Los detalles van en [ARCHITECTURE.md](ARCHITECTURE.md) §8 y [PROGRESSION.md](PROGRESSION.md) §7.

## 8. Personajes y escenarios `[CONFIRMADO]`

- Un **personaje principal visible**, personalizable más adelante (pelo, cara, ropa, accesorios).
- NPC futuros: clientes, repartidores, técnicos y trabajadores. Su desarrollo **no debe retrasar** el simulador.
- Escenarios: habitación → despacho, garaje → oficinas → salas de servidores → edificios empresariales → centros de datos.

## 9. Interfaz `[CONFIRMADO]`

- **Vista general:** dinero, nivel, experiencia, misión activa, inventario, cuaderno y estado general, sin saturar.
- **Herramientas avanzadas:** aparecen cuando se necesitan.
- **Rack:** prioridad a identificar equipos, puertos y cables.
- **Ordenador:** prioridad a la legibilidad de la terminal y las aplicaciones.
- **Controles y pantallas:** todo se usa con teclado y ratón; interfaz preparada para distintas resoluciones y escalados.

Estilo visual de la interfaz: [ART_STYLE.md](ART_STYLE.md) §9.

## 10. Idiomas, plataformas y distribución `[CONFIRMADO]`

- Idioma inicial: **español de España**; localización preparada para el inglés ([ADR 0007](adr/0007-spanish-first-localization.md)).
- Plataforma inicial: **Windows**. Linux y Steam Deck se estudiarán más adelante, sin retrasar la primera versión.
- Gratuito o de pago: sin decidir. **Sin microtransacciones** ni monetización durante el desarrollo inicial. Steam, cuando exista una versión suficientemente completa.

## 11. Un jugador y multijugador futuro `[CONFIRMADO]`

Solo un jugador por ahora. Los sistemas que cambiarían con un modo cooperativo están en [ARCHITECTURE.md](ARCHITECTURE.md) §12.

## 12. Fuera del alcance actual

- Multijugador.
- Soporte de *mods* (no se descarta en el futuro; los datos en `.tres` lo facilitarían).
- Ejecutar software real (SO, VM, contenedores, descargas de Internet).
- NPC complejos.
- Monetización.
- Plataformas distintas de Windows.
- Contenido de etapas posteriores a la 1 hasta completar el prototipo.

## 13. Análisis de cambios respecto a la visión anterior

Comparación entre la documentación del 2026-11-15 (v0, escrita al preparar el entorno) y el documento maestro. Las decisiones v0 marcadas como **sustituidas** dejan de ser válidas desde el 2026-11-15.

| Tema | v0 (sustituido) | v1 (vigente) | Impacto |
|---|---|---|---|
| Cámara | Órbita libre sobre la sala y vistas predefinidas, sin personaje. *Nota:* el documento maestro dice que el juego «ya no será en primera persona», pero en el repositorio no había ninguna especificación en primera persona; solo esta propuesta orbital de Claude | Tercera persona elevada con personaje visible, clic para mover y transición a vistas cercanas | Nuevos módulos: personaje, navegación, director de cámara, puntos de interacción |
| Estilo visual | Por decidir | Low-poly estilizado semi-cartoon, identidad original | Nuevo [ART_STYLE.md](ART_STYLE.md) |
| Profundidad técnica | «Plausible, no pedante»; MVP con capa física, energía y calor | Todo simulado con profundidad real: SO, terminal, paquetes, servicios, red L2/L3, virtualización; incremental y con pruebas | El simulador crece en módulos (SO y terminal); el calor pasa a etapas posteriores |
| MVP / prototipo | Hitos M1–M8 (sala, catálogo, colocación, cables, energía y calor, economía…) | 20 puntos en 7 hitos (habitación → interacción → tienda → rack y cables → red → terminal → misión y guardado) | ROADMAP reescrito |
| Progresión | 5 fases por espacio (armario → mini-CPD) | 6 etapas (Hogar → Centros de datos) con nivel, XP, reputación y competencias demostradas | Nuevo [PROGRESSION.md](PROGRESSION.md) |
| Modos | Por decidir (contratos, sandbox, retos) | Carrera, Sandbox y Desafíos técnicos | — |
| Tutorial | Integrado en el primer contrato | Cuaderno voluntario con tres niveles de ayuda; sin interrupciones constantes | Nuevo [TUTORIAL_SYSTEM.md](TUTORIAL_SYSTEM.md) |
| Idioma | Por decidir | Español de España, preparado para inglés | ADR 0007 |
| Plataformas | Por decidir (solo PC al principio) | Windows; Linux y Steam Deck después | — |
| Multijugador | No objetivo | No ahora, pero documentar impacto | ARCHITECTURE §12 |
| Catálogo | Racks, servidores, switches, routers, cables y accesorios | Catálogo amplio (componentes, NAS, AP, UPS, PDU, fibra, transceptores, herramientas, IoT, CPD…) | Esquema de datos ampliable, propuesto en HARDWARE_CATALOG §3 |
| Nuevas mecánicas | — | Diagnóstico visual, diseñador de topologías, redundancia y recuperación, cuaderno ilustrado | Nuevas secciones en NETWORK_SIMULATION, TUTORIAL_SYSTEM y PROGRESSION |

**Se mantiene de v0:**
- Godot 4.7 con GDScript tipado (ADR 0001).
- Catálogo guiado por datos (ADR 0002).
- Simulación separada de la escena (ADR 0003).
- Godot AI MCP con scope de proyecto (ADR 0004).
- Productos y marcas ficticios.
- Dinero entero y simulación determinista.
- Flujo de validación por CLI.

## 14. Preguntas abiertas

La lista numerada de decisiones pendientes está en [ROADMAP.md](ROADMAP.md) §5. Este documento se actualizará cuando el usuario las resuelva.
