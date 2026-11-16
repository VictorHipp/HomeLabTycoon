# ADR 0011 — Cableado guiado, cancelación al cambiar de tarea y recorridos ordenados

- **Estado:** **aceptada** (pedida por el usuario el 2026-11-16). Precisa la decisión 12 de `docs/ROADMAP.md` §5.
- **Fecha:** 2026-11-16

## Contexto

La decisión 12 confirmó el **cable con extremo pendiente**: se conecta un extremo, se va al otro equipo y se conecta el segundo.

El usuario pidió (2026-11-16):
- que, al tender un cable, el juego diga qué buscar: una toma de corriente, una entrada de un switch u otra equivalente;
- que, tras elegir la primera toma, indique en pantalla que falta la segunda;
- que el cable se cancele si el jugador deja de cablear y se pone con otra cosa, como el ordenador;
- que los cables vayan por un **camino lógico**, no por el más corto, sin chocar con nada, en esta habitación y en cualquier sala futura.

## Decisión

### Guía paso a paso (`game/interaction/cable_tool.gd`)

1. **Paso 1 de 2:** se elige un cable en el inventario. Un panel dice qué buscar, según el cable:
   - cable de red: un puerto RJ45 libre;
   - cable de corriente: una toma libre de la regleta o la entrada de alimentación de un equipo.

   En la vista general, una flecha marca cada equipo que tiene una toma compatible libre. En la vista cercana, las tomas compatibles brillan.
2. **Paso 2 de 2:** con un extremo conectado, el panel dice dónde va el otro. Las tomas compatibles brillan en verde si el cable llega y en naranja si no. Al pasar el ratón por una toma se ve la longitud necesaria.
3. **Reglas en la simulación:** las aplica `SimWorld.cable_port_problem`, `cable_reach` y `compatible_ports`, que son consultas de solo lectura. La vista solo las muestra.

### Cancelación

- **Sigue pendiente**, como pide la decisión 12, mientras el jugador camina o se acerca a otros equipos para conectar el otro extremo.
- **Se cancela** con Esc en la vista general, con el botón del panel o al empezar otra tarea:
  - sentarse al ordenador;
  - abrir la consola de un servidor;
  - colocar o mover un objeto;
  - abrir una caja;
  - montar un equipo.
- **Al cancelar** (`SimWorld.cancel_cable`), el extremo conectado se suelta y el cable vuelve al inventario. Un aviso lo explica.
- **No se cancela** al abrir el menú ni al guardar. Una partida guardada con un cable a medias lo recupera en el paso 2.

### Recorrido ordenado (`sim/cabling/cable_router.gd`)

- **Ángulos rectos:** rejilla de 2,5 cm sin diagonales, con heurística Manhattan, que da tramos largos con pocos giros. Los escalones se pliegan en un solo giro, y los quiebros de menos de 4 cm se enderezan.
- **Bordes:**
  - seguir paredes, muebles y equipos, o pasar bajo un mueble, cuesta 1;
  - el suelo libre, por donde se camina, cuesta 3;
  - el suelo libre solo se cruza cuando hace falta y por el camino más corto.
- **Holguras:**
  - 1,5 cm de cualquier obstáculo, que cubren el radio del cable dibujado y sus curvas;
  - por delante del rodapié.
- **Zonas prohibidas:** el paso de la puerta y la zona de entregas. Nada se coloca en ellas y ningún cable las cruza.
- **Si el cable no llega por el camino ordenado,** se usa el más compacto, que sigue en ángulo recto y sin chocar. Es lo que haría una persona con un cable corto.
- **Cualquier sala:** las reglas solo dependen de los datos de la sala (límites, muebles, zonas prohibidas). `tests/unit/test_cable_router.gd` lo comprueba con una sala sintética distinta.

## Consecuencias

- **Recorridos más largos:**
  - los recorridos ordenados son más largos que los tensos de antes;
  - desde algunos sitios el cable de 3 m que traen los equipos ya no llega, y hace falta el de 5 m;
  - la vista previa al colocar el rack lo avisa, redondeando hacia arriba;
  - las pruebas y el recorrido automático usan otro sitio para el rack: (0,2; 0,6), con el frente hacia la habitación.
- **Cables agrupados:** los que comparten tramo se dibujan uno junto a otro (al bajar) o uno sobre otro (en el suelo), en vez de superpuestos.
- **Limitación:** el recorrido sigue siendo 2D por el suelo, con bajadas verticales. Bandejas, canaletas y paso por paredes llegarán con salas mayores.
