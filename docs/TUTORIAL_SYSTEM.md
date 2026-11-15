# TUTORIAL_SYSTEM — Cuaderno interactivo y aprendizaje

> **Estado:** diseño; nada implementado. Requisitos `[CONFIRMADO]` (documento maestro §18). Diseño técnico `[PROPUESTA]`.

## 1. Requisitos `[CONFIRMADO]`

- Un cuaderno dentro del juego que funciona como **manual de consulta** y que el jugador abre cuando necesita ayuda.
- **Cada tutorial incluye:**
  - el concepto y para qué sirve;
  - ejemplos reales;
  - imágenes, diagramas y capturas del juego;
  - procedimientos paso a paso;
  - explicación de órdenes;
  - errores comunes y comprobaciones.
- **Visual,** no solo bloques de texto.
- **Tres niveles de ayuda** que elige el jugador:
  1. **Información:** explica los conceptos necesarios.
  2. **Pistas:** ayuda a encontrar la solución.
  3. **Tutorial completo:** instrucciones detalladas e ilustradas.
- **Voluntario:** el juego no interrumpe continuamente para explicarlo todo.
- **Funciones:** buscador, categorías, índice, marcadores, historial, enlaces entre temas y acceso desde las misiones.
- **Honesto:** el contenido está ligado a lo que el simulador implementa. Una función que aún no existe no se explica sin indicarlo claramente.

## 2. Modelo de contenido `[PROPUESTA]`

Una entrada por archivo, en `data/notebook/<idioma>/<categoría>/<id>.md`. Se escribe en un **Markdown restringido**: es fácil de escribir y de revisar en diffs, y se convierte al BBCode de `RichTextLabel` al cargar, con un conversor pequeño y probado.

```markdown
---
id: ip_subnet_basics
title: Direcciones IP y subredes
category: redes
tags: [ip, subred, máscara]
stage: 1
requires_features: [net.ipv4_static, terminal.ip]
commands: [ip, ping]
related: [what_is_a_network, ping_check]
---
## Información
...concepto, para qué sirve, ejemplo real, diagrama...
## Pistas
...preguntas guía, qué comprobar...
## Tutorial
...pasos numerados con capturas, órdenes y salida esperada, errores comunes...
```

**Elementos admitidos:**
- títulos, listas, negrita y cursiva;
- bloques de órdenes con su salida;
- tablas simples;
- imágenes con texto alternativo;
- avisos («Error común», «Comprueba»);
- enlaces internos `[[id]]` y enlaces a misiones.

## 3. Niveles de ayuda y misiones

- **Enlaces desde la misión:** cada requisito de misión enlaza con entradas concretas ([PROGRESSION.md](PROGRESSION.md) §6). Desde el panel de la misión, el jugador abre la entrada **en el nivel que elija**.
- **Pistas progresivas:** dentro de «Pistas» se revelan una a una, para no destripar la solución.
- **Sin penalización `[PROPUESTA]`:** consultar el cuaderno no penaliza. Opcionalmente, una distinción «sin ayuda» de prestigio, sin efecto en dinero ni progresión. Decisión pendiente, ROADMAP §5.

## 4. Honestidad del contenido `[PROPUESTA]`

- **Registro de funcionalidades:** `data/features.tres` lista los identificadores de funcionalidad implementados (`net.ipv4_static`, `terminal.ip`…). El código los da de alta cuando un sistema existe de verdad.
- Si una entrada requiere funcionalidades no implementadas:
  - en **Carrera** se muestra con el aviso «Contenido de referencia: esta función aún no está disponible en el juego»;
  - los procedimientos paso a paso de esa entrada no se ofrecen.
- **Pruebas automáticas** (fallan la validación si no se cumplen):
  - toda orden citada en `commands:` o en bloques de órdenes existe en el registro de órdenes **e** implementa las opciones usadas;
  - todo `requires_features` es un identificador conocido;
  - todo enlace `[[id]]` existe y toda imagen referenciada existe;
  - toda orden implementada tiene al menos una entrada del cuaderno.

## 5. Interfaz `[PROPUESTA]`

- **Acceso:** un botón del HUD, una tecla (`N`), el panel de la misión y la orden `man` (que enlaza con la entrada).
- **Estética** de libreta coherente con el arte ([ART_STYLE.md](ART_STYLE.md) §9).
- **Panel izquierdo:** índice por categorías, búsqueda, marcadores e historial.
- **Panel derecho:** la entrada, con pestañas Información / Pistas / Tutorial.
- **Enlaces:** se manejan con la señal `meta_clicked` de `RichTextLabel` `[VERIFICADO: la señal existe en Godot 4.7.2, sonda ClassDB, 2026-11-15]`.
- **Búsqueda:** índice invertido construido al cargar. Ignora mayúsculas y tildes; ordena por título, luego etiquetas y luego cuerpo.
- **Persistencia:** marcadores, historial y entradas leídas se guardan con la partida, como parte del avance educativo.

## 6. Ilustraciones `[PROPUESTA]`

| Tipo | Cómo se produce |
|---|---|
| Diagramas de red y de flujo | Renderizador de diagramas propio, compartido con el diseñador de topologías ([NETWORK_SIMULATION.md](NETWORK_SIMULATION.md) §11). Se describen como datos y se ven con el estilo del juego |
| Capturas del juego | Escena de captura reproducible: carga un escenario, coloca la cámara y guarda la imagen. Se regeneran cuando cambia la interfaz (herramienta futura en `tools/`) |
| Ilustraciones conceptuales | Hechas a mano más adelante; al principio, diagramas simples |

Todas las imágenes viven en `assets/notebook/` y llevan texto alternativo.

## 7. Flujo de autoría

1. Crear la entrada con los metadatos y los tres niveles.
2. Comprobar cada afirmación técnica contra [TECH_RESEARCH.md](TECH_RESEARCH.md): solo datos verificados o simplificaciones documentadas.
3. Comprobar cada procedimiento **en el juego real**: las órdenes y la salida mostradas deben coincidir con lo que produce la terminal (pruebas «golden»).
4. Pasar la validación automática (§4).

## 8. Alcance del prototipo (Hito 7)

Entre 4 y 6 entradas con los tres niveles y al menos una ilustración cada una:
1. Qué es una red.
2. Cables y puertos de red.
3. Qué hace un switch.
4. Direcciones IP y subredes.
5. La terminal: primeros pasos.
6. Comprobar la conectividad con `ping`.

Funciones del cuaderno en el prototipo: índice, búsqueda, enlaces, marcadores, historial y acceso desde la misión.
