class_name WalkthroughDriver
extends Node
## Development tool (not part of the game): plays the first mission end to end through the real
## input path — synthetic mouse / keyboard events at projected 3D positions — and saves one
## screenshot per step, so the whole flow can be checked without a person at the keyboard.
## Start it with tools\walkthrough.ps1 (adds `-- --walkthrough=<dir>` to the game command line).
## Shop and inventory buttons are driven through the same methods the buttons call.

const STEP_TIMEOUT := 25.0

var s: GameSession
var out_dir: String
var _shots: int = 0
var _log: Array[String] = []
var _failures: Array[String] = []


static func requested_dir() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--walkthrough="):
			return arg.trim_prefix("--walkthrough=")
	return ""


func start(session: GameSession, dir: String) -> void:
	s = session
	out_dir = dir
	DirAccess.make_dir_recursive_absolute(dir)
	_run.call_deferred()


func _run() -> void:
	await _frames(90)
	await _shot("inicio")

	_note("1. Ordenador y tienda")
	await _click_point(GameSession.MONITOR_POSITION + Vector3(0.0, 0.3, 0.0))
	if not await _wait_mode(InteractionManager.Mode.SCREEN):
		_finish()
		return
	await _frames(10)
	await _shot("escritorio")
	for item: StringName in [&"rack_12u_open", &"switch_16p_1u", &"server_1u_entry", &"cable_cat6_1m", &"cable_cat6_3m"]:
		s.screen._add_to_cart(item)
	await _frames(5)
	await _shot("tienda_carrito")
	s.screen._buy()
	await _frames(3)
	_note("Compra: " + s.screen._message.text)
	s.screen.show_page(&"orders")
	await _frames(5)
	await _shot("pedidos")
	s.screen._wait_delivery()
	await _frames(5)
	_key(KEY_ESCAPE)
	if not await _wait_mode(InteractionManager.Mode.OVERVIEW):
		_finish()
		return
	await _frames(20)
	await _shot("paquetes_entregados")

	_note("2. Abrir los paquetes")
	while not s.world.packages.is_empty():
		var package_id: int = s.world.packages.keys()[0]
		await _click_point((s.package_views[package_id] as Node3D).global_position + Vector3(0.0, 0.25, 0.0))
		if not await _wait(func() -> bool: return not s.world.packages.has(package_id)):
			_fail("no se abrió el paquete %d (modo %d)" % [package_id, s.interaction.mode])
			_finish()
			return
	await _frames(10)
	await _shot("inventario")

	_note("3. Colocar el rack")
	await _click_point(Vector3(-0.3, 0.0, 0.6)) # step aside first: objects cannot be dropped on the character
	await _wait(func() -> bool: return not s.character.moving)
	var rack := _inventory(&"rack_12u_open")
	s.interaction._on_inventory_item(rack.id)
	# Free floor with room behind the rack (its rear ports must be reachable and visible).
	var spot := s.camera.unproject_position(Vector3(0.9, 0.0, 0.35))
	_motion(spot)
	await _frames(5)
	await _shot("colocando_rack")
	await _click_screen(spot)
	if rack.location != &"placed":
		_fail("el rack no se colocó")
		_finish()
		return
	await _frames(40)

	_note("4. Montar switch y servidor")
	if not await _open(&"rack", rack.id):
		_finish()
		return
	await _shot("rack_cerca")
	var sw := _inventory(&"switch_16p_1u")
	var srv := _inventory(&"server_1u_entry")
	for pair: Array in [[sw, 9], [srv, 5]]:
		s.interaction._start_mount_mode((pair[0] as SimDevice).id)
		await _frames(3)
		await _click_slot(pair[1])
		if (pair[0] as SimDevice).location != &"mounted":
			_fail("%s no se montó" % (pair[0] as SimDevice).display_name())
			_finish()
			return
	await _frames(10)
	await _shot("montados")

	_note("5. Corriente del switch (trasera del rack -> regleta)")
	var strip := s.world.devices_of(&"power")[0]
	await _rack_side(true)
	s.interaction._on_inventory_item(_inventory(&"power_cord_3m").id)
	await _click_port(PortRef.make(sw.id, &"psu", 0))
	await _shot("cable_corriente_pendiente")
	await _leave()
	if not await _open(&"device", strip.id):
		_finish()
		return
	await _click_port(PortRef.make(strip.id, &"outlet", 2))
	await _shot("regleta")

	_note("6. Corriente del servidor (regleta -> trasera del rack)")
	s.interaction._on_inventory_item(_inventory(&"power_cord_3m").id)
	await _click_port(PortRef.make(strip.id, &"outlet", 3))
	await _leave()
	if not await _open(&"rack", rack.id):
		_finish()
		return
	await _rack_side(true)
	await _click_port(PortRef.make(srv.id, &"psu", 0))
	s.interaction._press_power(srv.id)
	if not await _wait(func() -> bool: return srv.is_running() and sw.is_running()):
		_fail("switch/servidor no arrancan: switch %s, servidor %s" % [sw.state, srv.state])
	await _frames(10)
	await _shot("encendidos_trasera")

	_note("7. Cable de red servidor -> switch")
	s.interaction._on_inventory_item(_inventory(&"cable_cat6_1m").id)
	await _click_port(PortRef.make(srv.id, &"lan", 0))
	await _rack_side(false)
	await _click_port(PortRef.make(sw.id, &"lan", 0))
	await _shot("servidor_switch")

	_note("8. Cable de red switch -> router")
	s.interaction._on_inventory_item(_inventory(&"cable_cat6_3m").id)
	await _click_port(PortRef.make(sw.id, &"lan", 1))
	await _leave()
	var router := s.world.devices_of(&"router")[0]
	if not await _open(&"device", router.id):
		_finish()
		return
	await _click_port(PortRef.make(router.id, &"lan", 1))
	await _frames(10)
	await _shot("router")

	_note("9. IP del servidor desde su consola")
	await _leave()
	if not await _open(&"rack", rack.id):
		_finish()
		return
	s.interaction._open_console(srv.id)
	await _frames(5)
	var console := s.interaction.console_terminal()
	console.run_line("ip address add 192.168.1.50/24 dev eth0")
	console.run_line("ip address show eth0")
	await _frames(5)
	await _shot("consola_servidor")
	_key(KEY_ESCAPE)
	await _frames(5)
	await _leave()

	_note("10. Ping desde el PC")
	await _click_point(GameSession.MONITOR_POSITION + Vector3(0.0, 0.3, 0.0))
	if not await _wait_mode(InteractionManager.Mode.SCREEN):
		_finish()
		return
	s.screen.show_page(&"terminal")
	await _frames(5)
	s.screen._terminal.run_line("ping -c 4 192.168.1.50")
	await _frames(5)
	await _shot("ping_desde_pc")
	_key(KEY_ESCAPE)
	await _wait_mode(InteractionManager.Mode.OVERVIEW)
	await _frames(20)
	await _shot("mision_completada")
	_finish()


# ----------------------------------------------------------------- helpers --

func _open(kind: StringName, target_id: int) -> bool:
	var point := s.target_center(kind, target_id)
	await _click_point(point)
	if not await _wait_mode(InteractionManager.Mode.CLOSEUP, 12.0):
		var map := s.get_world_3d().navigation_map
		var from := s.character.global_position
		var stand := s.stand_point(kind, target_id)
		var closest := NavigationServer3D.map_get_closest_point(map, stand)
		var path := NavigationServer3D.map_get_path(map, from, closest, true)
		_note("  diagnóstico: personaje %s · destino %s · punto navegable más cercano %s · ruta de %d puntos que acaba en %s" % [
			from, stand, closest, path.size(), path[path.size() - 1] if not path.is_empty() else Vector3.INF])
		_note("  (el clic en %s no abrió la vista cercana: modo %d; se usa la acción directa)" % [kind, s.interaction.mode])
		s.interaction._begin(kind, target_id)
		if not await _wait_mode(InteractionManager.Mode.CLOSEUP):
			_fail("no se pudo abrir %s %d" % [kind, target_id])
			return false
	await _wait(func() -> bool: return not s.director.busy)
	await _frames(5)
	return true


func _leave() -> void:
	_key(KEY_ESCAPE)
	await _wait_mode(InteractionManager.Mode.OVERVIEW)
	await _frames(5)


func _rack_side(rear: bool) -> void:
	if s.interaction._rack_rear != rear:
		_key(KEY_R)
		await _frames(2)
		await _wait(func() -> bool: return not s.director.busy)
		await _frames(5)


func _click_port(ref: String) -> void:
	var view := s.device_views.get(PortRef.device_id(ref)) as DeviceView
	if view == null or not view.port_areas.has(ref):
		_fail("puerto %s sin vista" % ref)
		return
	var pos := (view.port_areas[ref] as Area3D).global_position
	if s.camera.is_position_behind(pos):
		_fail("puerto %s detrás de la cámara" % ref)
		return
	var before := s.hud._toast.text
	await _click_screen(s.camera.unproject_position(pos))
	var toast := s.hud._toast.text
	_note("  clic en %s -> %s" % [ref, toast if toast != before else "(sin mensaje)"])


func _click_slot(u: int) -> void:
	for area: Area3D in s.interaction._slot_areas:
		if area.get_meta("u") == u:
			await _click_screen(s.camera.unproject_position(area.global_position))
			_note("  montaje U%d -> %s" % [u, s.hud._toast.text])
			return
	_fail("no hay hueco U%d" % u)


func _click_point(point: Vector3) -> void:
	var before := s.hud._toast.text
	await _click_screen(s.camera.unproject_position(point))
	if s.hud._toast.text != before:
		_note("  mensaje: " + s.hud._toast.text)


func _click_screen(screen_pos: Vector2) -> void:
	_motion(screen_pos)
	await _frames(2)
	_button(screen_pos, true)
	await _frames(1)
	_button(screen_pos, false)
	await _frames(3)


func _motion(screen_pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = screen_pos
	e.global_position = screen_pos
	Input.parse_input_event(e)


func _button(screen_pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = screen_pos
	e.global_position = screen_pos
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(e)


func _key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var e := InputEventKey.new()
		e.keycode = keycode
		e.physical_keycode = keycode
		e.pressed = pressed
		Input.parse_input_event(e)


func _inventory(item_id: StringName) -> SimDevice:
	for d: SimDevice in s.world.inventory():
		if d.definition.id == item_id:
			return d
	_fail("%s no está en el inventario" % item_id)
	return null


func _wait_mode(mode: InteractionManager.Mode, timeout: float = STEP_TIMEOUT) -> bool:
	var ok := await _wait(func() -> bool: return s.interaction.mode == mode, timeout)
	if not ok:
		_fail("esperaba el modo %d y sigue en %d" % [mode, s.interaction.mode])
	return ok


func _wait(condition: Callable, timeout: float = STEP_TIMEOUT) -> bool:
	var waited := 0.0
	while not condition.call():
		await get_tree().process_frame
		waited += get_process_delta_time()
		if waited > timeout:
			return false
	return true


func _frames(count: int) -> void:
	for _i: int in count:
		await get_tree().process_frame


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	_shots += 1
	var path := out_dir.path_join("%02d_%s.png" % [_shots, label])
	get_viewport().get_texture().get_image().save_png(path)
	_note("  captura %s" % path.get_file())


func _note(text: String) -> void:
	_log.append(text)
	print("WALK " + text)


func _fail(text: String) -> void:
	_failures.append(text)
	_note("FALLO: " + text)


func _finish() -> void:
	var tracker := s.world.mission
	_note("Misión completada: %s · estado %s" % [tracker.completed, str(tracker.status)])
	_note("Créditos %d · XP %d · nivel %d" % [s.world.credits, s.world.xp, s.world.level()])
	var file := FileAccess.open(out_dir.path_join("walkthrough_log.txt"), FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_log) + "\n")
	print("WALKTHROUGH %s (%d fallos)" % ["OK" if _failures.is_empty() and tracker.completed else "FAILED", _failures.size()])
	get_tree().quit(0 if _failures.is_empty() and tracker.completed else 1)
