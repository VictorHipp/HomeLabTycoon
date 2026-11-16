# HARDWARE_CATALOG — Equipamiento, tienda, pedidos e inventario

> **Estado:**
> - **Implementado:** `HardwareDefinition` y `PortDefinition` (`sim/hardware/`) y un item (`data/catalog/rack_42u_basic.tres`).
> - **Modelos provisionales del prototipo** (sin entrada de catálogo todavía): rack de 12U, switch de 16 puertos, servidor 1U, router doméstico, PC antiguo, monitor, regleta y caja de paquete, en `assets/models/` ([ART_STYLE.md](ART_STYLE.md) §11).
> - **Diseño:** todo lo demás.
>
> Requisitos `[CONFIRMADO]` (documento maestro §6–8). Procedimiento para añadir items: skill `hardware-catalog`.

## 1. Requisitos `[CONFIRMADO]`

- **Tienda online ficticia** inspirada en las reales, accesible desde los ordenadores del juego: categorías, buscador, filtros, fichas, especificaciones, precios, disponibilidad, compatibilidad, carrito, historial y pedidos.
- **Productos ficticios** con especificaciones coherentes con tecnologías reales.
- **Catálogo definido por datos** y fácil de ampliar.
- **Compra simulada completa:** elegir, comparar, pagar, información del pedido, espera, recepción, apertura, extracción e instalación. Tiempos simplificados; automatizable en etapas avanzadas.
- **Montaje con consecuencias técnicas:** tamaño, compatibilidad, recursos, puertos, consumo, capacidad y limitaciones. Sin tornillos individuales.

## 2. Categorías

Los items de la lista del usuario están marcados con «·»; los añadidos por investigación (profesiones de telecomunicaciones, redes, sistemas, seguridad e infraestructura), con «+». La etapa es la de desbloqueo propuesta `[PROPUESTA]`. La investigación de cada familia está en [TECH_RESEARCH.md](TECH_RESEARCH.md).

| Familia | Categorías | Etapa |
|---|---|---|
| Componentes | · Procesadores · Placas base · Memoria RAM · SSD y HDD + Fuentes de alimentación + Chasis + Tarjetas de red (NIC) + Controladoras HBA/RAID + Tarjetas gráficas | 2 |
| Equipos de cómputo | · Servidores (torre, rack 1U/2U/4U) + Mini PC + Placas SBC + Estaciones de trabajo + PC y portátiles + Servidores blade (6) | 1–6 |
| Almacenamiento | · NAS · Componentes de almacenamiento + Cabinas/JBOD + Cintas LTO | 1–5 |
| Red | · Routers · Switches (no gestionables, gestionables, L3) · Hubs (educativo) · Firewalls · Puntos de acceso · Controladoras Wi-Fi + Módems/ONT + Balanceadores de carga | 1–5 |
| Conectividad física | · Cables · Fibra óptica · Transceptores · Paneles de parcheo + Rosetas/tomas de pared + Latiguillos + DAC/AOC + Organizadores y bandejas | 1–4 |
| Infraestructura física | · Racks · UPS · PDU · Equipos de refrigeración + Regletas + Conmutadores de transferencia (ATS) + KVM y consola de rack + Sensores ambientales | 1–6 |
| Diagnóstico | · Herramientas de diagnóstico: + probador de cables, + crimpadora y herramienta de inserción, + cable de consola serie, + analizador Wi-Fi, + certificador de cableado, + medidor de potencia óptica y OTDR, + cámara térmica | 1–5 |
| Seguridad física y vigilancia | · Cámaras IP + Grabadores NVR + Control de acceso | 1–3 |
| IoT | · Dispositivos IoT (sensores, enchufes inteligentes, termostatos) | 1–2 |
| Centro de datos | · Equipamiento para CPD: + contención de pasillo frío/caliente, + PDU trifásicas, + switches *spine/leaf*, + servidores de alta densidad, + suelo técnico | 6 |

## 3. Esquema de datos

### 3.1. Implementado hoy

**`HardwareDefinition`**:

| Campo | Tipo | Notas |
|---|---|---|
| `id` | `StringName` | snake_case, único, estable; el nombre del archivo es el id |
| `category` | `enum Category` | `RACK, SERVER, SWITCH, ROUTER, CABLE, ACCESSORY` |
| `display_name` | `String` | Marca ficticia + modelo |
| `description` | `String` | Multilínea |
| `price` | `int` | Créditos enteros |
| `mount_height_u` | `int` | U que ocupa; 0 si no es montable |
| `capacity_u` | `int` | Solo racks |
| `power_idle_watts` / `power_max_watts` | `float` | Reposo ≤ máximo |
| `ports` | `Array[PortDefinition]` | Grupos homogéneos de puertos |
| `scene` | `PackedScene` | Escena 3D |

**`PortDefinition`**:

| Campo | Tipo | Notas |
|---|---|---|
| `id` | `StringName` | Único dentro del item |
| `kind` | `enum Kind` | `RJ45, SFP, SFP_PLUS, SFP28, QSFP_PLUS, QSFP28, POWER_C14, POWER_C13` |
| `count` | `int` | Número de puertos del grupo |
| `speed_mbps` | `int` | 0 en puertos de energía |
| `poe_budget_watts` | `float` | Presupuesto PoE del grupo |

### 3.2. Evolución propuesta `[PROPUESTA]` (Hito 3)

**Problema:** con decenas de categorías y comportamientos, un `enum` fijo y una clase con todos los campos no escalan. Cada categoría nueva obligaría a tocar código, y la clase acabaría con campos vacíos para la mayoría de items.

**Propuesta: composición.**

```
HardwareDefinition               (común a todo producto)
  id, category: StringName  ──▶ CategoryDefinition (data/catalog/categories/*.tres: id, padre, icono, clave de nombre)
  brand, model, display_name, description
  price, stage_unlock, condition (nuevo/reacondicionado)
  dimensions_m: Vector3, mounting: NONE|RACK|DESK|FLOOR|WALL, mount_height_u
  power_inputs (grupos), power_idle_watts, power_max_watts
  ports: Array[PortDefinition]
  specs: Array[DeviceSpec]   ◀── capacidades opcionales; cada sistema lee las que entiende
  box_contents: Array[StringName]   (accesorios incluidos)
  scene: PackedScene

DeviceSpec (base abstracta) ─┬─ RackSpec (capacity_u, depth_mm, open/closed, service_clearance_m)
                             ├─ ComputeSpec (cores, ram_gb, ram_slots, cpu_socket, drive_bays)
                             ├─ StorageSpec (capacity_gb, interface, form_factor)
                             ├─ SwitchSpec (managed, vlan_support, l3, switching_capacity)
                             ├─ RouterSpec (wan_ports, nat, dhcp_server, firewall)
                             ├─ PoeSpec (budget_w, standard)
                             ├─ CableSpec (connector_a/b, media, category, length_m, color)
                             ├─ TransceiverSpec (form_factor, media, wavelength, reach_m)
                             ├─ PowerDistributionSpec (outlets, capacity_w)  ← regleta / PDU
                             ├─ UpsSpec (capacity_va, battery_wh)
                             └─ HostSpec (os_image, default_hostname)        ← tiene SO simulado
```

**Ventajas:**
- Una categoría nueva es un archivo de datos.
- Una capacidad nueva es una `DeviceSpec` nueva que solo lee su sistema.
- Las compatibilidades (socket de CPU, tipo de RAM, conector de cable) se comprueban con reglas sobre las specs.

**Migración:** el `enum` actual se convierte en ids de categoría y `capacity_u` pasa a `RackSpec`. Solo hay un item, así que el coste es mínimo.

### 3.3. Carga del catálogo `[PROPUESTA]`

Un `CatalogRegistry`, propiedad del `SimWorld` ([ARCHITECTURE.md](ARCHITECTURE.md) §14), construye `Dictionary[StringName, HardwareDefinition]` al iniciar la partida. Debe:

1. **Rechazar con un error claro**, no en silencio, los ids duplicados o que no coincidan con el nombre del archivo.
2. **Validar** las reglas de §9 y fallar en desarrollo con `push_error`.
3. **No depender de listar directorios en un juego exportado**, porque los `.tres` aparecen como `.remap`. Opciones: un índice generado en tiempo de edición, o `ResourceLoader.list_directory` `[VERIFICADO: el método existe en Godot 4.7.2 (sonda ClassDB), 2026-11-15]`. Falta comprobar su comportamiento en un juego exportado `[POR VERIFICAR]`.

**Compatibilidad con partidas guardadas:** las partidas referencian el id.
- No se renombran ids.
- Retirar un producto es marcarlo como descatalogado, conservando su `.tres`.
- Añadir campos con valor por defecto es seguro.

## 4. Tienda (app del ordenador simulado)

- **Fuente:** el catálogo, filtrado por etapa desbloqueada y modo de juego.
- **Funciones `[CONFIRMADO]`:** categorías, buscador (nombre, marca, especificaciones), filtros (precio, categoría, puertos, velocidad, U, consumo), ficha con especificaciones, comparador, disponibilidad, compatibilidad, carrito, pago, historial y pedidos.
- **Compatibilidad en la ficha `[PROPUESTA]`:** avisos calculados sobre lo que posee el jugador, por ejemplo:
  - «Requiere un rack de al menos 600 mm de fondo»;
  - «No tienes ningún puerto SFP+»;
  - «Tu regleta tiene 1 toma libre».
- **Conexión `[PROPUESTA]`:** la tienda necesita que el PC tenga **conectividad a Internet simulada**. Si el router doméstico está desconectado, la tienda dice «Sin conexión». El simulador de red se nota desde el primer minuto.
- **Prototipo (Hito 3):** lista por categorías, ficha, carrito y pago. Buscador, filtros y comparador vienen después.

### 4.1. Implementado (2026-11-16): tienda «Rackwell & Cía.» `[CONFIRMADO: 2026-11-16]`

El usuario pidió una tienda al estilo de las grandes tiendas online: con imágenes, opiniones inventadas y descripciones más completas. Tiene identidad propia: no usa marcas reales.

- **Catálogo:**
  - tarjetas con foto, título largo, valoración con estrellas, precio, plazo de entrega y «Ya tienes N»;
  - buscador por texto y categorías (Racks, Servidores, Redes, Cables);
  - botón «Añadir a la cesta».
- **Ficha del producto:**
  - galería de dos fotos;
  - «Acerca de este producto»;
  - caja de compra con notas de compatibilidad calculadas con lo que tiene el jugador (unidades libres en el rack, tomas libres en la regleta, puertos RJ45 libres);
  - **Especificaciones**, generadas desde la `HardwareDefinition` (`game/computer/shop_specs.gd`), incluidos el consumo, el arranque, el sistema, los ingresos en línea y el precio de reventa;
  - «En la caja», generado desde `box_contents`;
  - descripción;
  - opiniones de clientes, con el reparto por estrellas.
- **Cesta:** cantidades «−» y «+», total, saldo antes y después, y «Tramitar pedido».
- **Datos de cada ficha:** `data/shop/<id>.tres` (`ShopListing`) guarda el título largo, los puntos clave, la descripción y las opiniones. Son ficticias, sin cifras técnicas propias. La valoración es la media de las opiniones listadas. `Catalog.validate()` exige una ficha por producto a la venta.
- **Fotos:**
  - renders de los propios modelos del juego (`tools\capture_shop_photos.ps1` → `assets/shop/<id>_1.png` y `_2.png`);
  - los cables, que no tienen modelo, salen como una bobina con el mismo tubo y color que en la habitación y con sus conectores.

## 5. Pedidos, entregas e inventario

### 5.1. Estado del pedido `[PROPUESTA]`

```
PAGADO → PREPARANDO → ENVIADO → ENTREGADO (paquete en el punto de entrega) → ABIERTO
```

- **Duraciones** en tiempo de juego por clase de envío (estándar, urgente), aceleradas o saltables ([ARCHITECTURE.md](ARCHITECTURE.md) §8).
- **Pago:** descuenta el dinero al instante. Sin saldo suficiente, no se puede pagar.
- **Notificaciones:** un correo o aviso en el escritorio simulado con el estado del pedido.
- **Automatización (Etapa 3+):** recepción automática o «técnico de almacén» que desembala y almacena.

### 5.2. Instancias e inventario `[PROPUESTA]`

- Cada unidad comprada es una **instancia** con id único (y número de serie visible) **desde el momento del pago**. Así el paquete contiene ids concretos y el guardado es trivial.
- **Ubicaciones posibles de una instancia:**
  - `in_package(pedido)`;
  - `inventory`;
  - `placed(sitio, posición, rotación)`;
  - `mounted(rack, u)`;
  - `installed(equipo anfitrión, ranura)`, para componentes (Etapa 2);
  - `connected` (cables, con sus dos extremos).
- **Inventario:** lista de instancias en la ubicación `inventory`. En el prototipo no hay límite de capacidad; el almacenamiento físico y el peso son una posible mejora futura.

## 6. Montaje en rack (reglas de simulación)

**Unidades** `[POR VERIFICAR]`, valores habituales a confirmar con EIA-310 antes del Hito 4:
- 1U = 44,45 mm;
- ancho de panel de 19" = 482,6 mm;
- apertura entre rieles ≈ 450 mm;
- numeración U1 abajo.

**Reglas:**

| Regla | Detalle |
|---|---|
| Ocupación | Un equipo de altura *h* ocupa U[*u*, *u+h−1*], sin solapes |
| Cabida | *u+h−1* ≤ `capacity_u` |
| Profundidad | Fondo del equipo ≤ fondo útil del rack; si no cabe, se rechaza con el motivo |
| Montaje frontal/trasero | Por equipo; algunos (PDU verticales «0U») no ocupan unidades |
| Desmontaje | Solo con el equipo apagado o aceptando un apagado forzado; los cables se desconectan o se impide la acción |
| Alimentación | Montar no alimenta: hace falta un cable de alimentación a una toma ([NETWORK_SIMULATION.md](NETWORK_SIMULATION.md) §3) |
| Etapa 2+ | Peso máximo del rack, paneles ciegos y flujo de aire, organización de cables |

## 7. Catálogo del primer prototipo `[PROPUESTA]`

El usuario pide comprar **un switch, un rack y un servidor**, con un catálogo pequeño y sin dispositivos decorativos. Propuesta mínima:

| Item | Propiedad | Notas |
|---|---|---|
| PC antiguo (con monitor) | Inicial | Host simulado con escritorio y terminal; 1 puerto RJ45 de 1 Gbps |
| Router doméstico | Inicial | 4 puertos LAN + 1 WAN; servidor DHCP mínimo (ver ROADMAP §5); salida a Internet simulada |
| Regleta de 4 tomas | Inicial | Alimentación de los equipos |
| Cable RJ45 de 2 m | Inicial | PC → router, ya conectado |
| Rack de suelo pequeño (≈ 12U) | Comprable | Cabe en una habitación |
| Switch 1U de 16 puertos 1 Gbps, no gestionable | Comprable | Incluye cable de alimentación y orejas de rack |
| Servidor 1U de entrada | Comprable | Host simulado; 2 puertos RJ45; incluye cable de alimentación |
| Cables RJ45 Cat6 de 1 m / 3 m / 5 m | Comprables | Para el cableado del prototipo |

Precios y dinero inicial: se equilibran en el Hito 7 ([PROGRESSION.md](PROGRESSION.md)).

## 8. Marcas y nombres

Productos **ficticios** `[CONFIRMADO]`.

Marcas ficticias propuestas `[PROPUESTA]`:

| Marca | Línea de productos |
|---|---|
| Rackwell | Racks, PDU y accesorios |
| Nodex | Servidores y NAS |
| Linkara | Equipos de red |
| Cablecraft | Cables y transceptores |
| Voltara | UPS y energía |

Formato del nombre visible: `"<Marca> <Modelo> (<descripción corta>)"`.

## 9. Validaciones automáticas del catálogo

- `id` no vacío, único, igual al nombre del archivo y en snake_case.
- `price > 0`, salvo en items iniciales no comprables.
- Potencia en reposo ≤ potencia máxima.
- Un rack tiene capacidad > 0. Un equipo montable tiene altura ≥ 1.
- Grupos de puertos: `count ≥ 1`, id único dentro del item, velocidad > 0 salvo en energía.
- Tipo y velocidad coherentes: `SFP_PLUS` implica 10 000 Mbps.
- PoE solo en RJ45.
- Toda escena de dispositivo tiene tantas tomas `PortSocket` como puertos declara el catálogo (prueba de escena).
- Toda categoría referenciada existe y todo item de `box_contents` existe.

## 10. Datos de referencia

Las cifras técnicas de referencia (alcances por categoría de cable, potencias PoE, consumos típicos, dimensiones de rack) están en el índice de [TECH_RESEARCH.md](TECH_RESEARCH.md) con su estado de verificación. **No se usan para reglas del simulador hasta estar `[VERIFICADO]`.**
