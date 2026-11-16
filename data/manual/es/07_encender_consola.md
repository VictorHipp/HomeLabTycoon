# Encender y configurar el servidor

## Encender los equipos
![El panel del rack con el botón Encender del servidor marcado](res://assets/manual/20_encender.png)
- El **switch** no tiene botón: arranca solo en cuanto le llega corriente.
- El **servidor** necesita además que pulses **«Encender»** en el panel del rack. Tarda un momento en arrancar («arrancando…») y luego aparece como «encendido».
- Los **LED** del frontal se iluminan según el estado real: alimentación, y cada puerto de red con enlace activo.

> Si un equipo dice «apagado (sin corriente)», revisa su cable de corriente y la regleta.

## La consola del servidor
![La consola del servidor con las órdenes escritas](res://assets/manual/21_consola.png)
El servidor aún no tiene dirección IP. Dásela desde su **consola local**, como si le conectaras un monitor y un teclado:

1. En el panel del rack, pulsa **«Consola»** junto al servidor.
2. Escribe `ip address add 192.168.1.50/24 dev eth0` y pulsa `Intro`. Si está bien, no dice nada (como en Linux).
3. Comprueba con `ip address show eth0`: debe aparecer `inet 192.168.1.50/24`.
4. `Esc` (o «Cerrar») cierra la consola.

- `help` muestra las órdenes que existen. Las que todavía no están en el juego lo dicen claramente.
- Usa una dirección de la red de casa (`192.168.1.x`) que no use otro equipo. Si apagas el servidor, pierde esta configuración y habrá que repetirla.
