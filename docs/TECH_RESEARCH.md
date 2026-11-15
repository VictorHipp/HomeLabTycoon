# TECH_RESEARCH — Investigación de tecnologías reales

> **Estado:** plan de investigación más las primeras entradas del prototipo (2026-11-15). Requisito `[CONFIRMADO]` (documento maestro §24): base de conocimiento extensa, por dominios, con fuentes fiables. No se introducen todas las tecnologías en la primera versión.

## 1. Método

1. **Elegir** el tema según la prioridad del índice (§4). Se investiga lo que necesita el siguiente hito, no todo a la vez.
2. **Rellenar la plantilla** (§3) consultando fuentes por orden de fiabilidad (§2).
3. **Marcar cada dato:**
   - `[VERIFICADO: fuente, fecha]` si se ha leído en la fuente;
   - `[POR VERIFICAR]` si no.
   - Un dato `[POR VERIFICAR]` **no** se usa en reglas del simulador ni en el cuaderno.
4. **Separar** tres cosas: cómo funciona en la realidad, cómo lo representa el juego y qué simplificación se acepta (y por qué).
5. **Definir las pruebas** que demostrarán que el simulador lo representa bien. Pasan a [TEST_PLAN.md](TEST_PLAN.md) cuando se implementa.
6. **Actualizar el estado** en el índice: `pendiente` → `en curso` → `listo para diseño` → `implementado`.

## 2. Jerarquía de fuentes

| Orden | Tipo | Ejemplos |
|---|---|---|
| 1 | Normas y especificaciones | IETF RFC (rfc-editor.org), IEEE 802.x, TIA/ISO/IEC (de pago: usar resúmenes reputados y señalarlo), ASHRAE TC 9.9 |
| 2 | Documentación oficial | Linux man-pages (man7.org), documentación de Debian y Ubuntu, systemd (freedesktop.org), kernel.org, Microsoft Learn, docs.godotengine.org |
| 3 | Fichas técnicas de fabricantes | Para rangos realistas (consumos, puertos, dimensiones). Nunca se copian marcas al juego |
| 4 | Referencias divulgativas reputadas | Wikipedia y similares **solo como puntero** hacia la fuente primaria; si se cita, se indica |
| 5 | Comunidad | Foros y blogs: solo como pista para buscar en fuentes de orden 1–3 |

## 3. Plantilla de entrada

```markdown
### <Tecnología>
- Estado: pendiente | en curso | listo para diseño | implementado · Prioridad: P0–P3 · Etapa: 1–6
1. Qué es:
2. Para qué sirve:
3. Cómo funciona realmente:            (con marcas [VERIFICADO]/[POR VERIFICAR])
4. Requisitos:
5. Hardware necesario:
6. Conocimientos previos:
7. Representación en el simulador:     (módulo, estado, reglas, consultas)
8. Simplificaciones aceptables:        (y por qué no rompen el aprendizaje)
9. Pruebas que lo demuestran:
10. Etapa de desbloqueo y justificación:
- Fuentes: (URL, fecha de consulta)
```

## 4. Índice por dominios

Prioridades:
- **P0:** necesario para el prototipo (Hitos 4–7).
- **P1:** resto de la Etapa 1.
- **P2:** Etapa 2.
- **P3:** Etapas 3–6.

| Dominio | Temas | Etapa | Prioridad | Estado |
|---|---|---|---|---|
| Fundamentos | Bits, bytes y unidades (SI vs. binarias); sistemas de numeración (binario, hexadecimal); cliente/servidor; modelo OSI y TCP/IP | 1 | P0–P1 | pendiente |
| Hardware | CPU, RAM, almacenamiento, fuentes, factores de forma, compatibilidades (socket, tipo de memoria), consumo típico | 1–2 | P1–P2 | pendiente |
| Redes | Ethernet de par trenzado (§5.1); switching y aprendizaje de MAC; VLAN 802.1Q; STP; IPv4 y subredes (§5.2); ARP; ICMP; enrutamiento; IPv6 y NDP; NAT; Wi-Fi 802.11 | 1–3 | P0–P2 | parcial |
| Telecomunicaciones | Acceso doméstico (fibra hasta el hogar, ONT, cable, móvil); fibra óptica (§5.4); transceptores; cableado estructurado; enlaces WAN y VPN entre sedes | 1–5 | P1–P3 | parcial |
| Sistemas operativos | Arranque, procesos, sistema de archivos, usuarios, permisos | 1 | P0–P1 | pendiente |
| Administración Linux | Jerarquía de archivos (FHS); coreutils y sus mensajes (§5.3); iproute2 (§5.5); bash (gramática del subconjunto); systemd y journald; gestión de paquetes Debian (apt/dpkg); SSH; red persistente | 1–2 | P0–P2 | parcial |
| Administración Windows | Windows Server, PowerShell, Active Directory, GPO, SMB | 3 | P3 | pendiente |
| Virtualización | Hipervisores de tipo 1 y 2, recursos virtuales, puentes de red virtuales, instantáneas, migración | 2–4 | P2–P3 | pendiente |
| Contenedores | Aislamiento, imágenes, redes de contenedores, orquestación (conceptos) | 2–4 | P2–P3 | pendiente |
| Almacenamiento | RAID (y por qué no es copia), NAS/SAN, SMB/NFS/iSCSI, sistemas de archivos, copias 3-2-1, instantáneas | 1–4 | P1–P3 | pendiente |
| Seguridad | Segmentación, firewall con estado, VPN, autenticación, claves SSH, principio de mínimo privilegio, actualizaciones | 1–5 | P1–P3 | pendiente |
| Servicios | DHCP (RFC 2131), DNS (RFC 1034/1035), HTTP, NTP, SMB, bases de datos, correo (conceptos) | 1–3 | P0–P2 | pendiente |
| Automatización | Scripts de shell, cron, gestión de configuración (conceptos) | 2–4 | P2–P3 | pendiente |
| Monitorización | Métricas, registros, alertas, SNMP, comprobaciones de salud, SLA | 2–4 | P2–P3 | pendiente |
| Infraestructura física | Racks EIA-310 (dimensiones, U); alimentación (circuitos, regletas, PDU, UPS); PoE 802.3af/at/bt; refrigeración y temperaturas (ASHRAE) | 1–6 | P0–P3 | pendiente |
| Redes empresariales | Diseño jerárquico (acceso, distribución, núcleo), enrutamiento dinámico (OSPF, conceptos), agregación de enlaces (LACP), Wi-Fi corporativa | 3–5 | P3 | pendiente |
| Centros de datos | Topología spine/leaf, pasillos frío/caliente, energía A/B, niveles de disponibilidad (Uptime Institute), PUE | 6 | P3 | pendiente |
| Alta disponibilidad | Redundancia vs. tolerancia a fallos, clústeres, balanceo, VRRP (conceptos), replicación | 4–5 | P3 | pendiente |
| Recuperación ante fallos | Copias, restauración, RTO/RPO, planes de recuperación, pruebas de restauración | 3–5 | P2–P3 | pendiente |

**Calendario:**
- antes del Hito 4: cableado, conectores y racks;
- antes del Hito 5: Ethernet, switching, IPv4, ARP, ICMP y DHCP;
- antes del Hito 6: FHS, coreutils, iproute2 y gramática de shell;
- antes del Hito 7: temas del cuaderno del prototipo.

## 5. Entradas del prototipo (P0)

### 5.1. Ethernet sobre par trenzado y su cableado

- **Estado:** en curso · **P0** · **Etapa 1**
1. **Qué es:** cableado de cobre de 4 pares trenzados con conectores 8P8C («RJ45») para Ethernet.
2. **Para qué sirve:** conectar equipos en red local.
3. **Cómo funciona:**
   - Las normas ANSI/TIA-568 definen los pinouts T568A y T568B, que solo difieren en el intercambio de los pares 2 y 3. La norma recomienda T568A para cableado horizontal.
   - Límites de longitud: 90 m de cableado horizontal instalado y 100 m de canal total con latiguillos; latiguillos de 5 m como máximo (revisión TIA/EIA-568-B).
   - `[VERIFICADO: Wikipedia «ANSI/TIA-568», 2026-11-15]` (fuente divulgativa; confirmar con un resumen de la norma vigente antes del Hito 4).
   - Velocidades por categoría y número de pares por estándar: `[POR VERIFICAR]`.
4. **Requisitos:** puertos RJ45 en ambos extremos, cable de categoría adecuada a la velocidad.
5. **Hardware:** cables y latiguillos, rosetas, paneles de parcheo, crimpadora o herramienta de inserción, probador.
6. **Conocimientos previos:** ninguno (primer tema del juego).
7. **Representación:**
   - `CableSpec` con categoría y longitud;
   - estado del enlace según compatibilidad y longitud ([NETWORK_SIMULATION.md](NETWORK_SIMULATION.md) §4–5);
   - pinout relevante solo en la crimpadora (Etapa 2).
8. **Simplificaciones:**
   - sin diafonía ni atenuación continua;
   - tablas discretas de «velocidad máxima según longitud»;
   - los cables comprados siempre están bien hechos, salvo avería inyectada.
9. **Pruebas:** canal de 100 m o menos con enlace; más de 100 m sin enlace con su motivo; un cable de categoría inferior limita la velocidad (cuando se verifiquen las cifras).
10. **Etapa 1:** es la base del cableado.
- **Fuentes:** https://en.wikipedia.org/wiki/ANSI/TIA-568 (2026-11-15).

### 5.2. Direccionamiento IPv4 y redes privadas

- **Estado:** en curso · **P0** · **Etapa 1**
1. **Qué es:** direcciones de 32 bits con prefijo (CIDR) que identifican interfaces y redes.
2. **Para qué sirve:** comunicar equipos dentro de una red y entre redes.
3. **Cómo funciona:**
   - Los bloques privados reservados son 10.0.0.0/8, 172.16.0.0/12 y 192.168.0.0/16 `[VERIFICADO: RFC 1918 §3, 2026-11-15]`.
   - Dos interfaces se comunican directamente si están en la misma subred y en el mismo dominio L2. Si no, necesitan un router `[POR VERIFICAR: RFC 791 / RFC 1122]`.
4. **Requisitos:** una interfaz con enlace y dirección configurada (estática o por DHCP).
5. **Hardware:** cualquier host con interfaz de red; un router para salir de la subred.
6. **Conocimientos previos:** qué es una red (5.1), números binarios básicos.
7. **Representación:** direcciones por interfaz en el `SimHost`; reglas de §7 de [NETWORK_SIMULATION.md](NETWORK_SIMULATION.md); `ip address` en la terminal.
8. **Simplificaciones:** sin fragmentación ni opciones IP; las direcciones de difusión y de red se tratan como no asignables.
9. **Pruebas:**
   - misma subred y mismo switch: comunican;
   - subred distinta sin router: no comunican, con el motivo en la traza;
   - IP duplicada: el conflicto se detecta.
10. **Etapa 1:** imprescindible para la primera misión.
- **Fuentes:** https://www.rfc-editor.org/rfc/rfc1918 (2026-11-15).

### 5.3. Órdenes básicas de coreutils y sus mensajes

- **Estado:** pendiente · **P0** · **Etapa 1**
- **Por investigar:**
  - comportamiento exacto y mensajes de error de `ls`, `cd` (de bash), `cat`, `mkdir`, `touch`, `rm`, `echo` y `pwd`;
  - qué mensajes se traducen con `LANG=es_ES.UTF-8` ([TERMINAL_DESIGN.md](TERMINAL_DESIGN.md) §10).
- **Fuentes previstas:** páginas man (man7.org), manual de GNU coreutils, manual de bash.

### 5.4. Fibra óptica: tipos y colores

- **Estado:** en curso · **P1** · **Etapa 2**
- **Colores de cubierta:** TIA-598C recomienda amarillo para monomodo; naranja para OM1/OM2; aguamarina para OM3/OM4 (algunos fabricantes, violeta para «OM4+»); verde lima para OM5 `[VERIFICADO: Wikipedia «Multi-mode optical fiber», 2026-11-15]`.
- **Alcance a 10 GbE:** OM3, hasta 300 m (misma fuente) `[VERIFICADO]`; OM4 a 400 m `[POR VERIFICAR]`.
- **Fuentes:** https://en.wikipedia.org/wiki/Multi-mode_optical_fiber (2026-11-15).

### 5.5. iproute2: la orden `ip`

- **Estado:** en curso · **P0** · **Etapa 1**
- **Sintaxis** `[VERIFICADO: man7.org ip-address(8), 2026-11-15]`:
  - `ip address add IFADDR dev IFNAME`;
  - `ip address del IFADDR dev IFNAME`;
  - `ip address [show [dev IFNAME] …]` (se puede omitir `show`).
  - `IFADDR` admite prefijo con barra (p. ej. `192.0.2.10/24`).
- **Persistencia:** la página man **no dice** si lo configurado con `ip` sobrevive a un reinicio `[POR VERIFICAR]`. Se espera que no y hay que confirmarlo en documentación de la distribución antes de decidir el comportamiento del prototipo.
- **Fuentes:** https://man7.org/linux/man-pages/man8/ip-address.8.html (2026-11-15).

### 5.6. Pendientes P0 sin empezar

| Tema | Fuente prevista |
|---|---|
| ARP | RFC 826 |
| ICMP echo y ping | RFC 792, página man de ping |
| Aprendizaje de MAC en switches | IEEE 802.1D / 802.1Q (resúmenes) |
| DHCP (DORA) | RFC 2131 |
| Bit de dirección MAC administrada localmente | IEEE 802 |
| Racks EIA-310: medidas **verificadas** el 2026-11-15 (§6); falta la numeración de las U | EIA-310 (resúmenes) |

## 6. Datos heredados que **requieren verificación**

Estas cifras aparecían como «datos reales» en la documentación v0 sin haber sido contrastadas. Quedan `[POR VERIFICAR]` y **no se usan** hasta verificarlas:

- Rack: ~~1U = 44,45 mm; panel de 19" = 482,6 mm; apertura 450 mm~~. **Verificado el 2026-11-15** (EIA-310-D citada en Wikipedia «19-inch rack»): 1U = 44,45 mm, panel de 482,6 mm, apertura de **450,85 mm**, taladros a 464,2–465,8 mm. Sigue pendiente: 42U ≈ 1,87 m útiles (se deduce de 42 × 44,45 mm), fondos de 600/800/1000/1200 mm y sentido de numeración de las U.
- Cobre: Cat5e 1G a 100 m; Cat6 10G hasta 55 m; Cat6a 10G a 100 m; Cat8 25/40G a 30 m; DAC pasivo SFP+ ≈ 5–7 m; OS2 10G a 10 km.
- Puertos: SFP 1G, SFP+ 10G, SFP28 25G, QSFP+ 40G, QSFP28 100G; 2,5G/5G (802.3bz).
- PoE: 802.3af 15,4 W, 802.3at 30 W, 802.3bt 60/90–100 W (potencia en el equipo de origen).
- Consumos típicos: servidor 1U, switch de 24 puertos, router doméstico, NAS.
- Conversión: 1 W = 3,412 BTU/h.
- Circuitos: 230 V × 16 A = 3680 W y 120 V × 15 A = 1800 W. La regla del 80 % de carga continua depende de la normativa y **no** es universal.
- Temperaturas ASHRAE: 18–27 °C recomendado y hasta 32 °C permitido (clase A1); umbrales de *throttling* (≈ 35 °C) y apagado (≈ 45 °C).
- Fiabilidad: tasa de fallo ×2 por cada +10 °C (regla empírica de Arrhenius).
- 100BASE-TX usa 2 pares; 1000BASE-T usa 4.
- Motor de física 3D por defecto en proyectos nuevos de 4.7.2: el ajuste devuelve `DEFAULT`, que no indica qué motor es.

## 7. Agente de investigación (propuesta)

`[PROPUESTA]` Un subagente de Claude Code, `tech-researcher`, que rellene una entrada de la plantilla para un tema dado, siga la jerarquía de fuentes y devuelva los datos marcados. No se crea sin aprobación ([ROADMAP.md](ROADMAP.md) §5).
