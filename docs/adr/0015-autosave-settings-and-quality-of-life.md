# ADR 0015 — Autoguardado, ajustes del jugador y comodidades habituales del género

- **Estado:** **aceptada**. El usuario pidió el 2026-11-16 revisar el código y aplicar, sin consultarle, las mejoras que Claude considerase, basándose en técnicas habituales de juegos parecidos. **Qué se eligió y cómo es decisión de Claude**; el usuario puede revertir cualquier punto.
- **Fecha:** 2026-11-16

## Contexto

Tras el menú de inicio ([ADR 0014](0014-title-menu-and-character-look.md)) quedaban carencias que los simuladores y juegos de gestión resuelven siempre de la misma manera:

- un solo archivo de partida, sin autoguardado: cerrar la ventana o volver al título perdía lo no guardado;
- si la escritura fallaba en el último paso, la ranura quedaba vacía, y un archivo dañado no se recuperaba de la copia `.bak` que ya se conservaba;
- ningún ajuste: el suavizado de bordes estaba fijo en el código y la sensibilidad de la cámara no se podía cambiar;
- el reloj solo se manejaba con el ratón;
- en la vista general nada decía qué era cada objeto ni qué hacía cada botón del ratón sobre él;
- el manual y los controles solo se veían dentro de una partida, y `Esc` no hacía nada en el creador de personaje.

La revisión encontró además dos defectos:

- con la ayuda emergente de un botón del HUD a la vista, `Esc` no abría el menú;
- «Cargar partida» dentro del juego descartaba el progreso sin avisar, mientras que «Volver al menú principal» sí avisaba.

## Decisión

1. **Autoguardado en un archivo aparte** (`partida_auto.json`, junto a `partida.json`). Nunca sustituye a la partida que guarda el jugador.
   - Se escribe cada N minutos reales con el reloj en marcha (5 por defecto; ajustable o desactivable), al llegar un pedido, al completar una misión, al volver al menú principal y al cerrar la ventana.
   - Una marca breve «Autoguardado ✓» lo indica sin interrumpir.
   - No se escribe en ejecuciones sin ventana (comprobaciones).
2. **«Continuar» en el título:** carga lo más reciente, sea la partida guardada o el autoguardado, y dice cuál es. Solo aparece si hay algo que continuar. «Cargar partida» sigue cargando la partida del jugador.
3. **Guardado más robusto** (`SaveService`):
   - si el último renombrado falla, se restaura el archivo anterior;
   - si el archivo no se puede leer, se carga la copia `.bak` y el mensaje lo dice;
   - un archivo dañado nunca sustituye a una copia buena;
   - cada archivo lleva `saved_at` (hora real), que solo se usa para elegir el más reciente.
4. **Avisos coherentes:** «Volver al menú principal» autoguarda y sale con un solo clic (solo avisa si el autoguardado falla). «Cargar partida» dentro del juego avisa en el primer clic y carga en el segundo.
5. **Ajustes del jugador** (`GameSettings`, `user://settings.cfg`): pantalla completa, sincronización vertical, suavizado de bordes, contador de fotogramas, sensibilidad e inversión del giro de la cámara y autoguardado.
   - Son de la máquina, no de la partida: **no van en el archivo de guardado** y el formato sigue en la versión 3.
   - Una tabla (`SPECS`) genera el archivo, los valores por defecto y la página «Ajustes › Opciones».
   - Un valor desconocido en el archivo vuelve al valor por defecto.
6. **Reloj con el teclado:** `Espacio` pausa y reanuda a la velocidad anterior; `1`, `2` y `3` ponen ×1, ×2 y ×4. `F5` es un guardado rápido. Son acciones con nombre (`InputBindings`), aparecen en «Controles» y no actúan mientras se usa la pantalla del ordenador o se escribe.
7. **Etiqueta junto al cursor** en la vista general (`HoverTip`): nombre de lo que hay debajo y qué hace cada botón del ratón. Usa las mismas reglas que los clics. Adelanta la parte de «etiqueta al pasar el ratón» del Hito 2 ([ROADMAP](../ROADMAP.md) §2).
8. **Menú sin partida:** el título abre el mismo menú del juego sin los botones de partida («Manual y ajustes»), y `F1` abre allí el manual. `Esc` en el creador vuelve al título.
9. **`Esc` en la vista general se lee antes que la interfaz** (`_input`), para que una ayuda emergente no se lo quede.
10. **Texto de fin de misión en los datos:** `MissionDefinition.completion_text` (antes estaba en el código de la sesión).

## Consecuencias

- **Archivos del jugador:** las pruebas y el recorrido usan sus propios archivos de partida, autoguardado y ajustes, y el recorrido no cambia el modo de la ventana. Una prueba comprueba que no se toca el archivo de ajustes del jugador.
- **Empezar una partida nueva** con un autoguardado anterior lo sustituirá en el primer autoguardado; la partida guardada a mano no se toca.
- **Pendiente:**
  - varias ranuras de guardado (Hito 7);
  - reasignar teclas desde el juego;
  - sonido (no hay ningún recurso de audio y no se descarga nada sin autorización);
  - la pantalla completa y la sincronización vertical no las ejercita el recorrido, que solo comprueba que el valor se guarda.
- **Descartado en esta ronda**, por riesgo sin beneficio visible: dividir `sim_world.gd` e `interaction_manager.gd`, y cambiar el modo de escalado de la ventana en `project.godot` (movería todas las capturas y las coordenadas del recorrido).
