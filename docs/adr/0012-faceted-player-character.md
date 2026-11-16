# ADR 0012 — Personaje del jugador facetado

- **Estado:** **aceptada** (pedida por el usuario el 2026-11-16). Precisa §2 y §3 de `docs/ART_STYLE.md` solo para los personajes.
- **Fecha:** 2026-11-16

## Contexto

La identidad visual aprobada (decisión 16) dice:
- §2: todas las aristas exteriores llevan un **bisel generoso**;
- §3: las personas se hacen con **volúmenes redondeados, cápsulas y curvas suaves**.

El jugador era un maniquí de cajas biseladas, solo de escala.

El usuario pidió (2026-11-16) mejorar el modelo del personaje con «un poco más de modelado», como una imagen de referencia de estilo *low-poly* facetado, pero con ropa y estilo acordes al juego.

## Decisión

- **Modelo:** el jugador usa `character_player`, generado por `build_character_player` en `tools/blender/build_prototype_models.py`.
- **Talla facetada:**
  - caras planas trianguladas y **sin bisel**;
  - cada triángulo con uno de tres tonos de su color, con semillas fijas;
  - secciones de 8–16 lados que conservan una **silueta redondeada**: la intención de §3 (cercanía) se mantiene, aunque la superficie sea facetada.
- **Ropa y aspecto:** los decidió Claude dentro de la paleta del hogar y pueden cambiar en el generador: sobrecamisa abierta, camiseta, vaqueros, zapatillas, gafas y barba corta. Solo el modelado facetado lo pidió el usuario.
- **Articulaciones:** las mismas `J_*` que el maniquí, así que la animación por procedimiento no cambia.
- **Lo que sigue igual:** los equipos y muebles mantienen el bisel de §2. El rig estándar, el atlas de expresiones y los accesorios modulares de §6 siguen siendo `[PROPUESTA]`.

## Consecuencias

- **Coste:** 76 piezas con hasta tres materiales cada una (unas 3600 caras). Hay más llamadas de dibujo que con el maniquí, y los FPS siguen sin medirse (H1-07). Si hiciera falta, se unirían las piezas de cada articulación.
- **Uniones:** las piezas rígidas se solapan en las articulaciones. Al sentarse, los muslos se hunden en el asiento, igual que con el maniquí; desde la cámara del juego no se ve.
- **Detalle en** `docs/ART_STYLE.md` §6.1.
