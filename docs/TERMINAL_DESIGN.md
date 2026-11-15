# TERMINAL_DESIGN — Ordenador simulado, terminal, SO, servicios y paquetes

> **Estado:** diseño; nada implementado. Requisitos `[CONFIRMADO]` (documento maestro §10–12, §23). Diseño técnico `[PROPUESTA]`.

## 1. Requisitos `[CONFIRMADO]`

- **Pantalla integrada en el mundo:** al usar un ordenador, la cámara se acerca a su pantalla y muestra un entorno simulado. Desde él se abre la tienda, se consultan pedidos, se administran equipos, se usan terminales, se consulta documentación, se diseñan topologías, se configuran servicios, se leen registros y se accede a interfaces de administración. Debe parecer un ordenador del mundo, no un menú genérico.
- **Terminal muy desarrollada**, sobre un estado simulado persistente:
  - sistema de archivos, usuarios, grupos y permisos;
  - procesos, variables de entorno, paquetes y servicios;
  - red, almacenamiento, registros, SSH, automatización y scripts.
- **Las órdenes usan el estado:** un servicio instalado aparece en la administración de servicios, un cambio de red afecta a la conectividad y un archivo creado se conserva.
- **Honestidad:** si una orden no está implementada, se informa claramente **sin inventar una ejecución correcta**.
- **Intérprete ampliable**, con estado persistente y pruebas automáticas.
- **Paquetes simulados:** gestores, catálogos, repositorios, dependencias, versiones, instalación, actualización, configuración, servicios y errores de instalación. **Nunca** se descarga ni se ejecuta software real.
- **Todo simulado:** sin SO, VM ni contenedores reales ([ADR 0006](adr/0006-fully-simulated-systems.md)).

## 2. El ordenador simulado («HomeLab OS») `[PROPUESTA]`

- **Escritorio ficticio** con identidad propia ([ART_STYLE.md](ART_STYLE.md) §9), mostrado en la pantalla del equipo ([INTERACTION_SYSTEM.md](INTERACTION_SYSTEM.md) §6).
- **Aplicaciones**, que son escenas `Control`. Cada una es una **vista** de módulos de simulación, nunca dueña de estado:

  | Aplicación | Hito / etapa |
  |---|---|
  | Navegador con la tienda | Hito 3 |
  | Pedidos y correo | Hito 3 |
  | Terminal | Hito 6 |
  | Diseñador de topologías | Etapa 1 tardía |
  | Monitor del sistema | Etapa 2 |
  | Explorador de archivos | Etapa 2 |
  | Interfaces web de administración de equipos (router, NAS, switch gestionable) | Etapas 1–3 |

- **Interfaces web de equipos:** el navegador solo las muestra si hay conectividad real con el equipo, comprobada en el motor de red.
- **Mismo modelo de host:** los servidores sin escritorio se usan por **consola local** o por **SSH**. Escritorio, consola y SSH son tres accesos al mismo host simulado.

## 3. Modelo de host simulado `[PROPUESTA]`

Todo equipo con SO (PC, servidor, NAS, router con CLI) tiene un `SimHost` en la simulación:

| Parte | Contenido |
|---|---|
| Identidad | hostname, imagen de SO (distribución ficticia y versión) |
| Sistema de archivos (VFS) | árbol de inodos con propietario, grupo, permisos, fechas de juego, contenido de texto |
| Usuarios y grupos | definidos en archivos del VFS (`/etc/passwd`, `/etc/group`) |
| Procesos | tabla con PID, PPID, usuario, orden, estado e inicio |
| Servicios | unidades tipo *init* con estado y habilitación |
| Paquetes | instalados, versiones, archivos que aportan |
| Red | interfaces vinculadas a puertos físicos, direcciones, rutas, configuración persistente y en ejecución |
| Registros | diario del sistema por unidad, con tiempo de juego |
| Sesiones | terminales abiertas (local, SSH), cada una con cwd, entorno e historial |

**Fuente de verdad:**
- **Configuración editable por el jugador** (`/etc/hosts`, la configuración de servicios, la red persistente, `/etc/passwd`): son **archivos reales del VFS** que los servicios y órdenes leen y analizan. Si el jugador los rompe, falla de forma realista y se ve en los registros.
- **Estado en tiempo de ejecución** (procesos, interfaces activas, montajes): es estado estructurado, expuesto como archivos virtuales (`/proc`) y mediante órdenes.

Todo el `SimHost` se guarda con la partida ([ARCHITECTURE.md](ARCHITECTURE.md) §7).

## 4. Intérprete de órdenes `[PROPUESTA]`

```
línea ─▶ Lexer (tokens, comillas, escapes) ─▶ Parser (AST) ─▶ Expansión (variables, ~, comodines)
      ─▶ Ejecutor (redirecciones, tuberías, listas &&, ||, ;) ─▶ ShellCommand.run(ctx) ─▶ código de salida
```

**Sintaxis por fases:**

| Fase | Elementos | Hito / etapa |
|---|---|---|
| 1 | Palabras, comillas `'…'` y `"…"`, escapes `\`, `;`, `&&`, `\|\|`, `\|`, `>`, `>>`, `<`, `$VAR`, `$?`, `~`, `#` comentarios | Hito 6 |
| 2 | Comodines `*` `?`, `$(…)`, asignaciones `VAR=valor`, `export` | Etapa 1 tardía |
| 3 | Scripts (subconjunto de shell: `if`, `for`, `while`, funciones), `cron` simulado | Etapa 2 |

**Garantías:**
- **Errores de sintaxis reales:** una comilla sin cerrar da un error como el de bash, no se ignora.
- **Robustez:** ninguna entrada puede colgar ni romper el juego, porque cada orden y cada bucle tienen límites. Se comprueba con pruebas de entradas aleatorias.

## 5. Contrato de una orden `[PROPUESTA]`

```gdscript
class_name ShellCommand extends RefCounted
func get_name() -> StringName
func run(ctx: CommandContext) -> int   # código de salida (0 = éxito)
# ctx: args, stdin, stdout/stderr (escritores), env, cwd, usuario, host (API del SimHost), reloj
```

- **Sin nodos ni UI:** una orden solo usa la API del `SimHost` y del motor de red. Por eso se prueba en *headless*.
- **Opciones estilo GNU** con un analizador común: cortas agrupables (`-la`), largas (`--all`) y `--`.
- **Operaciones largas** (instalar un paquete, `ping` sin límite): son **trabajos** que avanzan con el tiempo de juego y escriben su salida progresivamente. `Ctrl+C` las interrumpe con código 130.
- **Permisos** comprobados en un único punto: la API del VFS. Ninguna orden decide los permisos por su cuenta.

## 6. Honestidad: lo que no está implementado `[CONFIRMADO]` · mensajes `[PROPUESTA]`

| Situación | Respuesta |
|---|---|
| La orden no existe | `bash: foo: orden no encontrada` (como un sistema real) |
| Orden real que en el juego aporta un paquete no instalado | Sugerencia de instalación (al estilo de *command-not-found*): «La orden «htop» no se ha encontrado, pero se puede instalar con: apt install htop» |
| Orden real **todavía no implementada en el juego** | «htop es una orden real, pero aún no está implementada en HomeLab Tycoon.» |
| Opción real no implementada | «ls: la opción «-Z» existe en la herramienta real, pero aún no está implementada en el juego.» |
| Opción inexistente | El error que daría la herramienta real (opción no válida) |

Para distinguir esos casos, `data/terminal/` registra las **órdenes y opciones reales conocidas**. Una prueba automática garantiza que toda orden implementada tiene página de manual y pruebas, y que el manual solo documenta opciones implementadas.

## 7. Sistema de archivos, usuarios y permisos

- **Estructura** inspirada en la jerarquía estándar de Linux: `/etc`, `/home`, `/var/log`, `/usr/bin`, `/tmp`, `/proc`… `[POR VERIFICAR: FHS 3.0]`.
- **Archivos:** contenido de texto (los «binarios» son marcadores asociados a órdenes implementadas). Tamaños y fechas de juego.
- **Permisos:**
  - bits `rwx` para usuario, grupo y otros;
  - `root` ignora los permisos;
  - `umask` por defecto;
  - `sudo` por pertenencia a un grupo administrador (Etapa 1 tardía).
  - Comportamientos exactos `[POR VERIFICAR: páginas man de chmod, chown, sudo]`.
- **Límite de almacenamiento:** el VFS respeta el **disco simulado**. Si se llena, aparecen los errores correspondientes (avería «almacenamiento lleno»).
- **Editor de texto `[PROPUESTA]`:** un editor simulado sencillo, al estilo de `nano`, superpuesto en la terminal (guardar, salir, buscar). Es imprescindible para editar configuración. Llega en la Etapa 1 tardía, después del prototipo.

## 8. Procesos, servicios y registros

- **Procesos:** asignación de PID, árbol de procesos, señales (`TERM`, `KILL`, `HUP`) y consumo sintético de CPU y memoria según la carga de los servicios.
- **Servicios** (gestor tipo *systemd*, simplificado):
  - unidades aportadas por paquetes como archivos de texto en el VFS;
  - estados `active`, `inactive` y `failed`; habilitado o deshabilitado;
  - al arrancar, el servicio **valida su configuración**: si es errónea, queda `failed` y escribe el motivo en el diario;
  - al encender el equipo, arrancan las unidades habilitadas.
- **Diario:** `journalctl -u unidad` muestra las entradas con tiempo de juego. El flujo `configurar → reiniciar → consultar registros` es el bucle educativo central de la administración de sistemas.
- Semántica exacta de `systemctl` y `journalctl` `[POR VERIFICAR: documentación de systemd]`.

## 9. Paquetes y repositorios `[PROPUESTA]`

- **Índice de repositorio** (`data/packages/*.tres`):
  - nombre, versión, descripción y tamaño;
  - dependencias (con versión, Etapa 2);
  - lo que aporta: órdenes, unidades, configuración por defecto, páginas de manual y entradas del cuaderno relacionadas.
- **`apt update`:** descarga el índice. Requiere salida a Internet simulada; sin red falla como en la realidad (no se puede resolver o conectar).
- **`apt install`:**
  - resolución de dependencias (orden topológico) y confirmación `[S/n]`;
  - progreso con duración según tamaño y velocidad del enlace;
  - al terminar, registra órdenes, crea archivos y unidades, y habilita el servicio si procede.
  - Errores: dependencias no satisfechas, disco lleno, otra instalación en curso (bloqueo), sin red.
- **Otras operaciones:** `apt remove`, `apt purge`, `apt list --installed`, `apt search`, `apt show`, `apt upgrade` (Etapa 2).
- **Órdenes ligadas al paquete:** el **código** de cada orden existe en el juego, pero solo está disponible en el host si su paquete está instalado.
- **Repositorios:**
  - una distribución ficticia oficial;
  - más adelante, repositorios de terceros y «proyectos publicados» en una forja de código ficticia, representados de forma simulada.
- **Nombres:** las órdenes y protocolos estándar usan su nombre real (`ls`, `ssh`, `apt`). Los productos de marca (distribuciones, hipervisores, plataformas de contenedores) llevan nombres ficticios `[PROPUESTA]`. Pendiente de aprobación, ROADMAP §5.

## 10. Idioma de la salida `[PROPUESTA]`

- Cada host tiene una variable `LANG`, por defecto `es_ES.UTF-8`.
- **Mensajes que las herramientas reales traducen** (errores de coreutils, bash): aparecen en español, como en un sistema real configurado en español.
- **Formatos que no se traducen en la realidad** (columnas de `ip addr`, cabeceras de `ps`): se mantienen como en la herramienta real.
- Con `LANG=C` sale en inglés, y eso prepara la localización.
- Todas las cadenas pasan por `tr()` en el dominio `terminal` ([ARCHITECTURE.md](ARCHITECTURE.md) §9).
- Pendiente `[POR VERIFICAR]`: qué mensajes traduce realmente cada herramienta.

## 11. Red desde la terminal

- **`ip`:**
  - sintaxis de `ip address add|del|show` según la página man de iproute2 `[VERIFICADO: man7.org ip-address(8), 2026-11-15]`, p. ej. `ip address add 192.168.1.50/24 dev eth0`;
  - también `ip link set dev up|down`, `ip route` e `ip neigh`.
  - Las abreviaturas reales (`ip a`, `ip addr`) se admiten.
- **Persistencia de la configuración** `[PROPUESTA]` `[POR VERIFICAR]`:
  - en Linux, lo configurado con `ip` es de ejecución y no sobrevive a un reinicio (la página man consultada no lo indica explícitamente);
  - la configuración persistente vendría de un archivo de red con su orden de aplicación (Etapa 1 tardía).
  - En el prototipo, un reinicio por corte de alimentación pierde la IP. Decisión pendiente, ROADMAP §5.
- **`ping`:** consulta el motor de red y muestra salida al estilo real (líneas por respuesta y resumen) con tiempos sintéticos coherentes con la topología. Si falla, el mensaje refleja la causa real («Destination Host Unreachable» o sin respuesta). La traza detallada queda para herramientas de diagnóstico y para el cuaderno.
- **`ss -tlnp`** lista los sockets a la escucha. **`ssh usuario@host`** abre una sesión anidada en otro `SimHost` si hay conectividad, servicio a la escucha y credenciales válidas; `exit` vuelve. **`curl`** obtiene contenido de servidores web simulados (Etapa 2).

## 12. Virtualización, contenedores y Windows (futuro)

- **Virtualización (Etapa 2/4):** un `SimHost` puede ser **virtual**, con un `hypervisor_host_id`. Consume CPU, RAM y almacenamiento del host físico y se conecta por un puente virtual a su interfaz física. Mismo modelo de host, sin duplicar código.
- **Contenedores (Etapa 2–3):** grupos de procesos aislados con su propio sistema de archivos y mapeo de puertos, dentro de un host.
- **Administración Windows (Etapa 3+):** un intérprete alternativo, de estilo PowerShell, sobre el mismo modelo de host. Requiere investigación ([TECH_RESEARCH.md](TECH_RESEARCH.md)).

## 13. Órdenes por etapa educativa `[PROPUESTA]`

Las del prototipo van en **negrita**. La validez educativa de cada etapa se investiga ([TECH_RESEARCH.md](TECH_RESEARCH.md), dominio «Administración Linux»).

| Etapa | Órdenes |
|---|---|
| 1 | **help man clear echo pwd cd ls cat mkdir touch rm hostname whoami ip ping history exit** · cp mv grep less head tail sudo nano ps kill systemctl journalctl apt ssh ss df free |
| 2 | chmod chown useradd usermod passwd groups find tar curl wget dig traceroute mount lsblk crontab scripts, red persistente |
| 3 | rsync firewall (nftables/ufw simplificado) gestión de usuarios centralizada, administración de servicios de directorio |
| 4+ | Virtualización (CLI ficticia), contenedores, herramientas de monitorización, alta disponibilidad, automatización |

## 14. Conjunto del prototipo (Hito 6): comportamiento exacto

| Orden | Admite | Notas |
|---|---|---|
| `help` | — | Órdenes disponibles en este host |
| `man ORDEN` | — | Solo opciones implementadas, con enlace al cuaderno |
| `clear` | — | |
| `echo` | `-n`, `$VAR`, redirección | `echo hola > nota.txt` crea el archivo |
| `pwd`, `cd` | `cd ~`, `..`, `-`, rutas relativas y absolutas | |
| `ls` | `-l`, `-a`, varias rutas | Formato largo con permisos, propietario, tamaño y fecha |
| `cat` | varios archivos | Error real si no existe o es un directorio |
| `mkdir` | `-p` | |
| `touch` | — | Crea o actualiza la fecha |
| `rm` | `-r`, `-f` | Sin papelera: es real |
| `hostname`, `whoami` | — | |
| `ip` | `address show/add/del`, `link show/set up/down`, `route show`, `route add default via` | Formato real de salida |
| `ping` | `-c N` | IP o nombre de `/etc/hosts`. Sin DNS simulado, el resto de nombres da el error real de resolución más una nota honesta |
| `history`, `exit` | — | `exit` cierra la sesión (SSH) o la consola |

- **Sesión del servidor en el prototipo `[PROPUESTA]`:** consola local como `root`, para evitar `sudo` antes de enseñarlo. En el PC, usuario normal.
- **Prompt:** `usuario@host:ruta$`, o `#` para root.

## 15. Pruebas

Ver [TEST_PLAN.md](TEST_PLAN.md):
- pruebas unitarias por orden con un host de prueba;
- salidas de referencia («golden»);
- pruebas del lexer y del parser, incluidas entradas aleatorias que no deben romper nada;
- pruebas de honestidad (§6);
- persistencia: crear archivo → guardar → cargar → existe.
