---
name: hardware-catalog
description: "Úsala para añadir, modificar, equilibrar o validar equipos del catálogo de HomeLab Tycoon (racks, servidores, switches, routers, cables, componentes, NAS, UPS, PDU, transceptores, herramientas…), su esquema de datos, ids, precios, puertos, consumo y compatibilidades, y los datos que usa la tienda. No cubre cómo se comporta el hardware en la simulación (homelab-simulation)."
---

# Catálogo de hardware

**Documento dueño:** `docs/HARDWARE_CATALOG.md`. Contiene las categorías, el esquema actual y el propuesto, la tienda, los pedidos, el inventario, las reglas de montaje en rack y el catálogo del prototipo. Esta skill es el **procedimiento**.

## Estado del esquema

- **Implementado:** `HardwareDefinition` (`sim/hardware/hardware_definition.gd`) con `enum Category`, y `PortDefinition`. Un item: `data/catalog/rack_42u_basic.tres`.
- **Modelos provisionales** del prototipo en `assets/models/` (`tools/blender/build_prototype_models.py`). Al crear un item, su número de marcadores `PORT_*` debe coincidir con sus puertos; añade la expectativa en `tests/check_models.gd`.
- **`[PROPUESTA]` pendiente de aprobación:** esquema por composición, con categorías como datos y `DeviceSpec` (`docs/HARDWARE_CATALOG.md` §3.2). **No migres sin aprobación;** mientras tanto, usa el esquema implementado.

## Reglas confirmadas

- Productos **ficticios** con especificaciones **coherentes con tecnologías reales**.
- **Catálogo por datos:** ninguna regla de comportamiento en el catálogo y ninguna cifra de hardware en el código.
- Nada de dispositivos decorativos sin función técnica.

## Convenciones

- **`id`:** `StringName` snake_case `<categoría>_<modelo>[_<variante>]` (`switch_16p_basic`, `cable_cat6_3m`). Único y **estable para siempre**; el archivo se llama `<id>.tres`.
- **Nombre visible:** `"<Marca> <Modelo> (<descripción corta>)"`, con marcas ficticias (`docs/HARDWARE_CATALOG.md` §8).
- **`price`:** entero en créditos.
- **Puertos:** grupos homogéneos (`count` × `kind` a `speed_mbps`); id de grupo único dentro del item (`&"lan"`, `&"uplink"`, `&"psu"`).
- **Escena:** envoltorio con sus tomas (`PortSocket`), tantas como puertos (`docs/INTERACTION_SYSTEM.md` §10–11). Si aún no existe, greybox con dimensiones reales.

## Cifras técnicas

**Ninguna cifra se escribe de memoria.** Consulta `docs/TECH_RESEARCH.md`:

- **`[VERIFICADO]`:** se puede usar.
- **`[POR VERIFICAR]`:** se puede usar en un **borrador** marcado como tal, nunca en reglas del simulador ni en el cuaderno. Abre o completa la entrada de investigación.

Hoy están pendientes de verificar (TECH_RESEARCH §6):
- dimensiones de rack;
- alcances por categoría de cable;
- potencias PoE;
- consumos típicos.

## Equilibrio `[PROPUESTA]`

- Cada item tiene una **etapa de desbloqueo** (1–6, `docs/PROGRESSION.md` §4) y, dentro de ella, una gama (entrada, media, alta).
- Un item caro es **mejor en algo y peor en otra cosa** (consumo, ruido, calor, U, precio). Evita items estrictamente dominantes.
- Los precios son **borradores** hasta el equilibrio con la simulación económica (`game-design`).

## Procedimiento para añadir un item

1. Comprueba que tiene función técnica en el hito o etapa actual y que no duplica otro.
2. Revisa las cifras en `docs/TECH_RESEARCH.md`; si faltan, investiga primero.
3. Crea `data/catalog/<id>.tres`: con el MCP (`resource_manage`), o copiando uno existente y cambiando valores con el editor cerrado.
4. Escena envoltorio o greybox con sus tomas, LED y punto de interacción.
5. Ejecuta `tools\check_project.ps1` (el smoke test carga todos los `.tres`) y las validaciones del catálogo (`docs/HARDWARE_CATALOG.md` §9).
6. Si cambias una regla del esquema, actualiza `docs/HARDWARE_CATALOG.md` §3; si afecta a varios sistemas, añade un ADR.
