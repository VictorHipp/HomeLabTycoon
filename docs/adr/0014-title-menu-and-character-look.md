# ADR 0014 — Menú de inicio y aspecto del personaje elegido por el jugador

- **Estado:** **aceptada** (pedida por el usuario el 2026-11-16). Amplía el [ADR 0012](0012-faceted-player-character.md).
- **Fecha:** 2026-11-16

## Contexto

El juego arrancaba directamente en la habitación (`main.tscn` era la `GameSession`), y el personaje tenía un único aspecto, elegido por Claude (ADR 0012).

El usuario pidió dos cosas:
- un menú para empezar una partida nueva o cargar una;
- personalizar el personaje partiendo de la misma base: cambiar la ropa, el pelo y la barba, y elegir entre chico y chica.

## Decisión

1. **Lanzador:** `main.tscn` es ahora un `GameLauncher`.
   - Muestra el título (`TitleScreen`).
   - Entra directo en la `GameSession` si hay una partida nueva o una carga pendientes, cuando corre el recorrido automático (salvo los escenarios que empiezan en el título) o con `-- --new-game`.
   - Cargar y empezar recargan la escena, como ya hacía cargar desde el juego, así que ninguna vista conserva estado anterior.
2. **El aspecto es presentación:**
   - `CharacterAppearance` (`game/character/`) guarda una opción por ranura y se graba en la sección `session` de la partida;
   - la simulación no lo conoce.
3. **Opciones en datos:** `data/character/appearance_options.tres`. Cada opción de estilo lista los prefijos de las piezas que muestra, y una pieza se oculta si su ranura la reclama y la opción elegida no. Así, las mangas compartidas por dos prendas o los torsos que dependen del cuerpo y de la prenda funcionan sin reglas especiales.
4. **Un solo modelo con todas las piezas:** las mismas articulaciones `J_*` que antes, así que la animación de andar y sentarse no cambia. «Chica» cambia el torso, la cintura, el pecho y la cadera de cada prenda (y añade pestañas y labios), no las extremidades.
5. **Color por personaje:** las piezas personalizables usan materiales `c_*`. Se sustituyen por copias con el color elegido en cada instancia, conservando los tres tonos de las caras; el material importado no se toca.
6. **Compatibilidad:** sin aspecto guardado, o con valores desconocidos, se usa el aspecto por defecto, que es el del ADR 0012.

## Consecuencias

- **Coste:** el modelo pasa de 3598 a 7932 triángulos en el archivo, pero cada aspecto muestra entre unos 2500 y 3600. Las piezas ocultas no se dibujan.
- **Comprobación del proyecto:** `check_project.ps1` arranca la escena principal (el título) y, aparte, una partida nueva.
- **Pendiente:**
  - una sola ranura de guardado;
  - el aspecto no se cambia a mitad de partida;
  - sin expresiones faciales ni más peinados (el rig y el atlas de §6 siguen siendo `[PROPUESTA]`).
