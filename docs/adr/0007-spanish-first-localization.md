# ADR 0007 — Español de España primero, localización preparada

- **Estado:** aceptada (decisión del usuario, documento maestro §29)
- **Fecha:** 2026-11-15

## Contexto

El juego necesita un idioma inicial. Además, mucho texto (interfaz, catálogo, terminal, cuaderno) será difícil de traducir si no se prepara desde el principio.

## Decisión

- Idioma inicial: **español de España**. El inglés se incorporará más adelante.
- **Desde el primer día:** todo texto visible pasa por `tr()` con claves. No hay cadenas literales de interfaz en el código.
- `[PROPUESTA]` Formato gettext (`.po`) por dominios y cuaderno escrito por idioma ([ARCHITECTURE.md](../ARCHITECTURE.md) §9). Pendiente de aprobación.

## Consecuencias

- Coste pequeño y constante al escribir interfaz (claves en lugar de texto).
- Añadir el inglés será traducir catálogos y entradas, no tocar código.
- La terminal debe decidir qué mensajes se traducen. Propuesta de emular `LANG` en [TERMINAL_DESIGN.md](../TERMINAL_DESIGN.md) §10.
