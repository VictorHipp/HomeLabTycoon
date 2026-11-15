# INTERACTION_SYSTEM — Interacción con objetos

> **Estado:** diseño; nada implementado. Requisitos `[CONFIRMADO]` (documento maestro §2.2, §2.3, §7–9). Solución `[PROPUESTA]`. Cámara y transiciones en [CAMERA_SYSTEM.md](CAMERA_SYSTEM.md); reglas técnicas de cables y enlaces en [NETWORK_SIMULATION.md](NETWORK_SIMULATION.md).

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

## 8. Colocación de objetos (Hito 3) `[PROPUESTA]`

- **Activación:** desde el inventario («Colocar») o desde un objeto ya colocado («Mover»).
- **Fantasma** del objeto, verde si es válido y rojo si no, que sigue al ratón sobre el suelo o el mueble.
- **Ajuste a rejilla** de 0,1 m (`Alt` = libre) y giro en pasos de 90° con la rueda o `R`.
- **Validación en dos niveles:**
  1. visual inmediata, por solape de formas de colisión con `ShapeCast3D`;
  2. definitiva, con el comando `PlaceObject` validado por la simulación (espacio, superficie adecuada: un rack va en el suelo y un switch de sobremesa en un mueble).
- **Al confirmar:** se actualiza la navegación ([CAMERA_SYSTEM.md](CAMERA_SYSTEM.md) §4). Si el objeto deja una zona inaccesible, se avisa.

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
8. **Longitud:** se calcula a lo largo del recorrido, con distancia entre tomas × factor de recorrido (≈ 1,2) más holgura. Si el cable no llega, se rechaza con el motivo y la longitud necesaria. Bandejas y guías vendrán después.

**Representación visual `[SPIKE]` S4:**
- Cada cable es una malla de tubo generada a partir de una `Curve3D` con caída (catenaria aproximada), con pocos lados (6) y segmentos según la longitud.
- Color por tipo ([ART_STYLE.md](ART_STYLE.md) §4).
- En vista general muchos cables se simplifican.
- Clases necesarias, presentes en 4.7.2: `Curve3D` (`sample_baked`, `get_baked_length`) y `SurfaceTool` / `ImmediateMesh`.
- El spike mide el coste con 50 y 200 cables.

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
