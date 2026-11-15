# CAMERA_SYSTEM — Cámara, movimiento y transiciones

> **Aprobación:** el diseño por defecto de este documento queda aprobado para el Hito 1 al aprobar el usuario el inicio del hito (2026-11-15). Los cambios importantes se consultan antes ([README.md](README.md)).
>
> **Estado:** implementado en la prueba jugable (2026-11-15). Incluye la vista general (§3.1), el director con transición en dos fases, el corte automático de paredes (variante de malla baja) y el movimiento del personaje con navegación.
>
> **Pendiente:**
> - alternar los tres modos de paredes;
> - la opción «reducir movimiento» en los ajustes (existe en el director, pero no en la interfaz);
> - los *spikes* S1 (tu opinión sobre la sensación) y S3.
>
> Requisitos `[CONFIRMADO]` (documento maestro §2). Solución técnica `[PROPUESTA]`. Las clases de Godot citadas existen en 4.7.2 `[VERIFICADO: sonda ClassDB headless, 2026-11-15]`.

## 1. Requisitos `[CONFIRMADO]`

**Vista general:**
- Cámara 3D elevada en tres cuartos, con el personaje visible.
- Zoom y giro; **no** es una cámara fija.
- Movimiento cómodo por la habitación.
- Selección con el ratón.
- Personaje que se desplaza solo hasta donde se hace clic.
- Controles alternativos en el futuro.

**Transición a vista cercana:**
1. El personaje camina hasta el objeto.
2. La cámara se acerca al personaje y al objeto.
3. Continúa hasta una perspectiva cercana, aproximadamente a la altura de los ojos.

Debe ser fluida, relativamente rápida y sin cortes entre escenas desconectadas. Al cerrar, vuelve suavemente a la vista general.

**Reutilización:** cámaras, puntos de interacción y transiciones configurables, **sin duplicar la lógica de cada dispositivo** para sus distintas vistas.

## 2. Arquitectura `[PROPUESTA]`

Una sola `Camera3D` en el juego, controlada por un **director de cámara**. Las vistas son datos, no cámaras distintas.

```
CameraDirector (Node3D)          máquina de estados: OVERVIEW · TRANSITION · CLOSEUP
 ├─ OverviewRig                  calcula la pose de vista general a partir de:
 │    focus (Vector3), yaw, pitch, distance
 └─ Camera3D                     la única cámara; el director le aplica la pose resultante
CameraShot (Resource o Marker3D)  pose objetivo: transform, fov, near, límites de mirada
```

- **Pose:** `Transform3D` + FOV. Una transición interpola de la pose actual a la de destino.
- **Anclas de cámara:** cada objeto interactuable incluye en su escena un `Marker3D` por modo de vista cercana (`CAM_rack_front`, `CAM_rack_rear`, `CAM_screen`). Vienen del modelo como empties `CAM_<modo>` ([ART_STYLE.md](ART_STYLE.md) §8). El director **no sabe nada** de racks ni ordenadores: solo recibe una ancla.
- **Sin addons de cámara:** el director es código propio y breve. Alternativa descartada por ahora: un addon de terceros de cámaras virtuales, que añadiría una dependencia sin necesidad clara.

## 3. Vista general

### 3.1. Controles por defecto `[PROPUESTA]` (reasignables, ver ARCHITECTURE §10)

**Implementado el 2026-11-15** (`game/camera/overview_camera_rig.gd`). Tras probar la muestra, el usuario pidió **girar con el ratón**: el giro por arrastre sustituye a los pasos de 45°.

| Acción | Control |
|---|---|
| Mover personaje / usar objeto | Clic izquierdo |
| Girar la cámara | **Arrastrar con el botón derecho o con el central** (horizontal = giro, vertical = inclinación) · mantener `Q` / `E` (giro continuo y suave) |
| Zoom | Rueda del ratón |
| Desplazar el foco | `W` `A` `S` `D` / flechas |
| Centrar en el personaje | `F` |
| Velocidad del tiempo | Botones del HUD: pausa, ×1, ×2, ×4 y «Saltar espera» |

Un clic derecho sin arrastre queda libre para el menú contextual futuro y para desconectar puertos en las vistas cercanas.

Desplazamiento por bordes de pantalla: opcional, desactivado por defecto.

### 3.2. Parámetros iniciales `[PROPUESTA]` (se afinan en el *spike* S1)

| Parámetro | Valor |
|---|---|
| Inclinación (pitch) | 25°–65°, inicial 30,6° (el encuadre de la muestra aprobada) |
| Distancia al foco | 3–12 m, inicial 7,46 m |
| FOV | 42° |
| Suavizado de zoom y giro | exponencial, constante 10/s (≈ 0,1 s) |
| Giro con teclado / ratón | 100°/s · 0,3° por píxel (invertible por eje) |
| Límites del foco | caja de la habitación actual |

Valores implementados el 2026-11-15, con pruebas en `tests/unit/test_camera_rig.gd`.

### 3.3. Paredes que tapan (corte de paredes) `[PROPUESTA]` `[SPIKE]`

En una habitación con cámara elevada, las paredes cercanas a la cámara tapan la escena. Como en los simuladores sociales, hay tres modos alternables:
- **paredes completas**;
- **cortadas** (por defecto): las paredes cuya normal mira hacia la cámara se muestran a ≈ 0,3 m de altura;
- **bajadas**: todas cortadas.

Cada tramo de pared conoce su normal y el director evalúa el producto escalar con la dirección horizontal de la cámara. El corte puede ser un cambio de malla (versión baja de la pared) o un shader con transparencia por tramado. El *spike* decide cuál.

### 3.4. Seguimiento

Por defecto el foco es **libre**: el jugador mira donde quiere mientras el personaje camina. Con `F` se centra en el personaje. `[PROPUESTA]` Opción en ajustes: «seguir al personaje mientras camina».

## 4. Movimiento del personaje

**Flujo:**
1. **Clic en el suelo:** rayo desde la cámara con `project_ray_origin` / `project_ray_normal` `[VERIFICADO: existen en 4.7.2]` contra la capa de colisión «suelo».
2. Se fija el destino en un `NavigationAgent3D` (`set_target_position`) del personaje (`CharacterBody3D`), que avanza hacia `get_next_path_position()` hasta `navigation_finished` `[VERIFICADO: métodos y señal existen en 4.7.2]`.
3. **Destino inalcanzable:** el agente no encuentra ruta y se muestra un aviso breve («No puedo llegar ahí»). El personaje no se mueve en línea recta atravesando muebles.
4. **Llegada:** el personaje gira con suavidad para mirar hacia el punto de interacción, si lo hay.
5. **Cancelación:** un clic nuevo reemplaza el destino; abrir una interacción también lo fija.

**Malla de navegación** (`NavigationRegion3D`):
- Se hornea a partir de las **formas de colisión** de la habitación y de los objetos colocados.
- Al colocar, mover o retirar un objeto se vuelve a hornear con `bake_navigation_mesh()`, agrupando cambios unos 0,2 s.

Datos de la documentación oficial `[VERIFICADO: docs.godotengine.org «Using NavigationMeshes», 2026-11-15]`:
- el horneado se hace por defecto en un hilo en segundo plano;
- el **análisis de geometría siempre ocurre en el hilo principal**;
- para rehorneados en ejecución se recomiendan formas de física en lugar de mallas visuales;
- un `cell_size` demasiado pequeño puede congelar el juego.

**Pendiente `[SPIKE]` S3:** confirmar el coste de rehorneado con 20–40 objetos y si `NavigationObstacle3D.affect_navigation_mesh` (la propiedad existe en 4.7.2) basta para excluir zonas sin rehornear todo.

**Animación:** `AnimationTree` con reposo, caminar, interactuar de pie, sentarse y teclear, agacharse y llevar caja ([ART_STYLE.md](ART_STYLE.md) §6). La velocidad de caminar es constante y no se usa *root motion*.

## 5. Transiciones a vista cercana

### 5.1. Trayectoria en dos fases `[PROPUESTA]`

Sigue la secuencia que describe el usuario:

```
Pose actual (vista general)
   │  fase A ≈ 0,35 s
   ▼
Pose de aproximación (calculada): detrás y por encima del hombro del personaje,
a ≈ 2 m, mirando al objeto
   │  fase B ≈ 0,35 s
   ▼
Ancla del objeto (CAM_<modo>): cerca, ≈ altura de ojos, el objeto ocupa gran parte de la pantalla
```

**Interpolación:**
- La **posición** sigue una curva suave por los tres puntos (Catmull-Rom o Bézier) con aceleración y frenado.
- La **rotación** se interpola por cuaterniones (slerp), igual que el FOV.
- `Transform3D.interpolate_with` existe y funciona en 4.7.2 `[VERIFICADO: sonda headless, 2026-11-15]`. Se usa para tramos simples; la curva por tres puntos se calcula en el director.

**Duración y comportamiento:**
- Duración total ≤ 0,8 s, configurable.
- Un clic durante la transición la completa al instante.
- La opción de accesibilidad **«reducir movimiento»** sustituye el viaje por un fundido breve.
- **Salida:** trayectoria inversa hasta la pose de vista general **guardada** al entrar. El jugador vuelve exactamente a donde estaba mirando.

### 5.2. El personaje durante la vista cercana `[PROPUESTA]`

El ancla está a la altura de los ojos, cerca de la cabeza. Para que el cuerpo no tape la vista:
- se oculta la malla del personaje al final de la fase B, conservando su sombra si queda bien;
- se muestra al inicio de la salida.

Así la vista cercana parece primera persona solo mientras dura la interacción `[CONFIRMADO]`.

### 5.3. Movimiento limitado en vista cercana

Cada ancla declara qué se permite:
- **Rack:** desplazamiento vertical a lo largo de las U (rueda o `W`/`S`), giro pequeño (±15°) y cambio frontal ↔ trasero (otra ancla, transición corta ≈ 0,4 s).
- **Pantalla:** cámara fija. La interfaz pasa a ocupar la vista ([INTERACTION_SYSTEM.md](INTERACTION_SYSTEM.md) §6).
- **Caja o inspección:** giro alrededor del objeto (±30°) y zoom corto.

### 5.4. Colisiones de cámara

- Las anclas las coloca el diseñador del modelo, con espacio libre.
- Al entrar, un rayo comprueba que no hay obstáculos entre el ancla y el objeto (otro rack delante, un mueble). Si los hay, se usa una alternativa: retroceder por el eje de mirada hasta tener visión libre.
- **Implementado (2026-11-15), versión simple:**
  - Las anclas del rack están a 0,8 m de su cara, y el rack exige 50 cm libres ([INTERACTION_SYSTEM.md](INTERACTION_SYSTEM.md) §8.1). Cuando el ancla queda detrás de una pared, la cámara se desplaza dentro de la habitación (a 0,12 m de la pared) y vuelve a mirar la cara del rack. La vista queda más inclinada, pero se ven y se pulsan todos los puertos.
  - El punto donde se coloca el personaje también se mantiene dentro de la habitación.
  - El rayo contra obstáculos no está implementado.

## 6. Estados y enrutado de la entrada `[PROPUESTA]`

```
OVERVIEW ──clic en objeto──▶ APPROACHING (camina; la cámara sigue en vista general)
   ▲                                │ llega al punto de interacción
   │                                ▼
TRANSITION_OUT ◀──Esc/Cerrar── CLOSEUP ◀──── TRANSITION_IN
```

| Estado | Quién recibe la entrada |
|---|---|
| OVERVIEW / APPROACHING | Cámara y selección |
| TRANSITION_* | Nadie (salvo el clic que completa la transición) |
| CLOSEUP | Controlador de la vista cercana (rack, pantalla…) y la UI |

## 7. Ajustes del jugador `[PROPUESTA]`

Sensibilidad de giro y zoom, invertir giro, velocidad de transición, «reducir movimiento», seguir al personaje y modo de paredes por defecto.

## 8. Spikes

| Id | Pregunta | Hito |
|---|---|---|
| S1 | ¿Los parámetros de §3.2 y la trayectoria de §5.1 «se sienten bien»? ¿Duraciones? | 1–2 |
| S3 | Coste de rehornear la navegación con 20–40 objetos; utilidad de `affect_navigation_mesh` | 1 y 3 |
| S6 | Corte de paredes: ¿cambio de malla o shader de tramado? | 1 |

## 9. Criterios de aceptación

Ver [TEST_PLAN.md](TEST_PLAN.md) §4, Hitos 1 y 2.
