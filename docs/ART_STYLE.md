# ART_STYLE — Dirección artística

> **Estado (2026-11-15):** *spike* visual hecho. Hay 16 modelos provisionales generados por script (§11).
> - Requisitos del usuario: `[CONFIRMADO]`.
> - Identidad concreta (nombre, paleta, cifras): **a prueba** hasta que el usuario revise la muestra (decisión 16 de [ROADMAP.md](ROADMAP.md) §5).

## 1. Requisitos `[CONFIRMADO]`

- 3D low-poly estilizado, semi-cartoon, estética indie moderna.
- Formas geométricas simplificadas y proporciones humanas algo caricaturizadas.
- Colores equilibrados, iluminación suave, materiales y texturas sencillos, sombras discretas.
- Geometría optimizada y animaciones claras.
- Ni infantil ni fotorrealista. Atractivo, profesional y **reconocible**.
- Identidad **original**: no se copian personajes ni assets de otros juegos.
- Objetos técnicamente reconocibles: los elementos que afectan a la simulación (puertos, unidades U, LED) deben identificarse con claridad aunque la carcasa sea low-poly.
- El desarrollo no se detiene por falta de modelos: hay modelos provisionales con geometría simple.

## 2. Identidad: «Taller luminoso» `[PROPUESTA]`

La idea: **un taller doméstico cálido donde la tecnología brilla**. La habitación es acogedora (madera, tonos crema y terracota) y los equipos son objetos técnicos de grises fríos con acentos de color **funcionales**: cada color significa algo.

Al progresar, la paleta pasa de lo cálido y doméstico a lo frío y ordenado: oficina, sala técnica y centro de datos. El jugador **ve** su progreso en el ambiente.

Tres rasgos de firma:
1. **Bisel generoso.** Todas las aristas exteriores llevan un chaflán visible (≈ 4–8 % del lado menor). Da un aspecto amable y técnico a la vez y capta la luz para que la forma se lea bien.
2. **Color con significado.** Los colores saturados se reservan para la información: LED, tipos de cable, estados y resaltados. El resto se mantiene contenido.
3. **Brillo interior.** Pantallas, LED y paneles emiten luz con un *glow* suave. Los equipos parecen «vivos» cuando funcionan y apagados cuando no.

## 3. Lenguaje de formas

| Familia | Formas | Intención |
|---|---|---|
| Personas | Volúmenes redondeados, cápsulas, curvas suaves; talla facetada sin bisel en el jugador ([ADR 0012](adr/0012-faceted-player-character.md)) | Cercanía, expresividad |
| Mobiliario doméstico | Blando, madera, esquinas redondeadas | Hogar, calidez |
| Equipos informáticos | Rectangulares con bisel marcado y rejillas como inserciones simples | Técnico pero amable |
| Espacios empresariales y CPD | Angulosos, repetitivos, modulares | Escala, orden, profesionalidad |

**Prueba de silueta:** cada objeto se reconoce en escala de grises y a la distancia de la vista general.

## 4. Paleta `[PROPUESTA]`

Valores sRGB de partida; se ajustarán en el spike visual (ROADMAP, Hito 1).

**Neutros**

| Nombre | Hex | Uso |
|---|---|---|
| Tinta | `#1E2430` | Detalles oscuros, fondo de paneles de interfaz |
| Grafito | `#2E3440` | Carcasas oscuras (servidores, switches) |
| Acero | `#5C6675` | Carcasas medias, rieles |
| Niebla | `#C9D1D9` | Carcasas claras, plásticos |
| Hueso | `#EFE6D8` | Paredes, texto claro de interfaz |

**Hogar (cálidos)**

| Nombre | Hex |
|---|---|
| Madera miel | `#C98F5A` |
| Terracota | `#C8654A` |
| Mostaza | `#E0B34A` |
| Salvia | `#8FAF8B` |

**Funcionales.** Su significado es reservado: no se usan como decoración.

| Significado | Hex | Notas |
|---|---|---|
| LED correcto / enlace | `#4ADE80` | |
| LED actividad / aviso | `#F5A524` | |
| LED fallo | `#EF4444` | |
| LED identificación | `#60A5FA` | |
| Resaltado de interfaz / selección | `#3CC8D8` | |
| Cable de cobre por defecto | `#3B82C4` | El color del latiguillo no está normalizado; lo usamos como código de juego |
| Fibra monomodo (OS) | `#F2D33B` | Amarillo `[VERIFICADO: TIA-598C citado en Wikipedia «Multi-mode optical fiber», 2026-11-15]` |
| Fibra multimodo OM1/OM2 | `#E07B39` | Naranja (misma fuente) |
| Fibra multimodo OM3/OM4 | `#2EC4C4` | Aguamarina (misma fuente) |
| Fibra multimodo OM5 | `#A3D63B` | Verde lima (misma fuente) |
| Cable de alimentación | `#151515` | |

**Accesibilidad:** ninguna información depende solo del color. Los LED combinan color con **patrón** (fijo, parpadeo lento, parpadeo rápido) y la interfaz usa además iconos o texto.

## 5. Materiales, iluminación y render `[PROPUESTA]`

- **Atlas de paleta:** una textura pequeña de muestras de color (p. ej. 64×64 px) compartida por la mayoría de objetos. Las UV se colocan sobre la muestra deseada. Un solo material para muchos objetos simplifica la producción y favorece el *batching*.
- **Material base:** rugosidad alta (≈ 0,8), metálico 0 (salvo rieles y rejillas, ≈ 0,5), sin mapas normales en el estilo base.
- **Materiales especiales:**
  - pantallas, con la textura de la interfaz simulada (ver [INTERACTION_SYSTEM.md](INTERACTION_SYSTEM.md) §6);
  - cristal;
  - cables, con color por tipo;
  - LED, en un shader que recibe el estado por instancia. `[SPIKE]` Verificar `instance uniform` en 4.7.2 para no crear un material por LED.
- **Iluminación de la habitación:**
  - una luz direccional (sol por la ventana) con sombras suaves y poco contrastadas;
  - luces puntuales cálidas;
  - luz ambiental del entorno;
  - SSAO sutil;
  - *glow* para emisivos.
- **Sin GI costosa al principio:** ni SDFGI ni VoxelGI. Más adelante se puede valorar LightmapGI para el armazón estático de cada sala, porque los objetos del jugador cambian.
- **Mapa de tonos neutro:** sin colores quemados. Se elige en el spike visual.

## 6. Personajes `[PROPUESTA]`

- **Proporciones:** ≈ 6 cabezas de altura (estilizado frente a las ≈ 7,5 reales), cabeza algo mayor, manos simplificadas sin dedos individuales detallados y pies algo grandes para dar estabilidad.
- **Rostro:** ojos, cejas y boca como formas simples en textura (atlas de expresiones). Las expresiones cambian sin rig facial. Nariz mínima.
- **Ropa y pelo:** volúmenes grandes con pliegues sugeridos por la forma, no por textura. Pelo y barba como masas talladas con silueta reconocible.
- **Accesorios** (gafas, gorras, auriculares, barbas): piezas que se acoplan a huesos para permitir personalización modular.
- **Rig** humanoide estándar, compatible con el reasignador de esqueletos de Godot (`SkeletonProfileHumanoid`), para compartir animaciones entre personajes. `[POR VERIFICAR]` El flujo exacto de *retargeting* en 4.7.2.
- **Animaciones mínimas del prototipo:** reposo, caminar, interactuar de pie (rack), sentarse y teclear (PC), agacharse y abrir caja, llevar caja.
- **Presupuesto:** jugador 4–6 k triángulos; NPC 3–5 k.

### 6.1 Personaje del jugador provisional `[CONFIRMADO: 2026-11-16, modelado facetado pedido por el usuario]`

Decisión registrada en [ADR 0012](adr/0012-faceted-player-character.md).

El usuario pidió (2026-11-16) más modelado en el personaje, con el nivel de talla de una imagen de referencia facetada, pero con ropa y estilo del juego. Solo está confirmado ese **modelado facetado**. El rig estándar, el atlas de expresiones y los accesorios modulares de §6 siguen siendo `[PROPUESTA]`.

- **Modelo:** `character_player` (`assets/models/characters/`), generado por `build_character_player` en `tools/blender/build_prototype_models.py`. Sustituye al maniquí en el juego (`PlayerCharacter.MODEL`).
- **Aspecto:** cacharrero de homelab con sobrecamisa salvia abierta (cuello y puños más oscuros, bolsillo), camiseta hueso con un estampado de terminal, vaqueros apagados con el bajo vuelto, cinturón, zapatillas, gafas, barba corta y pelo tallado en mechones.
- **Cómo se talla:**
  - secciones de 8–16 lados a varias alturas, estrechadas y con algo de ruido fijo;
  - prendas abiertas con grosor real;
  - piezas convexas para nariz, orejas, manos y mechones;
  - caras planas trianguladas, sin bisel;
  - cada triángulo con uno de **tres tonos** de su color (100 %, 87 % y 109 %). Las caras se leen por el tono, como en la referencia. Las semillas son fijas, así que el `.glb` es reproducible.
- **Colores nuevos de atrezo:** salvia oscura, vaquero, vaquero claro, cuero y castaño. No se usa ningún color funcional (LED, cables, resaltado).
- **Mismas articulaciones que el maniquí:** `J_hip`, `J_knee`, `J_ankle`, `J_shoulder` y `J_elbow` (`_L` y `_R`), a las mismas alturas, para que `CharacterAnimator` y sus pruebas sigan valiendo. Cada pieza es rígida y cuelga de su articulación; rodillas y codos llevan una esfera de relleno para que no se abra un hueco al doblarse.
- **La ropa sigue a las piezas rígidas:** la chaqueta acaba en la cadera y no hay nada largo, porque al sentarse los muslos giran 88°.
- **Presupuesto:** 3598 triángulos, 76 piezas y 33 materiales.
- **Comprobado:**
  - en el juego: vista general de pie, andando y sentado (recorrido automático y capturas del manual);
  - en una escena de prueba aparte: de pie, a media zancada y sentado. El antebrazo queda unos 5 cm por encima de la mesa (puño a ≈ 0,80 m, tablero a 0,75 m).
  - Al sentarse, los muslos se hunden un poco en el asiento, igual que con el maniquí; desde la cámara del juego no se ve.

## 7. Objetos y dispositivos

**Reglas de legibilidad técnica:**
1. Las **dimensiones con efecto en la simulación** son reales: unidades U, anchos de rack y separación de los grupos de puertos. Ver [HARDWARE_CATALOG.md](HARDWARE_CATALOG.md) §6.
2. Los **elementos de lectura** (LED, etiquetas, botones de encendido, asas) pueden ampliarse hasta **1,5×** para verse bien en vista cercana.
3. **Cada tipo de conector tiene una forma propia y constante:** RJ45 (rectangular con muesca), jaula SFP (ranura estrecha), entrada de alimentación IEC (trapecio), USB, consola. El jugador aprende a reconocerlos.
4. Los **puertos llevan número** (etiqueta 3D o calcomanía) visible solo en vista cercana.
5. Un switch de 24 puertos **tiene 24 puertos modelados** e interactuables.

**Presupuestos orientativos** `[PROPUESTA]` (triángulos):

| Objeto | Presupuesto |
|---|---|
| Rack (vacío) | 1–2 k |
| Equipo 1U | 300–800 |
| PC con monitor | 1–2 k |
| Mueble | 200–1 k |
| Atrezo pequeño | 50–300 |
| Habitación de la Etapa 1, visible a la vez | < 150 k |

En centros de datos (Etapa 6) se usarán instancias (`MultiMesh`) y niveles de detalle para filas de racks.

## 8. Flujo Blender → Godot `[PROPUESTA]`

Herramienta: Blender 5.3.0, ya instalado (ver [DEVELOPMENT_WORKFLOW.md](DEVELOPMENT_WORKFLOW.md)).

1. **Unidades:** métricas, 1 unidad = 1 m. Blender trabaja con Z hacia arriba. El exportador glTF convierte a Y hacia arriba con `export_yup=True` `[VERIFICADO: Blender 5.3 → Godot 4.7.2, tests/check_models.gd, 2026-11-15]`.
2. **Origen del objeto:**
   - objetos de suelo: centro inferior;
   - equipos de rack: centro inferior del plano frontal de montaje, para que encajen por unidad U. Medidas `[VERIFICADO: EIA-310-D citada en Wikipedia «19-inch rack», 2026-11-15]`: 1U = 44,45 mm, panel de 482,6 mm, apertura entre postes de 450,85 mm, taladros a 464,2–465,8 mm entre centros. Que U1 sea la de abajo es **decisión de diseño**: la fuente no indica sentido de numeración.
3. **Nombres que el juego entiende** (empties en Blender, convertidos por un script de post-importación de Godot):

   | Empty / malla | Uso | Orientación (en Godot) |
   |---|---|---|
   | `PORT_<grupo>_<índice>` | Toma de un puerto | +Z sale de la toma |
   | `POWER_IN_<n>` / `POWER_OUT_<n>` | Entrada / salida de alimentación | +Z sale de la toma |
   | `LED_<nombre>` (malla) | Indicador, recoloreable por la simulación | — |
   | `STAND_POINT` | Punto donde se coloca el personaje | −Z = hacia dónde mira |
   | `CAM_<modo>` | Ancla de cámara para una vista cercana | −Z = dirección de la mirada (como `Camera3D`) |
   | `RACK_U1` | Origen del hueco U1 de un rack (plano de montaje) | — |
   | `SCREEN` (malla) | Pantalla que recibirá la textura del escritorio simulado | — |
   | `DELIVERY_POINT` | Punto de entrega de paquetes de una habitación | — |

   Convención de los equipos: el frente mira a −Y en Blender, que es +Z en Godot.

4. **Colisiones:** mallas simples con sufijo de importación de Godot (`-col`, `-colonly`) `[POR VERIFICAR en 4.7.2]`.
5. **Materiales:** un material llamado `M_Palette` en Blender. En Godot se sustituye por el material compartido del atlas al importar.
6. **Exportación** a `.glb` en `assets/models/<categoria>/<id>.glb`. El `.blend` fuente va en `art_source/<categoria>/<id>.blend` (carpeta ignorada por Godot). No se importan `.blend` directamente, para que nadie dependa de Blender para abrir el proyecto.
7. **En Godot:** una escena envoltorio `<id>.tscn` instancia el `.glb` como **hijo visual** y añade los nodos funcionales (vista del dispositivo, interactuable, tomas, LED). **Cambiar el modelo no cambia la lógica.**
8. **Automatización futura:** exportación por lotes con `blender --background <archivo> --python tools/blender/export_glb.py`.

## 9. Interfaz `[PROPUESTA]`

- **Interfaz del juego (HUD, menús, cuaderno):** paneles planos de esquinas redondeadas (6–8 px), fondo Tinta translúcido, texto Hueso, acentos con el color de resaltado e iconos de línea.
- **Cuaderno:** estética de libreta (papel claro, tinta oscura y diagramas a mano limpios), coherente con el mundo.
- **Ordenador simulado («HomeLab OS»):** identidad propia de sistema operativo ficticio, distinta del HUD, para que se note que estás *dentro* de un ordenador.
- **Tipografías:** una sans legible para la interfaz y una monoespaciada para la terminal, ambas con licencia libre. Candidatas: *Atkinson Hyperlegible* y *JetBrains Mono*, que se distribuyen con licencia SIL OFL `[POR VERIFICAR al descargar]`. Añadirlas supone descargar ficheros de terceros, así que **requiere aprobación** (decisión 5 de [ROADMAP.md](ROADMAP.md) §5).
- **Escalado de interfaz:** 75–200 %, legible a 1080p como mínimo.

## 10. Modelos provisionales («greybox»)

Cada objeto tiene una versión provisional desde el Hito 1:
- primitivas de Godot o Blender con **las dimensiones reales**;
- un color plano por categoría;
- los mismos empties funcionales (puertos, LED, punto de interacción, ancla de cámara) que tendrá el modelo final.

La escena envoltorio no cambia cuando llega el modelo definitivo: solo se sustituye el hijo visual.

## 11. Spike visual del Hito 1 (2026-11-15)

**Qué hay.** 16 modelos generados por `tools/blender/build_prototype_models.py` (Blender 5.3 en segundo plano):

| Grupo | Modelos |
|---|---|
| Habitación | `room_bedroom` |
| Muebles | `desk_basic`, `chair_office`, `bed_single`, `cabinet_small`, `rug_basic` |
| Equipos | `rack_12u_open`, `switch_16p_1u`, `server_1u_entry`, `router_home`, `power_strip_4`, `pc_tower_old`, `monitor_old`, `keyboard_mouse` |
| Atrezo | `package_box` |
| Personajes | `character_player` (jugador, §6.1) y `mannequin_scale` (maniquí de escala, solo en la muestra) |

- **Archivos:** cada uno exporta `assets/models/<categoría>/<id>.glb` y guarda su fuente editable `art_source/<categoría>/<id>.blend`, con los modificadores vivos.
- **Muestra:** `game/showcase/model_showcase.tscn` los coloca en la habitación, con el switch en U9 y el servidor en U5 del rack. Capturas en `docs/images/showcase/`.

**Cómo verlo:**
- `tools\view_showcase.ps1` abre una ventana. Teclas `1`–`5` para cambiar de vista (general, rack, rack por detrás, escritorio, habitación); en la vista 1, `Q`/`E` para girar y la rueda para zoom. El maniquí solo aparece en la vista general.
- En el editor (`tools\open_editor.ps1`): abrir `game/showcase/model_showcase.tscn` y navegar el visor 3D, o pulsar F6.
- Los `.blend` se abren en Blender.

**Verificado** `[VERIFICADO: tests/check_models.gd, 2026-11-15]`:
- tamaños en metros (switch y servidor de 482,6 mm de ancho y 43,7 mm de alto);
- Y hacia arriba;
- los empties llegan a Godot como nodos con su nombre;
- la orientación de tomas, anclas de cámara y puntos de personaje cumple la convención de §8.

**Desviaciones respecto a §5** (a decidir):
- **Materiales:** se usa un material por color de la paleta en lugar del atlas de paleta. Es más simple para el *spike*; el atlas se valorará cuando haya muchos modelos.
- **Colores de atrezo nuevos** (definidos en el script): madera oscura, beige retro (PC antiguo), cartón, cinta de embalar, piel, pelo, interior de toma, cristal, cielo de ventana, pantalla y LED apagado. Se añadirán a §4 si se aprueba la identidad.

**Presupuestos:**
- El switch tiene 1080 triángulos, por encima del rango de 300–800 de §7, por sus 16 tomas recortadas. El resto está dentro.
- Optimización posible: tomas como textura en el nivel de detalle lejano.

**Lecciones técnicas:**
- **Booleanas:** los cortadores no deben solaparse; se usa un prisma en «T» por toma. Los cortadores solapados producían artefactos.
- **Sombras:** en habitaciones, la luz direccional necesita `directional_shadow_max_distance` ≈ 12 m. Con el valor por defecto aparece granulado.

**Limitaciones:**
- **El maniquí no es el personaje:** solo da la escala en la muestra. El jugador usa `character_player` (§6.1), que es provisional: un personaje definitivo con el rig y la cara de §6 exige modelado a mano en Blender, o recursos externos con licencia (decisión futura).
- **LED fijos:** los LED tienen estados fijos en el modelo solo para la muestra. En el juego los controlará la simulación (*spike* S5).
