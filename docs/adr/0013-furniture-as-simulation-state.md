# ADR 0013 — Los muebles son estado de la simulación y el jugador los reorganiza

- **Estado:** **aceptada** (pedida por el usuario el 2026-11-16).
- **Fecha:** 2026-11-16

## Contexto

Hasta ahora la habitación era fija:
- `RoomView` colocaba los muebles desde una lista en el código;
- la simulación solo conocía los rectángulos de suelo y de cable, escritos a mano en `BedroomScenario`;
- el monitor y el teclado estaban en posiciones fijas de `GameSession`;
- el PC, la regleta y el router tenían la ubicación `fixed`.

El usuario pidió poder reorganizar el cuarto, es decir, mover la cama, la mesa con el PC, el router, la alfombra y la mesilla a su gusto, y que el manual lo explique.

## Decisión

1. **Los muebles se definen en datos:** `FurnitureDefinition`, en `data/furniture/`. Cada uno guarda el suelo que ocupa, lo que estorba a los cables, su contorno, su tablero con las zonas ya ocupadas, el modelo y las piezas que lo acompañan (silla, monitor, teclado). Todo está en coordenadas locales y gira en pasos de 90°. Se cumple así la regla de datos fuera del código.
2. **Los muebles son estado de la simulación:**
   - `SimWorld.furniture` guarda su sitio y su giro;
   - `obstacles` y `cable_obstacles` se recalculan a partir de ellos;
   - la vista solo los dibuja y obedece a la simulación (regla 1).
3. **Lo que va con un mueble se mueve con él:**
   - `SimDevice.furniture_id` dice con qué mueble va cada equipo;
   - el escritorio se lleva el PC y la regleta, y la mesilla, el router que tiene encima;
   - los cables siguen enchufados: se vuelven a tender en el sitio nuevo o el sitio se rechaza con el motivo, igual que al mover el rack.
4. **Router:** se coloca sobre un tablero (`top_problem`, `place_on_furniture`). Al cambiar de tablero, pasa a ir con ese mueble.
5. **Guardado v3:** añade la distribución. Las partidas anteriores cargan con la distribución inicial.

## Alternativas descartadas

- **Mover solo la vista:** la simulación seguiría con rectángulos viejos, así que los cables y la colocación del rack mentirían. Incumple la regla de honestidad.
- **Soltar los cables al mover:** el jugador perdería la red de casa sin avisar. Rechazar con el motivo es coherente con el rack y deja que el jugador desenchufe antes si quiere.

## Consecuencias

- **Coste de la comprobación:** comprobar un sitio vuelve a calcular la ruta de todos los cables, menos de 1 ms por sitio en esta habitación. La vista previa solo la repite cuando cambia el sitio o el giro.
- **Ninguna prueba se ha relajado:** la distribución inicial reproduce las medidas anteriores, así que las pruebas y los escenarios antiguos siguen valiendo.
- **Cables junto a una pared:** al girar el PC contra la pared apareció un cruce entre las bajadas de dos de sus cables. El dibujo de los cables ahora lo detecta en planta y, en ese caso, baja cada cable más alto un carril más afuera.
- **Pendiente:**
  - no se pueden comprar ni recoger muebles;
  - los equipos de casa no van al inventario;
  - las salas futuras se definirán con estas mismas piezas de datos.
