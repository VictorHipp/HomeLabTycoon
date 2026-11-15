---
name: game-design
description: "Úsala para decisiones de diseño de HomeLab Tycoon: mecánicas nuevas, progresión por etapas, competencias, misiones y sus validadores, economía y equilibrio, modos (Carrera, Sandbox, Desafíos), UX de construcción e interacción, cuaderno educativo, alcance de un hito y evaluación de ideas. No es para implementación (godot-development) ni para reglas técnicas del simulador (homelab-simulation)."
---

# Diseño del juego

La fuente de verdad es la documentación, no esta skill. Esta skill dice **cómo** decidir y **dónde** mirar.

## Dónde está cada cosa

| Tema | Documento |
|---|---|
| Visión, principios, modos, cambios respecto a v0 | `docs/GDD.md` |
| Etapas, competencias, misiones, economía, tiempo | `docs/PROGRESSION.md` |
| Cámara y movimiento | `docs/CAMERA_SYSTEM.md` |
| Interacciones, cableado (UX), colocación | `docs/INTERACTION_SYSTEM.md` |
| Cuaderno y niveles de ayuda | `docs/TUTORIAL_SYSTEM.md` |
| Arte | `docs/ART_STYLE.md` |
| Hitos, trazabilidad y decisiones pendientes | `docs/ROADMAP.md` |

## Reglas confirmadas por el usuario (no se discuten sin él)

- Tercera persona elevada con transiciones a vistas cercanas.
- Low-poly estilizado original.
- Todo simulado.
- Cableado prioritario.
- Terminal profunda y honesta.
- Seis etapas.
- Competencias **demostradas**, sin esperas artificiales ni farmeo.
- Misiones validadas por el **estado**, con varias soluciones.
- Cuaderno voluntario con 3 niveles.
- Modos Carrera, Sandbox y Desafíos.
- Español de España, Windows, un jugador.

Lista completa: `CLAUDE.md`.

## Cómo evaluar una mecánica o idea nueva

1. **Pilar:** ¿refuerza alguno? Construir es el juego · Aprender haciendo · Realismo verificable · Progresión justa · Libertad para experimentar (`docs/GDD.md` §4).
2. **Decisión:** ¿crea una decisión interesante o enseña algo que se **demuestra construyendo**? Si solo se puede «responder», no encaja.
3. **Verificabilidad:** ¿la regla técnica que implica está verificada (`docs/TECH_RESEARCH.md`)? Si no, primero se investiga.
4. **Coste:** modelo, simulación, UI, pruebas, cuaderno y documentación. ¿Cabe en el hito actual o va a una etapa posterior?
5. **Honestidad:** ¿podría aparentar algo no implementado? Entonces se declara o se pospone.
6. **Registro:** la decisión va al documento dueño. Lo que no está confirmado por el usuario se marca `[PROPUESTA]` y se añade a `docs/ROADMAP.md` §5.

## Cómo diseñar una misión

- Contexto, presupuesto, requisitos, restricciones, recompensas y criterios de éxito (`docs/PROGRESSION.md` §6).
- Cada requisito es un **validador sobre el estado** (`reachable`, `service_available`, `survives_failure`…). Nunca una secuencia de acciones.
- Debe tener **al menos dos soluciones válidas**, que se escriben como pruebas.
- Cada requisito enlaza con entradas del cuaderno en sus tres niveles.
- Solo usa sistemas implementados en el hito correspondiente.

## Equilibrio

1. Fijar el ritmo objetivo por etapa.
2. Simular el flujo de caja en *headless*.
3. Ajustar **datos**, no lógica.
4. Ninguna ruta debe dominar y cada etapa debe tener un cuello de botella distinto.

Los errores caros se pueden revertir; el dinero negativo bloquea compras, no la partida.
