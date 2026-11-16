# INTERACTION_SYSTEM — Interacción con objetos

> **Estado:** una versión simplificada está implementada en la prueba jugable de la primera misión (2026-11-15; `game/interaction/interaction_manager.gd`; lo implementado de la colocación está en §8.1 y el resumen, en [ROADMAP.md](ROADMAP.md) §1). El resto es diseño. Requisitos `[CONFIRMADO]` (documento maestro §2.2, §2.3, §7–9). Solución `[PROPUESTA]`. Cámara y transiciones en [CAMERA_SYSTEM.md](CAMERA_SYSTEM.md); reglas técnicas de cables y enlaces en [NETWORK_SIMULATION.md](NETWORK_SIMULATION.md).

## 1. Requisitos `[CONFIRMADO]`

- Seleccionar objetos con el ratón e interactuar con ordenadores, servidores y mobiliario.
- La interacción acerca la cámara a una vista detallada (rack, ordenador y, más adelante, servidores, switches, routers, paneles de parcheo, NAS, cajas, mesas de montaje, armarios técnicos y paneles de administración).
- En las vistas cercanas se usan interfaces interactivas, modelos simplificados y elementos seleccionables. **No** se animan las manos ni cada tornillo.
- **No se duplica la lógica** de cada dispositivo para sus vistas.

## 2. Conceptos `[PROPUESTA]`

| Concepto | Qué es | Dónde vive |
|---|---|---|
| `Interactable` | Componente (nodo) que hace interactuable un objeto 3D | Escena envoltorio del objeto |
| Punto de interacción | `Marker3D` `STAND_POINT`: dónde y hacia dónde se coloca el personaje | Escena del objeto (empty del modelo) |
| Ancla de cámara | `Marker3D` `CAM_<modo>` por cada vista cercana | Escena del objeto |
| Acción | Recurso `InteractionAction`: id, etiqueta (clave de traducción), modo de vista cercana y condiciones | Datos (por tipo de objeto) |
| Modo de vista cercana | Controlador genérico reutilizable: `rack`, `screen`, `box`, `inspect`, `placement` | `game/interaction/` |
| Gestor de interacciones | Máquina de estados que orquesta personaje, cámara y controlador | Escena de partida |

El `Interactable` expone: id de instancia en la simulación, acciones disponibles (que dependen del estado: no se puede «usar» un PC apagado), punto de interacción, anclas y nodos a resaltar. **No contiene lógica del dispositivo**: solo conecta el objeto 3D con el flujo de interacción.

## 3. Selección y menú de acciones `[PROPUESTA]`

- **Paso del ratón:** un rayo contra la capa de colisión «interactuables» (limitado a una vez por fotograma) resalta el objeto con un contorno o borde emisivo en el color de resaltado ([ART_STYLE.md](ART_STYLE.md) §4) y muestra una etiqueta con el nombre y el estado breve («Switch 16p — encendido»).
- **Clic izquierdo:** ejecuta la acción por defecto (PC → usar; rack → abrir; caja → abrir).
- **Clic derecho:** menú contextual con todas las acciones disponibles (Usar, Inspeccionar, Mover, Recoger, Vender…). Las no disponibles aparecen atenuadas **con el motivo** («Necesita alimentación»).
- El menú y la etiqueta funcionan también con teclado (Tab para recorrer objetos cercanos). `[PROPUESTA]` Se añade después del prototipo.

## 4. Flujo de interacción `[PROPUESTA]`

```
Idle ──acción──▶ Approach ──llega──▶ FocusIn ──transición terminada──▶ Active ──Esc/Cerrar──▶ FocusOut ──▶ Idle
                  │ clic en otro sitio                                    │ la simulación invalida
                  └──────────────▶ Idle                                  └──(p. ej. el equipo se apaga)──▶ aviso, sigue en Active
```

1. **Approach:** el personaje navega al punto de interacción. Si no puede llegar (por ejemplo, un objeto bloquea el paso), se cancela con aviso.
2. **FocusIn:** el director de cámara hace la transición al ancla del modo elegido.
3. **Active:** se instancia el **controlador del modo**, que recibe la entrada. Lee el estado de la simulación y envía **comandos**; no modifica nada por su cuenta.
4. **FocusOut:** se destruye el controlador y la cámara vuelve a la pose guardada.

## 5. Vista cercana del rack

Mecanismo en el Hito 2; funcionalidad completa en el Hito 4.

- **Unidades U:** el controlador genera huecos interactuables a partir de `capacity_u` del rack (U1 abajo `[POR VERIFICAR: convención EIA-310]`) y coloca cada equipo montado según su U inicial y su altura. Las reglas de ocupación están en [HARDWARE_CATALOG.md](HARDWARE_CATALOG.md) §6.
- **Montar:** el panel lateral muestra los equipos montables del inventario. Al elegir uno se resaltan los huecos donde cabe, y con clic se envía `MountInRack(rack, device, u)`. Si la simulación lo rechaza, se muestra el motivo («No hay 2U libres seguidas»).
- **Desmontar:** el equipo vuelve al inventario. Antes avisa si tiene cables conectados: se desconectan o se cancela.
- **Frontal ↔ trasera:** cambio de ancla. Los puertos de cada equipo están donde los tiene el modelo (switch delante; servidor con red y alimentación detrás).
- **Equipos:** el botón de encendido es un elemento seleccionable. Los LED reflejan el estado simulado ([NETWORK_SIMULATION.md](NETWORK_SIMULATION.md) §9).
- **Consola local:** `[PROPUESTA]` En un servidor se puede abrir su consola, como si se conectaran monitor y teclado (o una consola de rack), para usar la terminal sin red. Es la vía del prototipo para configurar la IP del servidor.

## 6. Vista cercana de pantalla (ordenador) `[PROPUESTA]` `[SPIKE]` S2

**Objetivo:**
- La pantalla del ordenador muestra la interfaz del escritorio simulado **dentro del mundo**.
- Al interactuar, esa pantalla pasa a ocupar la vista principal y se usa con ratón y teclado.
- El texto debe ser perfectamente legible.

**Diseño propuesto** (por validar en el spike):

1. La interfaz del escritorio simulado (tienda, terminal…) es un árbol de `Control` dentro de un `SubViewport` con la resolución de la pantalla virtual (p. ej. 1280×800).
2. **En vista general:** el material del monitor usa la `ViewportTexture` de ese `SubViewport`. Para no gastar rendimiento, se actualiza a baja frecuencia o solo cuando cambia.
3. **Al terminar la transición:** se muestra un `SubViewportContainer` a pantalla completa que contiene ese mismo `SubViewport`, con un fundido corto sobre la imagen del monitor. El contenedor reenvía la entrada al `SubViewport`.
4. **Al salir:** se oculta el contenedor y el monitor vuelve a mostrar la textura.

**Datos de la documentación oficial** `[VERIFICADO: docs.godotengine.org «Using Viewports», 2026-11-15]`:
- un `SubViewport` solo recibe entrada de un `SubViewportContainer` **padre directo**;
- en el modo por defecto solo se redibuja si su textura se dibuja y es visible;
- los modos de actualización son `Never`, `Once`, `Always` y `When Parent Visible`.

**Pendiente de comprobar en el spike:**
- un mismo `SubViewport` sirve a la vez de textura del monitor y de hijo del contenedor;
- la textura se actualiza con el contenedor oculto (modo `Always`);
- la entrada llega correctamente;
- el texto es nítido.

**Alternativa:** reenviar la entrada con `Viewport.push_input` (existe en 4.7.2) en lugar de usar el contenedor.

## 7. Cajas y desembalaje (Hito 3) `[PROPUESTA]`

- Los paquetes entregados aparecen en el **punto de entrega** de la casa, como objetos interactuables.
- **Abrir:** vista cercana de la caja, apertura animada breve (≤ 1,5 s) y vista del contenido (equipo y accesorios incluidos, p. ej. cable de alimentación y orejas de rack).
- **Recoger:** los objetos pasan al inventario. La caja vacía se puede retirar.
- **Repetición sin fatiga:** la animación completa solo la primera vez por tipo de producto. Después es más rápida, y existe «abrir todo» `[CONFIRMADO: no repetir animaciones largas]`. En etapas avanzadas, la recepción se automatiza.

### 7.1. Implementado (2026-11-15): zona de entregas

- **Zona reservada:** un rectángulo de 0,60 × 0,50 m junto a la puerta (`BedroomScenario.DELIVERY_ZONE`), marcado en el suelo con «ENTREGAS» y libre del paso y del giro de la puerta.
- **Qué impide la reserva:** colocar algo encima, que la zona de trabajo de un rack la pise y que la crucen cables.
- **Una sola pila:** todas las cajas que esperan, de cualquier pedido, van en la misma pila. Se dibujan hasta tres y un contador «×N» indica las reales.
- **Contenido:** cada caja conserva el suyo en la simulación.
- **Abrir:** un clic en la pila abre la de arriba; el contador baja y, sin cajas, la pila desaparece. La apertura animada y «abrir todo» siguen pendientes.
- **Partida antigua con la zona ocupada:** al cargar no se borra nada. La pila se pone en el sitio libre más cercano y un mensaje lo indica (`SimWorld.delivery_spot`).
- **Si llega un pedido con el personaje encima de la zona:** el personaje se aparta al suelo transitable más cercano.
- **Comprobado** en `tests/integration/test_deliveries.gd` y en el recorrido: varios pedidos seguidos en `wall` y el contador en cada caja.

## 8. Colocación de objetos (Hito 3) `[PROPUESTA]`

- **Activación:** desde el inventario («Colocar») o desde un objeto ya colocado («Mover»).
- **Fantasma** del objeto, verde si es válido y rojo si no, que sigue al ratón sobre el suelo o el mueble.
- **Ajuste a rejilla** de 0,1 m (`Alt` = libre) y giro en pasos de 90° con la rueda o `R`.
- **Validación en dos niveles:**
  1. visual inmediata, por solape de formas de colisión con `ShapeCast3D`;
  2. definitiva, con el comando `PlaceObject` validado por la simulación (espacio, superficie adecuada: un rack va en el suelo y un switch de sobremesa en un mueble).
- **Al confirmar:** se actualiza la navegación ([CAMERA_SYSTEM.md](CAMERA_SYSTEM.md) §4). Si el objeto deja una zona inaccesible, se avisa.

### 8.1. Implementado en la prueba jugable (2026-11-15)

**Fantasma:** rejilla de 0,05 m y giro de 90° con `R`. La vista previa usa las mismas reglas que la simulación (`SimWorld.placement_problem`), no un `ShapeCast3D`, e indica por qué no cabe. Regla de presentación añadida: no se puede soltar encima del personaje.

**Espacio de trabajo del rack** `[PROPUESTA]` (implementada; puedes vetarla):
- **Regla:** 50 cm libres delante y detrás del rack (`RackSpec.service_clearance_m`), dentro de la habitación y sin muebles ni equipos.
- **Motivo:**
  - el jugador necesita llegar al frontal para montar;
  - la cámara necesita sitio detrás para cablear.

  Antes de esta regla, un rack contra la pared dejaba la trasera inaccesible y la misión no se podía terminar.
- **Indicación en el suelo:** al colocar, el suelo marca las dos zonas. La clara es el frente.
- **Protección de las zonas:** nada puede colocarse después dentro de ellas.
- **Rechazo:** si no cabe, el mensaje lo explica («Deja al menos 50 cm libres delante y detrás…»). Al girarlo 90° suele caber.

**Aviso de alcance:** si los equipos del rack necesitarían un cable de corriente más largo que el más largo del catálogo, la vista previa lo avisa. Usa la misma regla de longitud que `connect_cable`. Es un aviso: no impide colocarlo.

**Mover y recoger** (salidas de un mal sitio):
- **Mover:**
  - con clic derecho sobre un rack colocado, en la vista general. No hace falta caminar hasta él, así que un rack que cierra el paso siempre se puede mover;
  - o con el botón «Mover rack» del panel del rack.

  Se mueve con lo que tenga montado y **con sus cables**: la simulación los vuelve a tender en el sitio nuevo. Si alguno ya no tuviera recorrido o no llegara, el sitio se rechaza con el nombre del cable y los metros (§9). También existe el botón «Desconectar todos los cables».
- **Colocar algo sobre un cable tendido:** el cable se vuelve a tender rodeándolo. Si no puede, se rechaza el sitio con el motivo.
- **Fantasma:** se tiñe de verde o de rojo además del mensaje, y el clic en un sitio rojo no hace nada.
- **Recoger:** botón «Recoger rack». Solo si está vacío y sin cables; vuelve al inventario.
- **Inaccesible:** si el rack deja algo fuera de alcance, no se avisa al colocarlo (pendiente). Al intentar ir allí, el personaje responde: «No puedo llegar ahí. Si el rack cierra el paso, muévelo con clic derecho sobre él».

**Clic derecho:** en la prueba, el clic derecho sin arrastre sobre un rack lo mueve directamente, sin menú contextual (§3). El arrastre con el botón derecho sigue girando la cámara.

**Comprobado** en `tests/integration/test_rack_placement.gd` y en los 4 escenarios de `tools\walkthrough.ps1` ([TEST_PLAN.md](TEST_PLAN.md)).

### 8.2. Implementado (2026-11-16): reorganizar la habitación `[CONFIRMADO: 2026-11-16, ADR 0013]`

El usuario pidió poder colocar a su gusto la cama, el escritorio con el PC, el router, la alfombra y la mesilla, y que el manual lo explique.

- **Los muebles son estado de la simulación:**
  - `SimWorld.furniture` contiene piezas `SimFurniture` (posición y giro) que vienen de `FurnitureDefinition` en `data/furniture/`;
  - cada definición tiene el suelo que ocupa, lo que estorba a un cable (patas, cajonera, base de la silla), su contorno, su tablero y los modelos que la muestran;
  - `obstacles` y `cable_obstacles` se recalculan a partir de las piezas. La distribución inicial reproduce exactamente las medidas anteriores (`tests/integration/test_furniture.gd`).
- **Cómo se mueve:**
  - clic derecho sin arrastre sobre la pieza en la vista general, como el rack. La alfombra se coge desde cualquier punto de ella;
  - `R` gira 90° y el fantasma se tiñe de verde o de rojo, con el motivo escrito abajo.
- **Lo que va con cada pieza (`SimDevice.furniture_id`):**
  - el escritorio se lleva la silla, el monitor, el teclado, la torre del PC y la regleta. Un clic derecho en el PC o en el monitor mueve el escritorio;
  - la mesilla se lleva el router que tiene encima.
- **Router:** va de un tablero a otro, sobre la mesilla o el escritorio. No puede ir donde están el monitor y el teclado (`top_reserved`). Las reglas están en `SimWorld.top_problem` y `place_on_furniture`.
- **Reglas al dejar una pieza (`SimWorld.furniture_problem`):**
  - dentro de la habitación;
  - sin chocar con otro mueble, un equipo o un paquete;
  - sin tapar la puerta, la zona de entregas ni el espacio de trabajo del rack;
  - lo que lleva también debe caber;
  - sin el personaje en medio;
  - cada cable enchufado se vuelve a tender y debe tener paso y longitud. Si no, se rechaza diciendo qué cable falla.

  La alfombra no ocupa suelo: puede ir debajo de otros muebles.
- **Después de mover:**
  - la navegación se vuelve a hornear;
  - la silla mira a su escritorio en cualquier giro;
  - para usar un equipo, el personaje busca un sitio alcanzable a su alrededor, empezando por el lado de sus tomas.
- **Guardado v3:** guarda la distribución. Las partidas v1 y v2 cargan con la distribución inicial.
- **Comprobado:**
  - `tests/integration/test_furniture.gd`, incluida una partida con la misión terminada (rack, zonas de trabajo y cables a la regleta que viaja con el escritorio);
  - escenario `furniture` de `tools\walkthrough.ps1`, que mueve las cinco cosas con clics reales, con un rechazo de la cama y otro del router. Después usa el PC (ping al router), abre de cerca el router en el escritorio, desenchufa su cable de corriente con clic derecho, lo vuelve a tender hasta la regleta y guarda y carga. Comprueba también que nada atraviesa nada y que ningún cable atraviesa otro;
  - un barrido en la simulación (script temporal, no está en el repositorio): con los cables de casa, el escritorio cabe en 621 combinaciones de sitio y giro (rejilla de 10 cm × 4 giros), la mesilla en 1019 y la cama solo en 66. Lo que más limita es el tamaño de la habitación y de la cama.
- **Límites:**
  - cambiar dos piezas grandes de sitio exige pasos intermedios, porque no hay almacén temporal;
  - cuando dos cables salen de la misma cara en direcciones distintas y uno podría atravesar al otro al bajar, el más alto baja un carril y medio más afuera. Eso no comprueba el hueco que hay detrás del equipo: solo está verificado en la distribución inicial y en la del recorrido;
  - no se ha probado la vista cercana de la torre del PC con su trasera contra la pared.

## 9. UX del cableado (Hito 4) `[PROPUESTA]`

Las reglas (compatibilidad, longitud, velocidad, estado del enlace) son de la simulación ([NETWORK_SIMULATION.md](NETWORK_SIMULATION.md) §4–5). Aquí solo se describe la experiencia.

1. **Elegir cable:** desde el inventario o el panel de la vista cercana (tipo y longitud visibles).
2. **Puertos:** se iluminan los **compatibles**. Los incompatibles se atenúan con el motivo («Este cable es RJ45; el puerto es una jaula SFP+»).
3. **Primer extremo:** clic en un puerto. La simulación registra el extremo A conectado y el B **libre**.
4. **Previsualización:** el extremo libre sigue al cursor con una curva colgante.
5. **Segundo extremo:**
   - si el destino está en la misma vista (mismo rack), clic en el puerto destino;
   - si está en otro equipo, el jugador sale (el cable queda colgando con el extremo libre, como en la realidad), se acerca al otro equipo y conecta el extremo B.
6. **Resultado:** `ConnectCable` devuelve el estado. El LED del puerto y el panel de estado del enlace se actualizan («Enlace: 1 Gbps» o «Sin enlace: el otro equipo no tiene alimentación»).
7. **Desconectar:** clic en el conector → «Desconectar» (o arrastrarlo a otro puerto). Los cables se pueden retirar al inventario.
8. **Longitud:** se calcula a lo largo del recorrido real (§9.1). Si el cable no llega, se rechaza con el motivo y la longitud necesaria. Bandejas y guías vendrán después.

### 9.1. Implementado (2026-11-15): recorrido por el suelo

**Dónde se calcula:** en la simulación, en `sim/cabling/cable_router.gd` y `SimWorld.route_between`. La vista solo lo dibuja (`game/cabling/cable_renderer.gd`).

**Cada extremo:**
- sale de la toma por la cara que indican los datos (`PortDefinition.face`: `front`, `rear` o `top`, contrastada con los marcadores de los modelos);
- baja al suelo junto a su equipo;
- en un rack, baja por el poste de esa cara más cercano al destino;
- un equipo sobre un mueble, como el router, lleva el cable por encima hasta el borde y lo baja por delante.

**Por el suelo** `[CONFIRMADO: 2026-11-16, ADR 0011]`, no el camino más corto sino uno ordenado, como lo tendería una persona:
- **Tramos rectos en ángulo recto.** Usa una rejilla de 2,5 cm sin diagonales (`AStarGrid2D` de Godot, heurística Manhattan). Los escalones se pliegan en un solo giro y los quiebros de menos de 4 cm se enderezan.
- **Por los bordes:**
  - pegado a paredes, muebles y equipos, o bajo un mueble, cuesta 1;
  - el suelo libre por donde se camina cuesta 3 `[PROPUESTA: cifra]`;
  - el suelo libre solo se cruza cuando hace falta y por el tramo más corto.
- **Holgura de 1,5 cm** con todo: la cama, las patas y la cajonera del escritorio, el mueble del router, la base de la silla y los equipos de suelo. Cubre el radio del cable dibujado y sus curvas. El cable va por delante del rodapié y pasa bajo el escritorio, entre sus patas.
- **Zonas prohibidas:** la zona de entregas y el paso de la puerta (`BedroomScenario.DOOR_ZONE`). Tampoco se puede colocar nada en el paso de la puerta.
- **Si el cable no llega por el camino ordenado,** se usa el más compacto, que sigue en ángulo recto y sin chocar.
- **Cualquier sala:** las reglas dependen solo de los datos de la sala (límites, rodapié, muebles, zonas prohibidas). Se prueba con una sala sintética en `tests/unit/test_cable_router.gd`.
- **Cables que comparten tramo** (`game/cabling/cable_renderer.gd`) nunca se dibujan uno dentro de otro:
  - en el suelo, el que llega después se apoya encima del otro y no baja hasta haberse separado 3 cm;
  - si varios bajan por el mismo sitio y se van en sentidos opuestos, cada uno baja medio carril hacia su lado;
  - si se van en el mismo sentido, bajan en carriles paralelos (2 cm) y siguen así hasta la primera curva;
  - tras un tramo largo sobre un mueble (el router en su mueble), cada cable baja delante de su propia toma;
  - en la regleta, el que pasa por encima de otras tomas ocupadas va un carril más alto;
  - hacia un poste del rack, el cable sale un carril más lejos del frontal, por delante de los latiguillos.

**Entre dos equipos del mismo rack:**
- misma cara: el cable va por delante;
- de delante a atrás: cruza por una U libre entre ellos;
- si no hay ninguna U libre: rodea el lateral del rack.

**Longitud necesaria:** salida de la toma (4 cm) + bajada al suelo + recorrido + subida + 20 cm de holgura (10 cm dentro de un rack).

**Consecuencias:**
- **Cables iniciales:** el cable de red del PC al router y el de corriente del router son de 5 m. Se añadió `power_cord_5m` al catálogo.
- **Misión:** desde un rack en medio de la habitación, el enlace al router suele pedir el cable de 5 m. Con los recorridos ordenados (2026-11-16), los cables de corriente de 3 m que traen los equipos llegan si la trasera del rack queda hacia el escritorio y la regleta; desde la otra punta de la habitación hace falta el de 5 m, y la vista previa lo avisa (longitud redondeada hacia arriba).

**Sin recorrido:** si no existe ninguno, la conexión se rechaza y se explica.

**Dibujo:**
- Tubo con esquinas redondeadas (3 cm) y marcos sin torsión.
- Más grueso que un cable real (8–9,5 mm de radio) para que se vea en la vista general.
- Se redibuja en cada cambio (mover, desconectar, recoger, cargar).

**Comprobado:**
- un barrido de posiciones del rack por los cuatro giros: ningún cable cruza nada (`tests/integration/test_rack_placement.gd`);
- en el recorrido automático, una esfera del radio del cable recorre cada cable dibujado cada centímetro y no puede tocar ningún sólido ajeno (muebles, paredes, rodapié, otros equipos);
- en el recorrido, además, ningún equipo, el monitor, el teclado ni la pila de cajas atraviesa otro objeto (colisionadores reducidos 1 cm);
- y ningún cable atraviesa a otro: cada par de cables, muestreados cada centímetro, se mantiene a más del 75 % de la suma de sus radios (los tubos dibujados tienen 8 caras).

**Representación visual `[SPIKE]` S4:**
- Cada cable es una malla de tubo generada a partir de una `Curve3D` con caída (catenaria aproximada), con pocos lados (6) y segmentos según la longitud.
- Color por tipo ([ART_STYLE.md](ART_STYLE.md) §4).
- En vista general muchos cables se simplifican.
- Clases necesarias, presentes en 4.7.2: `Curve3D` (`sample_baked`, `get_baked_length`) y `SurfaceTool` / `ImmediateMesh`.
- El spike mide el coste con 50 y 200 cables.

### 9.2. Implementado (2026-11-16): cableado guiado `[CONFIRMADO: 2026-11-16, ADR 0011]`

- **Paso 1 de 2:** al elegir un cable en el inventario, un panel con borde turquesa dice qué buscar:
  - cable de red: un puerto RJ45 libre;
  - cable de corriente: una toma libre de la regleta o la entrada de alimentación de un equipo.

  En la vista general, una flecha flota sobre cada equipo con una toma compatible libre. En la vista cercana, esas tomas brillan.
- **Paso 2 de 2:** con un extremo conectado, el panel dice dónde va el otro. Las tomas compatibles brillan en verde si el cable llega y en naranja si no. Al pasar el ratón, se ve la longitud que haría falta.
- **Cancelar:**
  - Esc en la vista general, o el botón «Cancelar cable»;
  - también al empezar otra cosa: sentarse al ordenador, abrir la consola, colocar o mover un objeto, abrir una caja o montar un equipo.
- **Al cancelar,** el extremo conectado se suelta y el cable vuelve al inventario, con un aviso.
- **No cancelan:** caminar ni acercarse a otro equipo, porque son parte de cablear (decisión 12).
- **Reglas:** están en la simulación (`SimWorld.cable_port_problem`, `cable_reach`, `compatible_ports`, `cancel_cable`), con pruebas en `tests/integration/test_cable_guidance.gd`.

- Rodea, con 1,2 cm de margen: la cama, las patas y la cajonera del escritorio, el mueble del router, la base de la silla, los equipos de suelo y la zona de entregas. Pasa bajo el escritorio, entre sus patas.

## 10. Separación datos/vista (para no duplicar lógica)

- Cada dispositivo tiene **una** escena envoltorio con sus tomas (`PortSocket` con id de grupo e índice), LED y botón de encendido. Sirve igual en vista general que en vista cercana.
- Los **controladores de modo son genéricos**: el del rack funciona con cualquier rack y cualquier equipo montable porque lee los datos del catálogo y de la simulación.
- Añadir un dispositivo nuevo es añadir datos y una escena envoltorio, no código de interacción. Ver la lista de comprobación de §11.

## 11. Cómo añadir un objeto interactuable

1. Definición en el catálogo ([HARDWARE_CATALOG.md](HARDWARE_CATALOG.md)).
2. Modelo o greybox con los empties `STAND_POINT`, `CAM_<modo>`, `PORT_*`, `LED_*` y `POWER_IN_*`.
3. Escena envoltorio con `Interactable` y `DeviceView` (o los generados por el script de importación).
4. Acciones y modo de vista cercana en los datos del tipo de objeto.
5. Prueba de escena: carga, tiene sus puntos y anclas, y el número de tomas coincide con los puertos del catálogo ([TEST_PLAN.md](TEST_PLAN.md)).

## 12. Spikes

| Id | Pregunta | Hito |
|---|---|---|
| S2 | Pantalla del ordenador: `SubViewport` compartido entre monitor y pantalla completa, entrada y nitidez | 2 |
| S4 | Malla de cables: coste con 50/200 cables y aspecto | 4 |
| S5 | LED por uniform de instancia (`instance uniform`) en 4.7.2 | 4–5 |
