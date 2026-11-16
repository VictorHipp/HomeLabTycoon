# Comprobar la red y terminar la misión

## Ping desde tu PC
![La terminal del PC con la respuesta del ping](res://assets/manual/22_ping.png)
1. Siéntate al ordenador y abre la aplicación **Terminal**.
2. Escribe `ping -c 4 192.168.1.50` y pulsa `Intro`.
3. Si todo está bien, verás cuatro respuestas `64 bytes from 192.168.1.50`. Si algo falla (un cable suelto, el switch sin corriente, otra subred), el ping no responde.

> El recorrido de los datos es: PC → router → switch → servidor. Por eso el switch tiene que estar unido al router.

## Misión completada
![El cartel de misión completada con la recompensa](res://assets/manual/23_mision.png)
El juego comprueba la misión por el estado real de tu red: en cuanto el servidor está montado, encendido, unido al switch, el switch al router, con una IP válida y el PC lo alcanza, aparece el cartel con la recompensa.

- Recibes **600 créditos** y **150 de experiencia**, y subes de nivel. La recompensa se da una sola vez.
- Pulsa **«Seguir jugando»**: puedes seguir comprando, recolocando y probando cosas.
