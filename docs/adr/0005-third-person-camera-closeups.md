# ADR 0005 — Tercera persona con transiciones a vistas cercanas

- **Estado:** aceptada (decisión del usuario, documento maestro §2)
- **Fecha:** 2026-11-15
- **Sustituye a:** la cámara orbital sin personaje de la visión v0

## Contexto

La visión v0 planteaba una cámara orbital libre sobre la sala, sin personaje visible. El usuario ha decidido una experiencia al estilo de los simuladores sociales: un personaje visible y controlado con clic, y vistas cercanas para las interacciones detalladas.

## Decisión

- Perspectiva principal en **tercera persona elevada** (tres cuartos), con zoom y giro.
- El personaje camina solo hasta el punto del clic.
- Al interactuar, el personaje se acerca y la cámara hace una **transición fluida y rápida** a una vista cercana (casi a la altura de los ojos), que puede parecer primera persona **solo durante la interacción**.
- Las cámaras, los puntos de interacción y las transiciones son **reutilizables y configurables**, sin duplicar la lógica de cada dispositivo.

Diseño técnico propuesto en `docs/CAMERA_SYSTEM.md` e `docs/INTERACTION_SYSTEM.md`.

## Consecuencias

- **Nuevos módulos:** personaje con navegación, director de cámara, gestor de interacciones y controladores genéricos de vista cercana.
- **Más contenido por objeto:** cada objeto interactuable necesita punto de interacción y anclas de cámara (empties en el modelo).
- **Menos animación:** las vistas cercanas permiten usar interfaces y modelos simplificados en lugar de animar manos y herramientas.
- **Riesgos técnicos** con *spikes* planificados: legibilidad de la pantalla del ordenador (S2) y coste de la navegación dinámica (S3).
