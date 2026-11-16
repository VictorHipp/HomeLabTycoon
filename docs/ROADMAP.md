# ROADMAP — Planificación del desarrollo

> **Revisión:** 2026-11-15, visión v1.
>
> - **Hitos y orden:** `[CONFIRMADO]` (documento maestro §30).
> - **Tareas concretas:** `[PROPUESTA]`. Las que dependen de una decisión pendiente (§5) lo indican.
> - **No se empieza la implementación** hasta revisar este plan con el usuario `[CONFIRMADO]`.

## 1. Estado

| Hito | Estado |
|---|---|
| 0 — Entorno | ✅ Completado (2026-11-15). Detalle: [DEVELOPMENT_WORKFLOW.md](DEVELOPMENT_WORKFLOW.md) |
| 1 — Habitación, cámara y movimiento | 🔶 **Casi terminado** (iniciado el 2026-11-15). **Hecho:** reestructuración de carpetas, *spike* visual ([ART_STYLE.md](ART_STYLE.md) §11) y *runner* de pruebas; además, las tareas 1–7, dentro de la prueba jugable. **Falta para cerrarlo:** alternar los tres modos de paredes (H1-06), medir los FPS (H1-07), tu opinión sobre la sensación de la cámara (S1) y el coste de rehornear la navegación (S3) |
| 2–7 | Planificados (§2) |
| **Prueba jugable de la primera misión** | ✅ **Jugable** (2026-11-15; pedida por el usuario, adelanta partes de los Hitos 1–7). Se juega con `tools\play.ps1` o F5. **Incluye:** cámara con giro por ratón, personaje que camina, PC con tienda, pedidos y terminal, paquetes, colocación con silueta, montaje por U, cables y corriente con extremo pendiente, encendido, consola del servidor, red con DHCP y `ping`, misión con recompensa. **Rack:** necesita 50 cm libres delante y detrás (zonas marcadas en el suelo); avisa si queda lejos de la regleta; se puede mover (clic derecho sobre él o botón «Mover rack», con lo montado y sin cables) y recoger (vacío). **Verificado** con 37 pruebas sin ventana y con un recorrido automático en 4 escenarios de colocación (bueno, contra la pared, lejos de la regleta y cerrando el paso). El recorrido usa solo entrada sintética real: clics en el mundo y en el centro de los botones, órdenes tecleadas tecla a tecla y arrastre de cámara (`tools\walkthrough.ps1`; capturas en `build/walkthrough/`, sin versionar; selección en [images/first_mission/](images/first_mission/)). `tools\play.ps1` arranca y deja el registro limpio. **Simplificado:** los paquetes se abren sin animación de cerca; colocar o mover no hace caminar al personaje; la consola del servidor se abre desde el panel del rack; junto a una pared, la cámara cercana del rack entra en la habitación y queda más inclinada. |
| **Segunda ronda (2026-11-15)** | ✅ Pedida por el usuario tras probar el juego. **Menú** en pausa (`Esc`, botón «Menú» del HUD y de la pantalla del PC) con **Ajustes › Controles**, sacados de las acciones reales del `InputMap`. **Manual del juego** (`F1`): 9 capítulos, 24 capturas anotadas generadas por el recorrido (`-Scenario manual`), índice, anterior, siguiente. **Guardar y cargar:** formato v1 en `user://saves/`, ida y vuelta idéntica, escritura atómica con copia `.bak`. **Entregas:** zona reservada junto a la puerta, una pila con contador «×N»; una partida con la zona ocupada se resuelve sin borrar nada. **Cables:** recorrido por el suelo calculado en `sim/` (rodea muebles, equipos y la zona de entregas; pasa bajo el escritorio); la longitud es la del recorrido; sin recorrido, se rechaza con el motivo; mover el rack vuelve a tender sus cables. **Colisiones:** colisionadores por piezas en los muebles; fantasma rojo o verde. **Personaje:** maniquí articulado, marcha procedural sin deslizar (el pie apoyado se desplaza menos de 2 mm), aviso si se atasca, se sienta en la silla giratoria y se levanta a un sitio libre. **Verificado:** 56 pruebas sin ventana y 4 escenarios del recorrido a 1600×900 y a 1280×720. **Falta:** cuaderno técnico (H7-03), personaje y animaciones definitivas |

Cada hito termina en una **versión jugable y estable**, con `check_project.ps1` en verde, criterios de aceptación cumplidos ([TEST_PLAN.md](TEST_PLAN.md) §4) y documentación al día.

## 2. Hitos del primer prototipo

### Preparación (antes del Hito 1)

- Resolver las decisiones del grupo «Antes del Hito 1» de §5 y aprobar el inicio del Hito 1 (que aprueba su diseño por defecto, ver [README.md](README.md)).
- **Primer commit** (línea base) cuando el usuario configure su identidad de Git y lo autorice.
- Reorganizar carpetas, si se aprueba (decisión 1).
- Esqueleto de `SimWorld`, `SimClock` y `SaveService` con el contrato `save_state` / `load_state` ([ARCHITECTURE.md](ARCHITECTURE.md) §4 y §7).
- *Runner* de pruebas (decisión 4) integrado en `check_project.ps1`.
- Acciones del *Input Map* ([ARCHITECTURE.md](ARCHITECTURE.md) §10).

### Hito 1 — Habitación, cámara y movimiento

1. Habitación provisional con dimensiones reales (≈ 3,5 × 3 m):
   - suelo y paredes en tramos con su normal;
   - puerta como punto de entrega y ventana;
   - escritorio con el PC antiguo, mueble con el router y regleta.
2. `CameraDirector` y vista general con los controles y límites de [CAMERA_SYSTEM.md](CAMERA_SYSTEM.md) §3.
3. Corte de paredes (*spike* S6).
4. Personaje provisional (cápsula orientada) con `CharacterBody3D`, `NavigationAgent3D` y malla de navegación (*spike* S3, parte 1).
5. Clic para moverse, con marcador de destino y aviso si no se puede llegar.
6. Iluminación base y *spike* visual de paleta y materiales ([ART_STYLE.md](ART_STYLE.md)).
7. `GameSession` con el `SimWorld` (vacío) y el reloj avanzando.

- **Depende de:** preparación.
- **Versión jugable:** pasear por la habitación y mirarla desde cualquier ángulo.

### Hito 2 — Interacción con objetos y transiciones de cámara

1. Componente `Interactable`: resaltado al pasar el ratón, etiqueta y menú contextual.
2. Gestor de interacciones (máquina de estados) y puntos de interacción.
3. Transición en dos fases, vuelta a la pose guardada y opción «reducir movimiento» (*spike* S1).
4. Modo pantalla (*spike* S2) con el **escritorio mínimo de HomeLab OS** en el PC: fondo, reloj e iconos provisionales.
5. Modo rack, solo el mecanismo: vistas frontal y trasera de un rack de prueba y desplazamiento por U.
6. Modo inspección genérico.

- **Depende de:** Hito 1.
- **Versión jugable:** caminar hasta el PC o el rack, acercarse, mirar y volver.

### Hito 3 — Tienda, inventario y colocación de equipos

1. Esquema de catálogo por composición, si se aprueba (decisión 3). Items del prototipo ([HARDWARE_CATALOG.md](HARDWARE_CATALOG.md) §7) y validador del catálogo.
2. Módulos de simulación: economía, inventario (instancias y ubicaciones) y pedidos, con sus comandos.
3. App Tienda (lista por categorías, ficha, carrito y pago) en el escritorio simulado.
4. Velocidades del reloj y «saltar hasta el evento». Entrega en el punto de entrega.
5. Caja interactuable y desembalaje.
6. Modo colocación con `PlaceObject` y rehorneado de navegación (*spike* S3, parte 2).

- **Nota de honestidad:** hasta el Hito 5 no existe la conectividad simulada. La tienda funciona sin comprobar la conexión, marcado con la funcionalidad `shop.connectivity_check = false`. En el Hito 5 pasa a depender de la red real.
- **Depende de:** Hito 2.
- **Versión jugable:** comprar, esperar o saltar la entrega, abrir las cajas y colocar el rack.

### Hito 4 — Racks, puertos y cableado

1. Módulo de racks: montaje y desmontaje con las reglas de [HARDWARE_CATALOG.md](HARDWARE_CATALOG.md) §6; vista de rack completa.
2. Escenas envoltorio provisionales (rack, switch, servidor, router, PC, regleta) con `PortSocket`, LED y botón de encendido.
3. Módulo de cableado: cables como instancias, extremos, compatibilidad y longitud.
4. UX del cable ([INTERACTION_SYSTEM.md](INTERACTION_SYSTEM.md) §9): extremo pendiente, desconexión y malla de cable (*spike* S4).
5. Cables de alimentación a la regleta. La lógica eléctrica llega en el Hito 5.
6. LED provisionales (*spike* S5).

- **Depende de:** Hito 3 e investigación P0 de cableado y racks ([TECH_RESEARCH.md](TECH_RESEARCH.md)).
- **Versión jugable:** montar el switch y el servidor en el rack y cablearlo todo.

### Hito 5 — Motor básico de red y encendido

1. Módulo eléctrico: toma → regleta → equipos; botón de encendido; arranque con duración.
2. Estados y negociación de enlace.
3. Dominio L2 del switch no gestionable.
4. IPv4, ARP, ping con traza y ruta por defecto. DHCP mínimo en el router (decisión 7). Internet simulada para la tienda.
5. LED y vistas que reflejan el estado simulado.
6. Panel de depuración (solo en desarrollo) para ver trazas.
7. Pruebas de escenarios y trazas de referencia.

- **Depende de:** Hito 4 e investigación P0 de Ethernet, IPv4, ARP, ICMP y DHCP.
- **Versión jugable:** encender los equipos, ver los LED y comprobar desde el panel de depuración que el PC y el servidor se ven cuando corresponde.

### Hito 6 — Ordenador y terminal simulada

1. `SimHost`: sistema de archivos, usuarios básicos, sesiones y red ligada al motor.
2. Lexer, parser y ejecutor (fase 1, [TERMINAL_DESIGN.md](TERMINAL_DESIGN.md) §4).
3. Las órdenes del prototipo (§14 de ese documento), con manual y registro de órdenes conocidas (honestidad).
4. App Terminal en el PC y **consola local** del servidor desde la vista de rack.
5. Mensajes en español según `LANG` (decisión 10).
6. Tipografía monoespaciada (decisión 5).

- **Depende de:** Hitos 2 y 5 e investigación P0 de coreutils e iproute2.
- **Versión jugable:** configurar la IP del servidor con la terminal y hacer `ping` desde el PC.

### Hito 7 — Misión, tutorial, recompensas y guardado

1. Módulo de misiones con los validadores necesarios, la misión «Primer servidor» ([PROGRESSION.md](PROGRESSION.md) §9) y su panel.
2. Módulo de progresión: dinero, XP, nivel y competencias; recompensas.
3. Cuaderno:
   - conversor Markdown → BBCode, índice, búsqueda, marcadores e historial;
   - las 6 entradas del prototipo;
   - registro de funcionalidades y pruebas de honestidad.
4. Guardado completo: ranuras, interfaz de guardar y cargar, autoguardado y versión 1 del formato. Prueba de ida y vuelta.
5. HUD mínimo ([GDD.md](GDD.md) §9).
6. Primer equilibrio de precios y dinero inicial.
7. Prueba de juego completa de los 20 puntos y lista de comprobación para el usuario.

- **Depende de:** todos los anteriores.
- **Versión jugable:** **el prototipo completo**.

## 3. Trazabilidad de los 20 puntos del prototipo

| # | Punto `[CONFIRMADO]` | Hito | Criterio de aceptación (resumen) | Cómo se comprueba |
|---|---|---|---|---|
| 1 | Ver al personaje desde una cámara 3D elevada | 1 | Vista de tres cuartos al iniciar, con zoom y giro dentro de límites | Prueba de escena + captura con MCP + revisión manual |
| 2 | Moverlo haciendo clic | 1 | Llega a ≤ 0,2 m del punto rodeando obstáculos; aviso si es inalcanzable | Prueba de escena *headless* + manual |
| 3 | Seleccionar objetos | 2 | Resaltado y etiqueta al pasar el ratón; clic = acción por defecto; menú contextual | Prueba de escena + manual |
| 4 | Acercar suavemente la cámara al interactuar | 2 | Camina al punto; transición ≤ 0,8 s sin saltos; `Esc` vuelve a la pose previa | Prueba del director de cámara + manual |
| 5 | Utilizar un ordenador | 2 | La pantalla pasa a pantalla completa, legible a 1080p, con ratón y teclado | *Spike* S2 + manual |
| 6 | Abrir una tienda sencilla | 3 | La app lista los productos del catálogo con precio y ficha | Prueba unitaria + manual |
| 7 | Comprar un switch, un rack y un servidor | 3 | El pago descuenta dinero; sin saldo no deja; crea el pedido | Prueba unitaria |
| 8 | Recibir un paquete | 3 | Tras la entrega (acelerable o saltable) aparece la caja en el punto de entrega | Prueba unitaria + manual |
| 9 | Abrirlo y recoger el dispositivo | 3 | Abrir, ver contenido y pasar al inventario | Prueba unitaria + manual |
| 10 | Colocar los equipos en la habitación | 3 | Fantasma, rejilla, giro y validación; queda en el estado | Prueba unitaria + manual |
| 11 | Instalar los dispositivos en el rack | 4 | Montaje por U con validación; desmontaje | Prueba unitaria + manual |
| 12 | Acercar la cámara al rack | 2 (mecanismo) · 4 (contenido) | Vista frontal y trasera, desplazamiento por U | Prueba de escena + manual |
| 13 | Identificar puertos y conectar cables | 4 | Compatibilidad resaltada; longitud validada; cable visible; desconectar | Prueba unitaria + manual |
| 14 | Encender los dispositivos | 5 | Solo con alimentación; LED según el estado; arranque breve | Prueba unitaria + manual |
| 15 | Utilizar una terminal simulada | 6 | Órdenes del prototipo correctas y persistentes; las no implementadas lo dicen | Pruebas *golden* + manual |
| 16 | Configurar una pequeña red | 6 (con el motor del Hito 5) | `ip address add` + `ping` funcionan solo con cableado, alimentación y subred correctos | Prueba de integración + manual |
| 17 | Consultar el cuaderno | 7 | Índice, búsqueda, marcadores, historial; 6 entradas con 3 niveles | Pruebas de honestidad + manual |
| 18 | Completar una misión | 7 | «Primer servidor» se valida por el estado con al menos 2 soluciones probadas | Prueba unitaria con 2 soluciones |
| 19 | Recibir dinero y experiencia | 7 | Recompensas aplicadas una sola vez; competencia registrada | Prueba unitaria |
| 20 | Guardar y cargar la partida | 7 | Guardar → cargar → guardar da una captura idéntica con todo lo de ARCHITECTURE §7 | Prueba de ida y vuelta + manual |

**Interpretaciones que hice** (decisiones 19 y 20 de §5):
- Los puntos 5–6 usan el ordenador antes del Hito 6: la vista de pantalla y un escritorio mínimo llegan en el Hito 2 y la tienda en el 3. El Hito 6 añade la terminal.
- El guardado se diseña desde el Hito 1 (cada módulo serializable) aunque su interfaz llegue en el Hito 7.

## 4. Spikes (experimentos técnicos breves)

| Id | Pregunta | Hito | Documento |
|---|---|---|---|
| S1 | Sensación de la cámara y duración de las transiciones | 1–2 | CAMERA_SYSTEM §8 |
| S2 | Pantalla del ordenador con `SubViewport` compartido: entrada y nitidez | 2 | INTERACTION_SYSTEM §6 |
| S3 | Coste de rehornear la navegación; `affect_navigation_mesh` | 1 y 3 | CAMERA_SYSTEM §4 |
| S4 | Malla de cables: coste con 50/200 cables | 4 | INTERACTION_SYSTEM §9 |
| S5 | LED con `instance uniform` en 4.7.2 | 4–5 | ART_STYLE §5 |
| S6 | Corte de paredes: malla alternativa o shader | 1 | CAMERA_SYSTEM §3.3 |

Cada *spike* produce una nota breve con el resultado en el documento indicado y, si cambia el diseño, una actualización o un ADR.

## 5. Decisiones pendientes de aprobación

**Estado (2026-11-15):** el usuario aprobó **todas las recomendaciones** de esta lista, salvo la 5 (tipografías; no se descarga ninguna: la terminal usa la fuente monoespaciada del sistema) y la 18 (subagente, sin decidir). La 16 (identidad visual) quedó aprobada tras ver la muestra («me encanta como se ve»). La 17 está hecha: primer commit y repositorio **público** https://github.com/VictorHipp/HomeLabTycoon.

Cada decisión necesita **respuesta explícita** antes del hito que la usa. El resto del diseño de cada hito se aprueba al aprobar el inicio del hito ([README.md](README.md)). Los números son identificadores estables; están agrupados por el hito que los necesita.

Formato: decisión — **recomendación por defecto**.

**Antes del Hito 1** (respondidas por el usuario el 2026-11-15)
- **17.** Primer commit de línea base — ✅ **Confirmada**, pero **bloqueada**: falta que el usuario configure `user.name` y `user.email` de Git. Mientras tanto hay copias en `C:\A_HomLab\_respaldos\`.
- **1.** Reorganizar carpetas en `sim/`, `game/` y `data/` ([ADR 0009](adr/0009-folder-structure-sim-game.md)) — ✅ **Confirmada y aplicada.**
- **4.** Pruebas con un *runner* propio mínimo, sin addons — ✅ **Confirmada** (pendiente de implementar en el Hito 1).
- **20.** Cada módulo nace serializable desde el Hito 1 ([ARCHITECTURE.md](ARCHITECTURE.md) §7) — ✅ **Confirmada.**
- **6.** Escenario inicial: PC antiguo, router doméstico, regleta y un cable ya conectados — ✅ **Confirmada.**
- **15.** Corte de paredes al estilo de los simuladores sociales — ✅ **Confirmada.**
- **16.** Identidad visual «Taller luminoso» y paleta de [ART_STYLE.md](ART_STYLE.md) — 🔶 **A prueba.** El usuario quiere ver los modelos antes; muestra en [ART_STYLE.md](ART_STYLE.md) §11.

**Hito 2**
- **19.** El ordenador se usa antes del Hito 6: vista de pantalla y escritorio mínimo en el Hito 2, tienda en el 3 y terminal en el 6 (interpretación de los puntos 5–6) — **Sí.**
- **5.** Tipografías libres (SIL OFL `[POR VERIFICAR]` al descargar): *Atkinson Hyperlegible* para interfaz (Hito 2) y *JetBrains Mono* para terminal (Hito 6). Requiere descargar archivos de terceros — **Sí.**

**Hito 3**
- **3.** Esquema del catálogo por composición: categorías como datos + `DeviceSpec` ([HARDWARE_CATALOG.md](HARDWARE_CATALOG.md) §3.2) — **Sí.**
- **13.** Escala de tiempo: 1 s real = 1 min de juego a ×1, con ×2, ×4 y «saltar hasta el evento» — **Sí, ajustable jugando.**

**Hito 4**
- **12.** Cable con extremo pendiente: conectar un extremo, ir al otro equipo y conectar el segundo — **Sí.**
- **18.** Subagente `tech-researcher` para rellenar entradas de investigación — **Decidir entonces;** opcional.

**Hito 5**
- **2.** Motor de red analítico con trazas en lugar de simulación por paquete ([ADR 0008](adr/0008-analytic-network-simulation.md)) — **Sí.**
- **7.** DHCP mínimo en el router doméstico (el PC obtiene IP solo) — **Sí.**

**Hito 6**
- **9.** Lo configurado con `ip` no sobrevive a un reinicio (realista; red persistente después), con aviso en el cuaderno — **Sí**, si la investigación confirma el comportamiento real.
- **10.** Terminal que emula `LANG`, con mensajes traducidos donde lo hace Linux en español — **Sí.**
- **11.** Órdenes y protocolos con nombre real; productos de marca (distribución, hipervisor…) con nombre ficticio — **Sí.**

**Hito 7**
- **8.** Misión «Primer servidor» tal como está en [PROGRESSION.md](PROGRESSION.md) §9: IP estática desde la consola local del servidor como `root` — **Sí.**
- **14.** El cuaderno no penaliza; distinción opcional «sin ayuda» sin efecto económico — **Sí.**

## 6. Después del prototipo: plan a largo plazo

`[CONFIRMADO: 2026-11-15]` El juego será extenso. El reparto en fases es `[PROPUESTA]`.

Cada fase agrupa varios hitos de desarrollo, y cada hito termina en una versión jugable. Cada fase aporta los capítulos de una etapa ([PROGRESSION.md](PROGRESSION.md) §10). Una fase se detalla (tareas, criterios) cuando termina la anterior: lo lejano no se planifica al detalle.

| Fase | Hitos (aprox.) | Objetivo | Contenido principal |
|---|---|---|---|
| A — Prototipo | 1–7 | La experiencia fundamental (los 20 puntos) | §2 |
| B — Etapa 1 completa | 8–13 | Los 5 capítulos del Hogar (≈ 20 misiones) | DHCP y DNS, NAS y permisos, copias y restauración, Wi-Fi e invitados, cámaras IP; editor de texto, `sudo`, `grep`, `systemctl`, `journalctl`, `apt`; probador de cables; diseñador de topologías v1; metas de carrera; personaje definitivo |
| C — Etapa 2 | 14–19 | Homelab avanzado | Switches gestionables y VLAN, STP, fibra y transceptores, UPS, térmica, virtualización v1, contenedores, red persistente |
| D — Etapa 3 | 20–25 | Pequeñas empresas | Sitios de clientes y desplazamiento, usuarios centralizados, firewall y NAT, Wi-Fi corporativa, monitorización v1 |
| E — Etapa 4 | 26–31 | Empresas medianas | Varios racks, enrutamiento entre departamentos, almacenamiento compartido, redundancia de enlaces |
| F — Etapa 5 | 32–37 | Grandes empresas | Alta disponibilidad, clústeres, recuperación ante desastres, varias sedes |
| G — Etapa 6 | 38–43 | Centros de datos | Salas grandes, energía A/B, refrigeración de CPD, escala y automatización |
| H — Lanzamiento | 44+ | Versión publicable | Inglés, pulido de arte y audio, accesibilidad, rendimiento, publicación (si se decide) |

**En todas las fases:**
- arte definitivo progresivo;
- entradas del cuaderno de cada capítulo;
- equilibrio económico de cada etapa (los créditos ganados deben bastar para el material del siguiente capítulo);
- Desafíos técnicos.

## 7. Riesgos

| Riesgo | Mitigación |
|---|---|
| Alcance enorme (simulador completo) | Hitos pequeños con versión jugable; etapas por fidelidad; nada entra sin pruebas |
| Rendimiento de la simulación en GDScript | Resolución analítica, recálculo por cambios, medir antes de optimizar |
| Pantalla del ordenador poco legible o con entrada problemática | *Spike* S2 en el Hito 2, con alternativa `push_input` |
| Coste de la navegación dinámica | *Spike* S3; limitar el rehorneado a cambios reales |
| Contenido educativo incorrecto | [TECH_RESEARCH.md](TECH_RESEARCH.md) con marcas de verificación; pruebas de honestidad |
| Arte 3D con un solo desarrollador | Greybox con dimensiones reales; el modelo se cambia sin tocar la lógica |
| Dependencia del plugin Godot AI | Todo es verificable sin él (CLI y `check_project.ps1`); no se exporta |
