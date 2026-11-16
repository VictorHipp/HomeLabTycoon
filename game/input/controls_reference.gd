class_name ControlsReference
extends RefCounted
## The list of controls shown in Settings > Controls (and in the manual). One source for both.
## Keys and buttons of named actions are read from the InputMap at the moment the list is
## shown, so the page always tells the controls that really work. The few gestures that the
## code reads directly from the mouse (dragging to turn, right click on objects) are written
## out and marked as not remappable yet. tests/unit/test_controls_reference.gd checks that every
## action of InputBindings is listed.

## Each group: [title, rows]; each row: [what it does, actions (Array) or a fixed description].
const GROUPS := [
	["Cámara y desplazamiento", [
		["Girar la cámara", "Arrastrar con el botón derecho o con el central del ratón"],
		["Girar la cámara con el teclado", [&"camera_rotate_left", &"camera_rotate_right"]],
		["Acercar / alejar", [&"camera_zoom_in", &"camera_zoom_out"]],
		["Mover la vista", [&"camera_pan_forward", &"camera_pan_left", &"camera_pan_back", &"camera_pan_right"]],
		["Centrar la vista en el personaje", [&"camera_recenter"]],
	]],
	["En la habitación", [
		["Caminar hasta un punto / usar un objeto (ordenador, cajas, rack, regleta, router)", [&"interact"]],
		["Mover un mueble (cama, escritorio con el PC, mesilla, alfombra), el router o el rack; los cables se vuelven a tender si siguen llegando", [&"secondary"]],
		["Cancelar el cable que estás tendiendo (vuelve al inventario) · abrir el menú", [&"close_interaction"]],
		["Tender un cable: elegirlo en el inventario y seguir el panel «Paso 1 de 2 / 2 de 2»", "Clic izquierdo en el cable y luego en las tomas que brillan"],
		["Abrir el manual", [&"open_manual"]],
	]],
	["Colocar o mover un objeto o un mueble", [
		["Colocar en el sitio marcado en verde", [&"interact"]],
		["Girar 90°", [&"rotate_object"]],
		["Cancelar", [&"close_interaction"]],
		["Cancelar (también)", [&"secondary"]],
		["Girar la cámara mientras colocas", "Arrastrar con el botón derecho"],
	]],
	["Vista de cerca (rack, regleta, router)", [
		["Conectar el cable elegido en un puerto (brillan los compatibles: verde si llega, naranja si no)", "Clic izquierdo sobre el puerto"],
		["Desconectar el cable de un puerto", [&"secondary"]],
		["Cara frontal / trasera del rack", [&"rotate_object"]],
		["Volver a la vista general", [&"close_interaction"]],
	]],
	["Ordenador y consola", [
		["Escribir una orden y ejecutarla", "Teclado e Intro"],
		["Repetir órdenes anteriores", "Flechas ↑ y ↓"],
		["Levantarse del ordenador / cerrar la consola", [&"close_interaction"]],
	]],
	["Tiempo y partida (en la vista general)", [
		["Pausar el reloj del juego / reanudarlo", [&"time_pause"]],
		["Velocidad ×1 / ×2 / ×4", [&"time_speed_1", &"time_speed_2", &"time_speed_4"]],
		["Guardado rápido (igual que «Guardar partida»)", [&"quick_save"]],
	]],
	["Menú", [
		["Abrir el menú (en la vista general) · cerrarlo", [&"close_interaction"]],
		["Abrir o cerrar el manual", [&"open_manual"]],
	]],
]
const NOT_REMAPPABLE := "Los gestos de ratón escritos en cursiva todavía no se pueden cambiar."


## [title, [[what, keys text, is_fixed_gesture], ...]] with the current bindings.
static func groups() -> Array:
	var result: Array = []
	for group: Array in GROUPS:
		var rows: Array = []
		for row: Array in group[1]:
			if row[1] is Array:
				rows.append([row[0], keys_for(row[1]), false])
			else:
				rows.append([row[0], row[1], true])
		result.append([group[0], rows])
	return result


static func listed_actions() -> Array[StringName]:
	var result: Array[StringName] = []
	for group: Array in GROUPS:
		for row: Array in group[1]:
			if row[1] is Array:
				for action: StringName in row[1]:
					if not result.has(action):
						result.append(action)
	return result


## "Q / E", "W / A / S / D · ↑ / ← / ↓ / →"... from the InputMap.
static func keys_for(actions: Array) -> String:
	var primary: Array[String] = []
	var secondary: Array[String] = []
	for action: StringName in actions:
		if not InputMap.has_action(action):
			primary.append("?")
			continue
		var events := InputMap.action_get_events(action)
		for i: int in events.size():
			var name := event_name(events[i])
			var bucket := primary if i == 0 else secondary
			if not bucket.has(name):
				bucket.append(name)
	var text := " / ".join(primary)
	if not secondary.is_empty():
		text += " · " + " / ".join(secondary)
	return text


static func event_name(event: InputEvent) -> String:
	var key := event as InputEventKey
	if key != null:
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		match code:
			KEY_UP:
				return "↑"
			KEY_DOWN:
				return "↓"
			KEY_LEFT:
				return "←"
			KEY_RIGHT:
				return "→"
			KEY_ESCAPE:
				return "Esc"
			KEY_ENTER:
				return "Intro"
			KEY_SPACE:
				return "Espacio"
		return OS.get_keycode_string(code)
	var mouse := event as InputEventMouseButton
	if mouse != null:
		match mouse.button_index:
			MOUSE_BUTTON_LEFT:
				return "Clic izquierdo"
			MOUSE_BUTTON_RIGHT:
				return "Clic derecho"
			MOUSE_BUTTON_MIDDLE:
				return "Clic central"
			MOUSE_BUTTON_WHEEL_UP:
				return "Rueda hacia arriba"
			MOUSE_BUTTON_WHEEL_DOWN:
				return "Rueda hacia abajo"
	return event.as_text()
