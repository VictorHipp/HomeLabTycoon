# ADR 0010 — Economía con libro de movimientos, ingresos pasivos con tope y segunda mano

- **Estado:** **aceptada** (pedida por el usuario el 2026-11-16). Las cifras son `[PROPUESTA]` y se ajustarán jugando.
- **Fecha:** 2026-11-16

## Contexto

Tras probar el juego, el usuario pidió (2026-11-16):
- que los puntos tengan lógica y control, sin que «sobren puntos porque sí»;
- unos pocos puntos pasivos cuando los servicios estén funcionando, para recuperarse si compra de más;
- vender lo comprado, como en un mercado de segunda mano, por menos de lo que costó.

Situación anterior:
- 1500 créditos iniciales para un material de 808: sobraban 692, más los 600 de la recompensa, sin nada en qué gastarlos;
- la XP llegaba de golpe al final;
- ningún movimiento de dinero tenía un motivo visible.

La decisión 8 (`docs/ROADMAP.md` §5 y `docs/PROGRESSION.md` §1) pide **sin esperas artificiales ni farmeo**. Unos ingresos pasivos sin límite chocarían con ella: con ×4 o «Saltar espera» se convertirían en una fuente de dinero inagotable.

## Decisión

1. **Libro de movimientos** (`sim/economy/economy.gd`): todo cambio de créditos o de XP pasa por `SimWorld.grant_rewards`, `purchase` o `sell_device` y deja una línea con su motivo. La suma de las líneas es el saldo. Se ve en la aplicación «Mi cuenta» del PC y, en el HUD, como avisos flotantes «+N cr» y «−N cr».
2. **XP por objetivo, una sola vez:** cada requisito de misión da su XP la primera vez que se cumple. Deshacerlo y rehacerlo no da nada. La misión da el resto al completarse; el total sigue siendo 150 XP.
3. **Créditos iniciales ajustados al material:** 1000 créditos para un material mínimo de 808. Coincide con el «poco margen» de la misión confirmada (`PROGRESSION.md` §9).
4. **Ingresos pasivos con tope diario:**
   - cada equipo con `online_income_per_hour` en el catálogo cobra mientras esté encendido y sea accesible en los dos sentidos desde el PC del jugador; hoy solo el servidor, 4 cr por hora de juego;
   - se cobra a la hora en punto, con dinero entero; las fracciones se acumulan y se guardan;
   - entre todos los equipos se cobra como máximo `passive_daily_cap` = 60 cr por día de juego. Lo que pase del tope no se acumula para el día siguiente.
5. **Segunda mano:**
   - solo se vende lo que está en el inventario y se compró en la tienda (lo de la casa no se pagó), con el PC conectado a Internet;
   - se paga el 60 % si el objeto está sin estrenar y el 45 % si ya se instaló o se conectó;
   - lo vendido no se borra: queda con la ubicación `sold`, para que los pedidos antiguos y el libro sigan pudiendo nombrarlo.
6. Las cifras están en datos: `data/economy/economy_rules.tres` y el catálogo.
7. El guardado pasa a la versión 2. Una partida v1 se sigue cargando: el libro empieza vacío, lo instalado cuenta como usado y una misión completada no vuelve a dar XP.

## Consecuencias

- **A favor:**
  - cada crédito tiene un motivo visible;
  - comprar de más se puede corregir, siempre con pérdida;
  - montar más servidores tiene sentido económico, pero con un techo.
- **No es una fuente inagotable:**
  - comprar y revender siempre pierde dinero, y una prueba automática lo comprueba con todos los productos;
  - esperar entregas una y otra vez nunca da más que el tope diario (`tests/integration/test_economy.gd`).
- **Honestidad:**
  - aún no hay servicios simulados en los servidores;
  - el ingreso depende de que el equipo esté encendido y sea accesible, y así se dice en «Mi cuenta», en la ficha de la tienda y en el manual;
  - cuando existan servicios (archivos, copias…), el ingreso dependerá de ellos.
- **Pendiente:** la XP y el nivel todavía no desbloquean nada. Su efecto (categorías de la tienda, contratos) llegará con las etapas (`PROGRESSION.md` §10.3).
