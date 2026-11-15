# PROGRESSION — Economía, niveles, competencias, etapas y misiones

> **Estado:** diseño; nada implementado. Requisitos `[CONFIRMADO]` (documento maestro §4, §5, §19, §20, §22, y respuesta del usuario del 2026-11-15: juego **extenso**, con muchas partes, puntos y recompensas, y **las recompensas sirven para comprar material nuevo**). Diseño concreto (listas, cifras, validadores) `[PROPUESTA]`. La estructura de una carrera larga está en §10.

## 1. Requisitos `[CONFIRMADO]`

- **Indicadores:** dinero virtual, nivel general, experiencia, reputación, desbloqueos, contratos y competencias técnicas.
- **Recompensas** al completar proyectos. Subir de nivel **no depende solo de acumular puntos**: algunos niveles exigen **demostrar conocimientos concretos**. Por ejemplo, redes empresariales requieren haber resuelto antes proyectos de redes domésticas y de pequeñas oficinas.
- **Sin** esperas artificiales ni tareas repetitivas.
- **Misiones:** descripción, contexto, presupuesto, requisitos, restricciones, recompensas y criterios de éxito.
- **Varias soluciones válidas:** se comprueba que la infraestructura funciona, no una secuencia de acciones.
- **Modos:** Carrera, Sandbox y Desafíos técnicos.
- **Gestión de recursos:** dinero, experiencia, espacio, energía, refrigeración, CPU, RAM, almacenamiento, velocidad de red y mantenimiento. Las decisiones tienen consecuencias: se aprende a **dimensionar**, no a comprar siempre lo más caro.
- **Progresión en seis etapas**, de la habitación al centro de datos (§4).

## 2. Indicadores `[PROPUESTA]`

| Indicador | Cómo se gana | Para qué sirve |
|---|---|---|
| Dinero (créditos, entero) | Contratos, ventas de equipo usado | Comprar equipos, pagar costes |
| Experiencia (XP) | Contratos y desafíos, según dificultad y calidad | Sube el **nivel general** |
| Nivel general | Umbrales de XP | Tamaño del tablón de contratos, apps y herramientas del escritorio, categorías de la tienda |
| Reputación por segmento (Particulares, Pymes, Empresas, CPD) | Contratos cumplidos a tiempo y bien | Ofertas mejores y mejor pagadas; acceso a clientes mayores |
| Competencias técnicas | **Pruebas de competencia** superadas (§3) | Requisito de contratos y de etapas |
| Desbloqueos | Combinación de lo anterior | Catálogo, espacios, herramientas, automatizaciones |

**Regla anti-farmeo:** la XP permite acceder a algo **solo junto con** las competencias exigidas. Repetir contratos fáciles da poca XP y nunca da competencias que no ejercitan.

## 3. Competencias y pruebas de competencia `[PROPUESTA]`

Dominios con rangos de 0 a 5 (Novato, Aprendiz, Competente, Avanzado, Experto, Maestro).

| Dominio | Ejemplo de prueba (rango 1 → 3) |
|---|---|
| Hardware y montaje | Montar un servidor en rack con alimentación → sustituir un componente averiado sin perder servicio |
| Cableado | Conectar equipos con el cable adecuado → cableado estructurado con panel de parcheo dentro de límites |
| Redes locales (L2) | Red con switch funcionando → VLAN aisladas comprobadas |
| Redes IP (L3) | Dos equipos comunicados en la misma subred con IP estática → enrutar entre subredes |
| Servicios de red | DHCP sirviendo direcciones → DNS interno resolviendo nombres |
| Sistemas Linux | Navegar y crear archivos → instalar y configurar un servicio que arranca tras un reinicio |
| Almacenamiento y copias | Carpeta compartida → copia **restaurable** verificada |
| Seguridad | Red de invitados aislada → firewall con reglas mínimas necesarias |
| Energía y climatización | Presupuesto eléctrico respetado → UPS con autonomía suficiente |
| Virtualización y contenedores | Una VM con servicio → varias VM con recursos dimensionados |
| Monitorización y operación | Alertas básicas → detectar y resolver una avería antes de incumplir el SLA |
| Alta disponibilidad y recuperación | Servicio que sobrevive al fallo de un enlace → recuperación ante desastre con RTO/RPO pedidos |
| Diseño y planificación | Plan de topología que coincide con lo construido → presupuesto óptimo dentro de requisitos |

- **Cómo se obtiene una prueba:** los **validadores** de misión (§6) la verifican sobre el estado del mundo cuando se completa una misión que la concede. También los Desafíos técnicos.
- **Cada prueba se consigue una vez:** queda registrada como avance educativo y se guarda.

## 4. Etapas de progresión `[CONFIRMADO: etapas y contenidos]` · desbloqueos y misiones `[PROPUESTA]`

| Etapa | Espacio | Desbloquea (catálogo y herramientas) | Competencias que se introducen | Misiones de ejemplo | Sistemas de simulación necesarios |
|---|---|---|---|---|---|
| 1 Hogar | Habitación propia | Router doméstico, switch no gestionable, servidor de entrada, NAS pequeño, AP, cámaras IP, cables de cobre; probador de cables | Hardware 1, Cableado 1, L2 1, L3 1, Servicios 1, Linux 1, Almacenamiento 1 | Primer servidor (prototipo); carpeta compartida familiar; copias de seguridad; Wi-Fi de invitados; cámara IP | Electricidad básica, L1, L2 simple, IPv4, ARP, ICMP, DHCP, DNS básico, terminal Etapa 1, paquetes básicos |
| 2 Homelab avanzado | Habitación ampliada o garaje | Racks completos, switches gestionables, routers avanzados, firewalls, UPS, paneles de parcheo, refrigeración, componentes | Virtualización 1–2, L2 2 (VLAN), Linux 2 (SSH, servicios), Energía 1–2, Seguridad 1 | Laboratorio de virtualización; VLAN para IoT; acceso remoto seguro | VLAN, STP, transceptores y fibra, UPS, térmica, VM, contenedores, red persistente |
| 3 Pequeñas empresas | Oficinas de clientes (desplazamiento) | Wi-Fi corporativa, NVR, servidores de aplicaciones, gestión de usuarios | Seguridad 2, Servicios 2–3, Monitorización 1, Diseño 1 | Oficina de 10 empleados con servidor de archivos y Wi-Fi de invitados; cámaras para un comercio | Sitios múltiples, usuarios centralizados, firewall/NAT completo, monitorización |
| 4 Empresas medianas | Salas técnicas de cliente | Varios racks, almacenamiento compartido, firewalls empresariales | L3 3 (enrutamiento entre departamentos), HA 1, Almacenamiento 3, Monitorización 2 | Interconectar departamentos; almacenamiento compartido; monitorización centralizada | Enrutamiento dinámico básico, almacenamiento en red, redundancia de enlaces |
| 5 Grandes empresas | Edificios y varias sedes | Balanceadores, clústeres, almacenamiento de alta capacidad | HA 2–3, Seguridad 3, Diseño 3 | Alta disponibilidad de un servicio crítico; recuperación ante desastres; enlace entre sedes | Clústeres, replicación, VPN entre sedes, evaluación de resiliencia |
| 6 Centros de datos | Salas con filas de racks | Equipos de alta capacidad, energía redundante, refrigeración de CPD | Energía 4–5, Climatización, HA 4–5 | Diseñar una sala; cumplir requisitos de disponibilidad; operación a escala | Energía redundante (A/B), contención de pasillos, escalado de simulación, automatización |

**Cambios de etapa:** se pasa a la siguiente cuando se cumplen **nivel + competencias + reputación** exigidos. Los Desafíos permiten practicar sin arriesgar la Carrera.

## 5. Modos `[CONFIRMADO]`

- **Carrera:** tablón de contratos según etapa, nivel, reputación y competencias. Proyectos personales opcionales en el homelab propio (experimentar sin cliente).
- **Sandbox `[PROPUESTA]`:** dinero configurable (o ilimitado), todo desbloqueado, sin contratos obligatorios. Los logros educativos de Sandbox no cuentan para Carrera.
- **Desafíos técnicos:** escenarios cerrados con mundo inicial definido:
  - **construcción** con restricciones (presupuesto, espacio, energía);
  - **diagnóstico:** algo está roto y hay que encontrar por qué.

## 6. Misiones: estructura y validación `[PROPUESTA]`

```
MissionDefinition (data/missions/*.tres)
  id, etapa, segmento de cliente, contexto y descripción (claves de traducción)
  presupuesto, plazo opcional (sin castigos frustrantes)
  requisitos: Array[Requirement]       ← cada uno: validador + parámetros + entradas del cuaderno
  restricciones: Array[Constraint]     ← presupuesto máximo, consumo máximo, U disponibles…
  recompensas: dinero, XP, reputación, desbloqueos, pruebas de competencia
  criterios de excelencia (opcionales): coste, orden del cableado, redundancia
```

**Biblioteca de validadores:** son **consultas** a la simulación y nunca miran qué acciones se hicieron:
- `reachable(a, b, protocolo?)`, `isolated(a, b)`, `service_available(host, servicio, desde)`;
- `device_installed(categoría, ubicación)`, `powered(dispositivo)`, `link_speed_at_least(a, b, mbps)`;
- `vlan_membership(...)`, `budget_respected()`, `power_budget_ok(circuito)`;
- `backup_restorable(datos)`, `survives_failure(escenario)` (evalúa sobre una **copia** del mundo con la avería inyectada, [NETWORK_SIMULATION.md](NETWORK_SIMULATION.md) §10);
- `plan_matches_build(plan)`, que usa el diseñador de topologías.

**Evaluación:**
- La misión se completa cuando **todos los requisitos se cumplen a la vez**.
- El panel de la misión muestra cada requisito (cumplido o no) **sin revelar la solución**. Para ayuda, el cuaderno con sus niveles.
- **Varias soluciones:** cada misión se prueba con al menos dos soluciones distintas en las pruebas automáticas ([TEST_PLAN.md](TEST_PLAN.md)).

**Lugar:**
- Etapas 1–2: el homelab propio.
- Etapa 3+: los clientes tienen **sitios** propios en el mismo mundo simulado. El personaje se desplaza (mapa o furgoneta) `[PROPUESTA]`.

## 7. Tiempo y ritmo `[CONFIRMADO: simplificado, sin esperas frustrantes]` · cifras `[PROPUESTA]`

- **Reloj:** escala por defecto de 1 s real = 1 min de juego a ×1. Velocidades ×2 y ×4; «saltar hasta el evento» cuando no hay nada que hacer.
- **Duraciones de ejemplo:**
  - entrega estándar: 2–4 h de juego, saltable;
  - arranque de un servidor: 30–90 s de juego;
  - instalación de un paquete: según tamaño y velocidad;
  - transferencia: según el enlace.
- **Automatización:** las tareas repetitivas se simplifican en etapas avanzadas (recepción automática, plantillas de cableado, scripts).

## 8. Economía y equilibrio `[PROPUESTA]`

- **Ingresos:** contratos (pago base y extras por excelencia), venta de equipo usado con pérdida y, en etapas avanzadas, contratos de mantenimiento con SLA.
- **Costes:**
  - compras;
  - electricidad, desde la Etapa 2, según los kWh simulados;
  - alquiler de espacios, desde la Etapa 3;
  - mantenimiento y sustituciones;
  - penalizaciones por incumplir SLA (solo en contratos que lo pacten).
- **Procedimiento de equilibrio:**
  1. fijar el ritmo objetivo por etapa;
  2. simular el flujo de caja en *headless* con la propia simulación;
  3. ajustar precios y recompensas en los **datos**;
  4. comprobar que ninguna ruta domina y que cada etapa tiene un cuello de botella distinto.
- **Errores caros reversibles:** vender con pérdida, deshacer la colocación. El dinero negativo bloquea compras, no la partida.

## 9. Misión del prototipo: «Primer servidor» `[PROPUESTA]`

> Contexto: quieres montar tu primer servidor en casa para empezar tu homelab.

| Requisito | Validador | Cuaderno |
|---|---|---|
| R1. Hay un rack colocado en la habitación | `device_installed(rack, habitación)` | Cables y puertos |
| R2. El switch y el servidor están montados en el rack | `device_installed(switch, rack)`, `device_installed(servidor, rack)` | — |
| R3. Switch y servidor encendidos | `powered(switch)`, `powered(servidor)` | — |
| R4. El servidor se conecta a la red a través del switch | `cabled_to(servidor, switch)` y el switch tiene enlace activo con la red doméstica | Qué hace un switch |
| R5. El servidor tiene una IP válida de la red doméstica, sin conflicto | `ip_in_subnet(servidor, red_doméstica)` y `no_ip_conflict()` | Direcciones IP y subredes |
| R6. El PC y el servidor se comunican en ambos sentidos | `reachable(pc, servidor, icmp)` y `reachable(servidor, pc, icmp)` | Comprobar la conectividad con `ping` |

**Restricción:** presupuesto inicial suficiente para rack, switch, servidor y algún cable, con poco margen.

**Recompensas:** dinero, XP, prueba **Redes IP rango 1** y **Hardware rango 1**, y desbloqueo de la siguiente página del catálogo de la Etapa 1.

**Soluciones válidas** (las pruebas automáticas cubrirán al menos dos):
- PC → router y servidor → switch → router;
- PC → switch, servidor → switch y switch → router.

En ambos casos con cualquier IP libre de la subred y con el PC por DHCP.

## 10. Estructura de una carrera larga

`[CONFIRMADO: 2026-11-15]` El juego debe ser **extenso**, con muchas partes, un sistema de puntos y recompensas, y esas recompensas sirven para **comprar material nuevo**.

Las cifras y listas de esta sección son `[PROPUESTA]`.

**Vocabulario:** «hito» se reserva para el desarrollo (Hitos 1–7 del prototipo, [ROADMAP.md](ROADMAP.md)). Las partes del juego se llaman así:

| Nivel | Qué es |
|---|---|
| **Etapa** (6) | Gran fase de la carrera: Hogar → Centros de datos (§4) |
| **Capítulo** (4–6 por etapa) | Bloque temático con un objetivo propio, p. ej. «Compartir en casa» |
| **Misión** (3–6 por capítulo) | Contrato o proyecto con requisitos validados por el estado (§6). La última del capítulo es un **proyecto final** que combina lo aprendido |
| **Meta de carrera** | Logro transversal (p. ej. «Una semana sin caídas») con recompensa propia |
| **Desafío técnico** | Escenario cerrado de construcción o diagnóstico (§5) |

### 10.1. Volumen orientativo

| Etapa | Capítulos | Misiones de carrera | Desafíos | Metas |
|---|---|---|---|---|
| 1 Hogar | 5 | ≈ 20 | 5 | 10 |
| 2 Homelab avanzado | 5 | ≈ 22 | 6 | 12 |
| 3 Pequeñas empresas | 6 | ≈ 25 | 6 | 12 |
| 4 Empresas medianas | 6 | ≈ 25 | 6 | 12 |
| 5 Grandes empresas | 5 | ≈ 22 | 6 | 12 |
| 6 Centros de datos | 5 | ≈ 20 | 6 | 12 |
| **Total** | **32** | **≈ 134** | **≈ 35** | **≈ 70** |

Además, **contratos secundarios** generados a partir de plantillas (variantes de clientes, presupuestos y restricciones). Son opcionales y dan ingresos extra.

La duración sale de **contenido técnico distinto** en cada capítulo, no de repetir tareas ni de esperas `[CONFIRMADO: documento maestro §5]`.

### 10.2. Capítulos de la Etapa 1 (ejemplo)

| Capítulo | Contenido | Equipos que se compran |
|---|---|---|
| 1. Mi primera red | Cables, switch, IP; incluye la misión del prototipo «Primer servidor» (§9) | Rack pequeño, switch, servidor, cables |
| 2. Compartir en casa | Carpeta compartida, usuarios y permisos, NAS pequeño | NAS, discos |
| 3. Que no se pierda nada | Copias de seguridad y **restauración comprobada** | Disco externo o segundo NAS |
| 4. Wi-Fi para todos | Punto de acceso, red de invitados aislada, contraseñas | Punto de acceso, switch PoE |
| 5. Ojos en casa | Cámara IP, grabación, almacenamiento y consumo | Cámaras IP, almacenamiento |

### 10.3. Puntos y recompensas

| Recompensa | Qué hace | De dónde sale |
|---|---|---|
| **Créditos** (dinero) | **Se gastan en la tienda para comprar material.** Es el bucle principal de recompensa | Pago de misiones y contratos, extras por excelencia, venta de equipo usado |
| **Puntos de experiencia (XP)** | Suben el **nivel general**, que decide qué categorías y gamas aparecen en la tienda y cuántos contratos ofrece el tablón | Misiones y desafíos, según dificultad y calidad |
| **Reputación** | Clientes mejores y mejor pagados | Contratos bien cumplidos |
| **Pruebas de competencia** | Abren capítulos y etapas (§3) | Requisitos concretos de misiones y desafíos |
| **Recompensas especiales** | Material de segunda mano regalado por un cliente, cupones de descuento de la tienda, acceso anticipado a un producto | Excelencia, metas de carrera |
| **Personalización** | Ropa, pelo y accesorios del personaje; decoración de la sala | Metas de carrera |

**Reglas:**
- **Desbloquear no es regalar:** un desbloqueo hace que el producto **aparezca en la tienda**, pero hay que **comprarlo con créditos**. Excepción: Sandbox.
- **La XP solo da acceso junto con las competencias exigidas** (§2). Repetir contratos fáciles da cada vez menos créditos y XP y nunca da competencias.
- **Todo importe y precio está en los datos** y se equilibra con la simulación económica (§8).

### 10.4. Ritmo económico

- La recompensa de cada capítulo cubre ≈ 70–90 % del material que necesita el siguiente. El resto sale de la excelencia, los contratos secundarios o vender material viejo.
- Así se premia **dimensionar bien**: comprar lo justo deja margen para experimentar. Nunca obliga a farmear, porque los contratos secundarios siempre están disponibles y son variados.
- **Curva de nivel:** XP para el nivel *n* ≈ 100 × *n*^1,5; unos 50 niveles en toda la carrera.
- **XP por misión según dificultad:** básica 50, media 120, avanzada 250, experta 500; +25 % por excelencia.
- Estas cifras se ajustarán al probar el juego.

### 10.5. Ejemplos de metas de carrera

«Primer rack lleno» · «Cableado impecable» (todo etiquetado y ordenado) · «Una semana sin caídas» · «Diagnóstico relámpago» · «Presupuesto ajustado» (completar con menos del 80 % del presupuesto) · «Recuperado» (restaurar una copia tras una avería).
