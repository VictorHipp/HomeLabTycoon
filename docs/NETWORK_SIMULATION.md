# NETWORK_SIMULATION — Simulación de red e infraestructura física

> **Estado:** diseño; nada implementado. Requisitos `[CONFIRMADO]` (documento maestro §9, §13, §14–17, §20, §23). Enfoque técnico `[PROPUESTA]` ([ADR 0008](adr/0008-analytic-network-simulation.md)). UX del cableado en [INTERACTION_SYSTEM.md](INTERACTION_SYSTEM.md) §9; gestión de servicios desde el SO en [TERMINAL_DESIGN.md](TERMINAL_DESIGN.md).

## 1. Requisitos `[CONFIRMADO]`

- **Qué se modela:** dispositivos, interfaces, puertos, enlaces, IP, máscaras, rutas, ARP y NDP, switching, VLAN, enrutamiento, DNS, DHCP, firewall, NAT, protocolos, servicios y estados de conectividad.
- **Comprobaciones de conectividad:** su resultado depende de la configuración. Las configuraciones incorrectas tienen **consecuencias técnicas comprensibles**.
- **Nada por magia:** un equipo sin el enlace correcto no se comunica.
- **Motor separado de la representación visual**, probado automáticamente sin escena 3D.
- **Desarrollo incremental:** cada protocolo entra con pruebas y reglas verificables.
- **El cableado manda:** tipos, compatibilidad, longitud, puertos, velocidades, estado del enlace, alimentación, cableado estructurado, paneles de parcheo, fibra, PoE y transceptores.
- **Diagnóstico visual:** los indicadores reflejan el estado real. El jugador investiga las causas; no recibe un mensaje que le diga qué reparar.
- **Más adelante:** redundancia, averías con causa definida y gestión de energía y refrigeración.

## 2. Enfoque: estado + resolución analítica con trazas `[PROPUESTA]`

**Qué no se hace:** simular cada trama y cada paquete con tiempos (simulación de eventos discretos por paquete).

**Qué se hace:** el motor mantiene el **estado** (topología física, configuración de cada host y equipo) y **resuelve consultas** recorriendo esa topología según las reglas de cada capa.

**Ejemplo:** `ping(desde=PC, a=192.168.1.50)` produce una **traza** paso a paso:
1. ¿El PC tiene interfaz con IP y enlace?
2. ¿El destino está en la misma subred?
3. ¿Responde ARP? Requiere el mismo dominio L2 y el destino encendido con esa IP.
4. ¿Llega la petición ICMP? ¿Existe el camino de vuelta?
5. Resultado, o **el paso exacto donde falla y por qué**.

**Por qué:**
- es determinista y barato;
- se prueba con escenarios pequeños;
- cada fallo tiene una explicación legible, que es la base del aprendizaje y del diagnóstico;
- escala a salas grandes recalculando solo lo que cambió.

**Intercambios de protocolo con valor educativo** (DHCP con sus cuatro mensajes, ARP *who-has*): se representan como **secuencias de pasos en la traza**, que se pueden visualizar sin simular tiempos de paquete.

**Rendimiento** (ancho de banda, latencia, saturación): se calcula de forma analítica a partir de las velocidades de enlace y la carga, cuando haga falta (Etapa 2+).

**Puerta abierta:** si una herramienta futura necesitara simulación por paquete (captura de tráfico detallada), podría añadirse para un caso concreto sin cambiar el modelo de estado.

## 3. Electricidad

- **Grafo de alimentación:**
  - fuentes: toma de pared en un circuito con capacidad;
  - distribución: regleta, PDU, UPS;
  - consumidores: entrada de alimentación del equipo.
- **Equipo alimentado** si existe camino a una fuente con energía y no se supera la capacidad de ningún tramo.
- **Encendido:** botón de encendido → estado `BOOTING` durante un tiempo de arranque (dato del catálogo) → `RUNNING`. Sin alimentación no arranca (el LED no se enciende).
- **Consumo:** interpolación entre reposo y máximo según la carga. Superar la capacidad de una regleta o circuito corta la alimentación de todo lo conectado (evento).
- **UPS (Etapa 2):** autonomía = energía restante / carga. Al agotarse, apagado sin cierre limpio, con riesgo para los servicios.
- **Cifras pendientes:** capacidades de circuito, reglas de carga continua y potencias típicas están `[POR VERIFICAR]` en [TECH_RESEARCH.md](TECH_RESEARCH.md). Las reglas de carga continua difieren entre normativas (p. ej. Norteamérica y Europa): no se fija ninguna sin fuente.

## 4. Capa física: puertos, cables, transceptores y parcheo

- **Puerto (instancia):** `(id de dispositivo, grupo, índice)`. Tiene tipo de conector, velocidades admitidas, PoE (si aplica), estado administrativo (activo/desactivado) y, si es una jaula SFP, el transceptor insertado.
- **Cable (instancia):** su `CableSpec` define conectores en ambos extremos, medio (cobre por categoría o fibra por tipo), longitud y velocidad máxima según la longitud. Estado: correcto o averiado (tipo de avería).
- **Transceptores (Etapa 2):** módulos que se insertan en jaulas SFP/SFP+/QSFP. El enlace exige transceptores compatibles con el medio en ambos extremos (multimodo con multimodo, misma longitud de onda) y fibra adecuada.
- **Cableado estructurado (Etapa 2–3):**
  - la roseta de pared y el panel de parcheo son elementos **pasivos**: la toma frontal de un panel está unida a su enlace permanente trasero;
  - el canal completo es la suma de los tramos (latiguillo + enlace permanente + latiguillo);
  - límites de longitud: horizontal ≤ 90 m y total del canal ≤ 100 m incluidos latiguillos `[VERIFICADO: Wikipedia «ANSI/TIA-568», sobre la revisión TIA/EIA-568-B, 2026-11-15]`. Confirmar en fuente primaria antes del Hito 4.
- **Datos de referencia de fibra:**
  - OM3 soporta 10 GbE hasta 300 m `[VERIFICADO: Wikipedia «Multi-mode optical fiber», 2026-11-15]`;
  - OM4 a 400 m `[POR VERIFICAR]`.

## 5. Enlaces: estado y negociación

```
SIN_CABLE → CONECTADO (un extremo) → NEGOCIANDO (≈ 1–3 s de juego) → ACTIVO | DEGRADADO | CAÍDO(motivo)
```

**Un enlace está ACTIVO** si:
1. ambos extremos están conectados;
2. ambos equipos están alimentados y encendidos;
3. ambos puertos están activos;
4. los conectores y el medio son compatibles;
5. la longitud está dentro del alcance;
6. el cable no está averiado de forma que impida el enlace.

**Velocidad:**
- velocidad = la **mayor velocidad común** de ambos puertos, limitada por lo que admite el cable a esa longitud;
- si es menor que la nominal de ambos puertos, el enlace queda **DEGRADADO** y se explica («el cable limita a 1 Gbps»).

**Motivos de CAÍDO** (los muestran la interfaz y la terminal): sin alimentación en el otro extremo, conector incompatible, longitud excedida, cable averiado, puerto desactivado, transceptor ausente o incompatible.

**Dúplex:** completo. El semidúplex queda para hubs y casos educativos.

## 6. Capa 2 (switching y VLAN)

- **MAC por interfaz:** se generan de forma determinista con el bit de «administrada localmente», p. ej. `02:xx:…` `[PROPUESTA]`, para no imitar fabricantes reales. `[POR VERIFICAR]` Formato del bit U/L según IEEE 802.
- **Switch no gestionable:** un único dominio de difusión con todos sus puertos activos.
- **Switch gestionable (Etapa 2):**
  - VLAN por puerto: modo acceso (una VLAN) o troncal (802.1Q, varias VLAN etiquetadas y una nativa);
  - el dominio L2 de una VLAN es la componente conexa de enlaces activos que la transportan;
  - se calcula con unión-búsqueda y se recalcula al cambiar un enlace o la configuración.
- **Tabla MAC:** se muestra en la CLI del switch (Etapa 2), derivada del dominio y de los hosts que han «hablado».
- **Bucles:** sin STP, un bucle provoca una **tormenta de difusión** (evento con síntomas visibles: LED de actividad saturados, conectividad que falla). STP se introduce en la Etapa 2–3 como solución.
- **Hubs (educativo, Etapa 1 opcional):** dominio de colisión compartido y semidúplex.

## 7. Capa 3 (IP y enrutamiento)

- **Interfaces:** una o varias direcciones IPv4 con prefijo. IPv6 y NDP en etapas posteriores `[CONFIRMADO: en la lista; etapa por decidir]`.
- **Redes privadas:**
  - 10.0.0.0/8, 172.16.0.0/12 y 192.168.0.0/16 `[VERIFICADO: RFC 1918 §3, 2026-11-15]`;
  - la red doméstica del prototipo usa un bloque de 192.168.0.0/16.
- **ARP:**
  - la resolución tiene éxito si el destino está en la **misma subred**, en el **mismo dominio L2**, encendido y con esa IP;
  - las entradas resueltas forman la caché visible con `ip neigh`;
  - un conflicto de IP (dos hosts con la misma dirección) produce síntomas intermitentes y es investigable.
  - Detalles del protocolo `[POR VERIFICAR: RFC 826]`.
- **Enrutamiento:**
  - tabla por host: rutas conectadas automáticas, puerta de enlace por defecto y rutas estáticas;
  - coincidencia del prefijo más largo;
  - los routers reenvían entre interfaces y decrementan el TTL;
  - errores ICMP en la traza: destino inalcanzable, TTL excedido.
- **ICMP echo (ping):** necesita ida **y vuelta**. Una ruta de vuelta mal configurada falla aunque la ida sea correcta, y eso enseña. Detalles `[POR VERIFICAR: RFC 792]`.
- **NAT y firewall (Etapa 1 tardía y Etapa 2):**
  - el router doméstico hace NAT de origen LAN → WAN;
  - reglas de firewall con estado simplificado (permitir lo establecido y lo explícito);
  - evaluadas en la traza, con la regla que bloquea.
- **Internet simulada `[PROPUESTA]`:** más allá del WAN del router hay una «nube» del proveedor con servicios públicos simulados (repositorios de paquetes, la tienda, DNS públicos). Instalar software o comprar requiere salida a Internet.

## 8. Servicios de red y conexiones de aplicación

- **Socket de escucha:** cada servicio escucha en `(IP, puerto, protocolo)`; se muestra con `ss -tlnp` ([TERMINAL_DESIGN.md](TERMINAL_DESIGN.md)).
- **Conexión** (ssh, curl, montar recurso compartido): alcanzabilidad L3 + firewall + socket a la escucha + autenticación cuando aplique.
- **DHCP:**
  - servidor con rango, puerta de enlace y DNS;
  - cliente en una interfaz en modo DHCP;
  - el arrendamiento se concede si hay un servidor en el mismo dominio L2 (o un *relay*, Etapa 3);
  - la traza muestra los cuatro mensajes (Discover, Offer, Request, Ack).
  - Detalles `[POR VERIFICAR: RFC 2131]`.
- **DNS (Etapa 1–2):** zonas en servidores simulados, resolutor del host configurado por archivo, recursión hacia el proveedor. Los fallos de DNS son una avería clásica e investigable.
- **Etapas posteriores:** HTTP, SSH, SMB/NFS, NTP, monitorización, bases de datos, copias de seguridad, cada uno con su comportamiento mínimo verificable.

## 9. Diagnóstico visual y herramientas

| Indicador o herramienta | Refleja | Etapa |
|---|---|---|
| LED de alimentación | Alimentado / encendido / en arranque (parpadeo) / averiado | 1 |
| LED de puerto | Enlace (fijo), actividad (parpadeo), velocidad (color por convención del juego) | 1 |
| Ventiladores | Giran si está encendido; su velocidad y ruido crecen con la temperatura | 1 (visual), 2 (térmico) |
| Alarmas del equipo | Sobretemperatura, fuente averiada, disco fallido | 2 |
| Indicadores de disco | Actividad y fallo | 2 |
| Cables desconectados o colgando | Visibles en el mundo | 1 |
| `ip`, `ping`, `ss` | Estado de interfaces y conectividad | 1 |
| Probador de cables | Continuidad, mapa de pares, longitud estimada, cable averiado | 1–2 |
| `traceroute`, registros, paneles de monitorización | Caminos, eventos, métricas | 2–3 |

**Regla:** todo indicador lee el estado simulado. Ejemplo: si un switch pierde la alimentación, sus LED se apagan, sus enlaces caen y los hosts conectados pierden la conectividad, todo como consecuencia del modelo.

## 10. Averías, redundancia y recuperación

- **Inyección de averías:** `inject_fault(objetivo, tipo, parámetros)` para misiones, desafíos y, en Carrera, averías por desgaste.
- **Causa definida:** toda avería tiene una causa y al menos una pista observable y un camino de diagnóstico.
- **Tipos `[CONFIRMADO: lista del usuario]`:**
  - fallo de alimentación;
  - cable defectuoso;
  - puerto averiado;
  - disco dañado;
  - almacenamiento lleno;
  - error de configuración;
  - conflicto de IP;
  - problema de DNS;
  - fallo de servicio;
  - sobrecalentamiento;
  - recursos insuficientes;
  - VLAN mal configurada;
  - fallo de hardware.
- **Ejemplo realista:** un cable con un par cortado podría bajar el enlace de 1 Gbps a 100 Mbps, porque 1000BASE-T usa los cuatro pares y 100BASE-TX dos `[POR VERIFICAR]`. Si se verifica, es una avería excelente para enseñar.
- **Redundancia (Etapas 3–6):**
  - fuentes dobles, varios circuitos, UPS;
  - enlaces agregados y caminos redundantes;
  - servidores de respaldo, alta disponibilidad, clústeres, replicación;
  - RAID con sus límites: **no es copia de seguridad**;
  - copias y restauración.
- **Disponibilidad de un servicio:** se calcula sobre su **grafo de dependencias** (host → alimentación, red, almacenamiento → servicios de los que depende).
- **Evaluación de resiliencia `[PROPUESTA]`:** una misión puede pedir que el servicio sobreviva al fallo de X. Se evalúa sobre una **copia** del mundo con la avería inyectada; el mundo real no se toca ([PROGRESSION.md](PROGRESSION.md) §6). Métricas avanzadas: disponibilidad, tiempo de recuperación y pérdida de datos simulada.

## 11. Diseñador de topologías (mismos datos) `[CONFIRMADO: funciones]` · diseño `[PROPUESTA]`

- **Qué es:** una aplicación del escritorio simulado. Un **plan** es un documento propio: nodos que referencian **definiciones del catálogo**, enlaces entre puertos concretos, nombres, VLAN y subredes. Se guarda en la partida.
- **Sin sistemas duplicados:** usa las mismas definiciones, tipos de puerto y reglas de compatibilidad que el mundo físico. Un enlace imposible (RJ45 a SFP+) se marca en el plan igual que en la realidad.
- **Comparación plan ↔ instalación (versión avanzada):** `diff(plan, mundo)` lista equipos ausentes, conexiones distintas, puertos equivocados y configuración incompleta. Ayuda a diagnosticar y puede servir de validador de misión.
- **Reutilización:** el mismo renderizador de diagramas sirve para las ilustraciones del cuaderno ([TUTORIAL_SYSTEM.md](TUTORIAL_SYSTEM.md) §6).

## 12. Calor y refrigeración (Etapa 2+)

- El calor generado es aproximadamente la potencia consumida.
- La temperatura de la sala evoluciona según el calor aportado y la refrigeración instalada. Hay umbrales de *throttling* y de apagado por protección.
- Fórmulas y umbrales (incluidas recomendaciones de ASHRAE) `[POR VERIFICAR]` en [TECH_RESEARCH.md](TECH_RESEARCH.md).

## 13. Alcance del prototipo (Hito 5)

| Incluido | Fuera |
|---|---|
| Grafo de alimentación: toma → regleta → equipos; botón de encendido; arranque con duración | Capacidades eléctricas detalladas, UPS |
| Puertos RJ45, cables Cat6 con longitud; estados de enlace con motivo; velocidad negociada | Fibra, transceptores, PoE, parcheo |
| Switch no gestionable (un dominio L2) | VLAN, STP |
| IPv4 estática; ARP; ping con traza; ruta por defecto | Enrutamiento entre subredes, NAT, firewall |
| DHCP mínimo en el router doméstico `[PROPUESTA]` (ROADMAP §5) | DNS |
| Conectividad a «Internet simulada» para la tienda `[PROPUESTA]` | Rendimiento y latencia |

## 14. Pruebas

Ver [TEST_PLAN.md](TEST_PLAN.md) §3:
- constructor de escenarios para montar topologías en pocas líneas;
- invariantes (velocidad del enlace = mínimo de la cadena, un dominio sin enlaces está aislado);
- trazas de referencia («golden»);
- reproducibilidad con semilla.
