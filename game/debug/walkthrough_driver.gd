class_name WalkthroughDriver
extends Node
## Development tool (not part of the game): plays the first mission end to end through the real
## input path only — synthetic mouse and keyboard events, never direct calls:
## 3D clicks at projected positions, clicks on the centre of real buttons, commands typed key by
## key, camera drags with the right / middle button. Saves one screenshot per step and a log.
## Start it with tools\walkthrough.ps1, which adds `-- --walkthrough=<dir> --scenario=<name>`.
##
## Scenarios (where the player puts the rack, docs/TEST_PLAN.md §3):
##   basic    — a good spot (front towards the room).
##   wall     — first against the wall: rejected with the reason; turned 90°: accepted.
##   far      — far from the power strip: placement warns, the power cable does not reach,
##              the loose end is unplugged with a right click and the rack is moved.
##   blocking — closes the way to the computer: "cannot get there", right click moves the rack.
## Every scenario must end with the mission completed.

const STEP_TIMEOUT := 25.0
const SCENARIOS: Array[String] = ["basic", "wall", "far", "blocking"]
const GOOD_SPOT := Vector3(0.9, 0.0, 0.5)
const GOOD_YAW := 270.0
const WALL_SPOT := Vector3(1.3, 0.0, 0.5)
const FAR_SPOT := Vector3(1.45, 0.0, 0.65)
const BLOCK_SPOT := Vector3(-0.35, 0.0, 0.0)
const ASIDE := Vector3(-0.9, 0.0, 1.0) ## Where the character waits while the rack is placed.
const SHOPPING: Array[StringName] = [&"rack_12u_open", &"switch_16p_1u", &"server_1u_entry", &"cable_cat6_1m", &"cable_cat6_3m"]

var s: GameSession
var out_dir: String
var scenario: String = "basic"
var _shots: int = 0
var _log: Array[String] = []
var _failures: Array[String] = []


static func requested_dir() -> String:
	return _arg("--walkthrough=")


static func _arg(prefix: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return ""


func start(session: GameSession, dir: String) -> void:
	s = session
	out_dir = dir
	var requested := _arg("--scenario=")
	if requested != "":
		scenario = requested
	DirAccess.make_dir_recursive_absolute(dir)
	_run.call_deferred()


func _run() -> void:
	if not SCENARIOS.has(scenario):
		_fail("escenario desconocido «%s» (válidos: %s)" % [scenario, ", ".join(SCENARIOS)])
		_finish()
		return
	_note("Escenario: " + scenario)
	await _frames(90)
	await _shot("inicio")
	await _steps()
	_finish()


func _steps() -> void:
	if not await _camera_and_walk():
		return
	if not await _shop():
		return
	if not await _unpack():
		return
	var rack := await _place_rack()
	if rack == null:
		return
	if not await _mount(rack):
		return
	if not await _power(rack):
		return
	if not await _network(rack):
		return
	if not await _server_ip(rack):
		return
	# The mission is validated from the simulated state: it completes as soon as the server
	# has its IP. The centred banner can cover the monitor (1280×720), so close it first,
	# as a player would.
	if not await _end_banner():
		return
	if not await _ping_from_pc():
		return
	await _shot("final")
	if scenario == "wall":
		await _epilogue_pick_up(rack)


## wall, after the mission: the panel buttons that undo everything (the mission stays completed).
func _epilogue_pick_up(rack: SimDevice) -> void:
	_note("11. Epílogo: desconectar todo, desmontar y recoger el rack (botones del panel)")
	if not await _open(&"rack", rack.id):
		return
	if not await _press(_find_button(s.hud._side_box, "Desconectar todos los cables"), "Desconectar todos los cables"):
		return
	if s.world.has_cables_inside(rack):
		_fail("quedan cables en el rack")
		return
	await _press(_find_button(s.hud._side_box, "Recoger rack"), "Recoger rack (con equipos dentro)")
	if rack.location != &"placed" or not s.hud._toast.text.contains("Vacía antes"):
		_fail("recoger un rack con equipos debe rechazarse con el motivo («%s»)" % s.hud._toast.text)
		return
	for _i: int in 2:
		if not await _press(_find_button(s.hud._side_box, "Desmontar"), "Desmontar"):
			return
	if not s.world.mounted_in(rack).is_empty():
		_fail("el rack no quedó vacío")
		return
	await _shot("rack_vacio")
	if not await _press(_find_button(s.hud._side_box, "Recoger rack"), "Recoger rack"):
		return
	await _wait_mode(InteractionManager.Mode.OVERVIEW)
	await _frames(20)
	if rack.location != &"inventory":
		_fail("el rack no volvió al inventario («%s»)" % s.hud._toast.text)
	await _shot("rack_recogido")


# ------------------------------------------------------------------- steps --

func _camera_and_walk() -> bool:
	_note("0. Cámara: arrastrar con el botón derecho gira; después el clic izquierdo sigue caminando")
	var centre := s.get_viewport().get_visible_rect().size / 2.0
	var yaw0 := s.rig.target_yaw_deg
	var pitch0 := s.rig.target_pitch_deg
	await _drag(centre, Vector2(120.0, 30.0), MOUSE_BUTTON_RIGHT)
	var turned := s.rig.target_yaw_deg - yaw0
	_note("  giro %+.1f° · inclinación %+.1f°" % [turned, s.rig.target_pitch_deg - pitch0])
	if absf(turned) < 10.0:
		_fail("arrastrar con el botón derecho no giró la cámara")
	if s.interaction.mode != InteractionManager.Mode.OVERVIEW:
		_fail("el arrastre cambió el modo de interacción a %d" % s.interaction.mode)
	await _frames(30)
	await _shot("camara_girada")
	var toast_before := s.hud._toast.text
	await _click_screen(s.camera.unproject_position(Vector3(0.6, 0.0, 0.9)), MOUSE_BUTTON_RIGHT)
	if s.interaction.mode != InteractionManager.Mode.OVERVIEW or s.hud._toast.text != toast_before:
		_fail("un clic derecho en el suelo hizo algo")
	var target := Vector3(0.6, 0.0, 0.9)
	var start := s.character.global_position
	await _click_point(target)
	if not s.character.moving:
		_fail("tras girar la cámara, el clic izquierdo no hizo caminar al personaje")
		return false
	await _wait(func() -> bool: return not s.character.moving)
	var end := s.character.global_position
	_note("  el personaje caminó de %s a %s" % [_v(start), _v(end)])
	if Vector2(end.x - target.x, end.z - target.z).length() > 0.25:
		_fail("el personaje no llegó al punto pulsado")
	yaw0 = s.rig.target_yaw_deg
	await _drag(centre, Vector2(-120.0, -30.0), MOUSE_BUTTON_MIDDLE)
	_note("  arrastre con el botón central: giro %+.1f°" % (s.rig.target_yaw_deg - yaw0))
	if absf(s.rig.target_yaw_deg - yaw0) < 10.0:
		_fail("arrastrar con el botón central no giró la cámara")
	await _frames(30)
	return true


func _shop() -> bool:
	_note("1. Ordenador y tienda (botones reales)")
	await _click_point(GameSession.MONITOR_POSITION + Vector3(0.0, 0.3, 0.0))
	if not await _wait_mode(InteractionManager.Mode.SCREEN):
		return false
	await _frames(10)
	await _shot("escritorio")
	for item: StringName in SHOPPING:
		var def := s.world.catalog.get_item(item)
		if not await _press(_shop_add_button(def.display_name()), "Añadir " + def.display_name()):
			return false
		await _frames(3)
	await _shot("tienda_carrito")
	if not await _press(_find_button(s.screen, "Comprar"), "Comprar"):
		return false
	_note("  compra: " + s.screen._message.text)
	if s.world.orders.is_empty():
		_fail("no se hizo el pedido")
		return false
	if not await _press(_find_button(s.screen, "Pedidos"), "Pedidos"):
		return false
	await _shot("pedidos")
	if not await _press(_find_button(s.screen, "Esperar hasta la entrega"), "Esperar hasta la entrega"):
		return false
	if not await _press(_find_button(s.screen, "Levantarse (Esc)"), "Levantarse (Esc)"):
		return false
	if not await _wait_mode(InteractionManager.Mode.OVERVIEW):
		return false
	await _frames(20)
	await _shot("paquetes_entregados")
	return true


func _unpack() -> bool:
	_note("2. Abrir los paquetes")
	while not s.world.packages.is_empty():
		var package_id: int = s.world.packages.keys()[0]
		await _click_point((s.package_views[package_id] as Node3D).global_position + Vector3(0.0, 0.25, 0.0))
		if not await _wait(func() -> bool: return not s.world.packages.has(package_id)):
			_fail("no se abrió el paquete %d (modo %d)" % [package_id, s.interaction.mode])
			return false
	await _frames(10)
	await _shot("inventario")
	return true


func _place_rack() -> SimDevice:
	_note("3. Colocar el rack")
	await _click_point(ASIDE) # objects cannot be dropped on the character
	await _wait(func() -> bool: return not s.character.moving)
	var rack := _inventory(&"rack_12u_open")
	if rack == null or not await _press(_find_button(s.hud._inventory_row, rack.display_name()), "inventario: " + rack.display_name()):
		return null
	if not await _wait_mode(InteractionManager.Mode.PLACEMENT, 5.0):
		return null
	match scenario:
		"basic":
			var centre := s.get_viewport().get_visible_rect().size / 2.0
			var yaw0 := s.rig.target_yaw_deg
			await _drag(centre, Vector2(90.0, 0.0), MOUSE_BUTTON_RIGHT)
			if s.interaction.mode != InteractionManager.Mode.PLACEMENT or absf(s.rig.target_yaw_deg - yaw0) < 10.0:
				_fail("arrastrar con el botón derecho mientras se coloca debe girar la cámara sin cancelar (modo %d)" % s.interaction.mode)
			await _drag(centre, Vector2(-90.0, 0.0), MOUSE_BUTTON_RIGHT)
			await _frames(30)
			await _place_at(rack, GOOD_SPOT, GOOD_YAW, "colocando_rack")
		"wall":
			_note("  contra la pared: el frente mira a la pared derecha")
			await _place_at(rack, WALL_SPOT, 90.0, "rechazo_pared")
			if rack.location == &"placed":
				_fail("el rack se colocó sin espacio delante")
				return null
			if not s.hud._toast.text.contains("libres delante y detrás"):
				_fail("el rechazo no explica el motivo: «%s»" % s.hud._toast.text)
			_note("  girado 90°: el frente mira a la habitación")
			await _place_at(rack, WALL_SPOT, 180.0, "colocando_rack")
		"far":
			var preview := await _place_at(rack, FAR_SPOT, 0.0, "aviso_lejos")
			if not preview.contains("Lejos de la regleta"):
				_fail("la vista previa no avisa de que queda lejos de la regleta")
		"blocking":
			await _place_at(rack, BLOCK_SPOT, 0.0, "colocando_rack")
	if rack.location != &"placed":
		_fail("el rack no se colocó: «%s»" % s.hud._toast.text)
		return null
	await _frames(40)
	if scenario == "blocking" and not await _blocked_then_move(rack):
		return null
	return rack


## blocking: the rack closes the way to the computer; a right click on it moves it (no walking).
func _blocked_then_move(rack: SimDevice) -> bool:
	_note("3b. El rack cierra el paso al ordenador")
	await _click_point(GameSession.MONITOR_POSITION + Vector3(0.0, 0.3, 0.0))
	await _frames(10)
	if s.interaction.mode != InteractionManager.Mode.OVERVIEW or not s.hud._toast.text.contains("No puedo llegar"):
		_fail("el rack no bloqueó el paso (modo %d, mensaje «%s»)" % [s.interaction.mode, s.hud._toast.text])
		return false
	await _shot("paso_bloqueado")
	_note("3c. Clic derecho en el rack: moverlo sin caminar")
	await _click_point(s.target_center(&"rack", rack.id), MOUSE_BUTTON_RIGHT)
	if not await _wait_mode(InteractionManager.Mode.PLACEMENT, 5.0):
		return false
	await _place_at(rack, GOOD_SPOT, GOOD_YAW, "rack_movido")
	if rack.position.distance_to(GOOD_SPOT) > 0.03:
		_fail("el rack no se movió: «%s»" % s.hud._toast.text)
		return false
	await _frames(40)
	return true


func _mount(rack: SimDevice) -> bool:
	_note("4. Montar switch y servidor (botones del panel)")
	if not await _open(&"rack", rack.id):
		return false
	await _shot("rack_cerca")
	for pair: Array in [[&"switch_16p_1u", 9], [&"server_1u_entry", 5]]:
		var d := _inventory(pair[0])
		if d == null or not await _press(_find_button(s.hud._side_box, d.display_name()), "Montar " + d.display_name()):
			return false
		await _click_slot(pair[1])
		if d.location != &"mounted":
			_fail("%s no se montó" % d.display_name())
			return false
	await _frames(10)
	await _shot("montados")
	return true


func _power(rack: SimDevice) -> bool:
	var sw := _mounted(rack, &"switch_16p_1u")
	var srv := _mounted(rack, &"server_1u_entry")
	var strip := s.world.devices_of(&"power")[0]
	if scenario == "far" and not await _far_power_then_move(rack, sw, strip):
		return false
	_note("5. Corriente del switch (trasera del rack -> regleta)")
	if not await _ensure_rack_closeup(rack):
		return false
	await _rack_side(true)
	if not await _choose_cable(&"power_cord_3m"):
		return false
	await _click_port(PortRef.make(sw.id, &"psu", 0))
	await _shot("cable_corriente_pendiente")
	await _leave()
	if not await _open(&"device", strip.id):
		return false
	await _click_port(PortRef.make(strip.id, &"outlet", 2))
	await _shot("regleta")
	if not s.world.is_powered(sw):
		_fail("el switch no recibe corriente: «%s»" % s.hud._toast.text)
		return false

	_note("6. Corriente del servidor (regleta -> trasera del rack) y botón Encender")
	if not await _choose_cable(&"power_cord_3m"):
		return false
	await _click_port(PortRef.make(strip.id, &"outlet", 3))
	await _leave()
	if not await _open(&"rack", rack.id):
		return false
	await _rack_side(true)
	await _click_port(PortRef.make(srv.id, &"psu", 0))
	if not await _press(_find_button(s.hud._side_box, "Encender"), "Encender"):
		return false
	if not await _wait(func() -> bool: return srv.is_running() and sw.is_running()):
		_fail("switch/servidor no arrancan: switch %s, servidor %s" % [sw.state, srv.state])
		return false
	await _frames(10)
	await _shot("encendidos_trasera")
	return true


## far: the power cable does not reach; unplug the loose end (right click) and move the rack
## with the panel button.
func _far_power_then_move(rack: SimDevice, sw: SimDevice, strip: SimDevice) -> bool:
	_note("5a. El cable de corriente no llega a la regleta")
	await _rack_side(true)
	if not await _choose_cable(&"power_cord_3m"):
		return false
	var psu := PortRef.make(sw.id, &"psu", 0)
	await _click_port(psu)
	await _leave()
	if not await _open(&"device", strip.id):
		return false
	await _click_port(PortRef.make(strip.id, &"outlet", 2))
	if not s.hud._toast.text.contains("no llega"):
		_fail("esperaba «el cable no llega» y el mensaje es «%s»" % s.hud._toast.text)
		return false
	await _shot("cable_no_llega")
	await _leave()
	_note("5b. Clic derecho en el extremo conectado y «Mover rack»")
	if not await _open(&"rack", rack.id):
		return false
	await _rack_side(true)
	await _click_port(psu, MOUSE_BUTTON_RIGHT)
	if s.world.port_cable.has(psu):
		_fail("el clic derecho no desconectó el extremo suelto")
		return false
	if not await _press(_find_button(s.hud._side_box, "Mover rack"), "Mover rack"):
		return false
	if not await _wait_mode(InteractionManager.Mode.PLACEMENT):
		return false
	await _place_at(rack, GOOD_SPOT, GOOD_YAW, "rack_movido")
	if rack.position.distance_to(GOOD_SPOT) > 0.03 or sw.location != &"mounted":
		_fail("el rack no se movió con el switch montado: «%s»" % s.hud._toast.text)
		return false
	await _frames(40)
	return true


func _network(rack: SimDevice) -> bool:
	var sw := _mounted(rack, &"switch_16p_1u")
	var srv := _mounted(rack, &"server_1u_entry")
	_note("7. Cable de red servidor -> switch")
	if not await _choose_cable(&"cable_cat6_1m"):
		return false
	await _click_port(PortRef.make(srv.id, &"lan", 0))
	await _press(_find_button(s.hud._side_box, "Ver cara frontal (R)"), "Ver cara frontal (R)")
	await _wait(func() -> bool: return not s.director.busy)
	await _frames(5)
	await _click_port(PortRef.make(sw.id, &"lan", 0))
	await _shot("servidor_switch")

	_note("8. Cable de red switch -> router")
	if not await _choose_cable(&"cable_cat6_3m"):
		return false
	await _click_port(PortRef.make(sw.id, &"lan", 1))
	await _leave()
	var router := s.world.devices_of(&"router")[0]
	if not await _open(&"device", router.id):
		return false
	await _click_port(PortRef.make(router.id, &"lan", 1))
	await _frames(10)
	await _shot("router")
	var link := NetworkEngine.port_link(s.world, PortRef.make(router.id, &"lan", 1))
	if not link["up"]:
		_fail("sin enlace switch-router: %s" % link["reason"])
		return false
	return true


func _server_ip(rack: SimDevice) -> bool:
	_note("9. IP del servidor: botón Consola y órdenes tecleadas")
	await _leave()
	if not await _open(&"rack", rack.id):
		return false
	if not await _press(_find_button(s.hud._side_box, "Consola"), "Consola"):
		return false
	await _frames(5)
	var console := s.interaction.console_terminal()
	if console == null:
		_fail("no se abrió la consola")
		return false
	await _type_line(console, "ip address add 192.168.1.50/24 dev eth0")
	await _type_line(console, "ip address show eth0")
	await _frames(5)
	await _shot("consola_servidor")
	# The echo of the command line also contains the address: look for the output line.
	if not console.output.get_parsed_text().contains("inet 192.168.1.50/24 scope global eth0"):
		_fail("«ip address show eth0» no muestra la IP nueva")
		return false
	_key(KEY_ESCAPE)
	await _frames(5)
	await _leave()
	return true


func _ping_from_pc() -> bool:
	_note("10. Ping desde el PC: aplicación Terminal y orden tecleada")
	await _click_point(GameSession.MONITOR_POSITION + Vector3(0.0, 0.3, 0.0))
	if not await _wait_mode(InteractionManager.Mode.SCREEN):
		return false
	if not await _press(_find_button(s.screen, "Terminal"), "Terminal"):
		return false
	await _frames(5)
	await _type_line(s.screen._terminal, "ping -c 4 192.168.1.50")
	await _frames(5)
	await _shot("ping_desde_pc")
	if not s.screen._terminal.output.get_parsed_text().contains("64 bytes from 192.168.1.50"):
		_fail("el ping no respondió")
	_key(KEY_ESCAPE)
	await _wait_mode(InteractionManager.Mode.OVERVIEW)
	await _frames(20)
	return true


func _end_banner() -> bool:
	if not await _wait(func() -> bool: return s.hud._banner.visible, 5.0):
		_fail("no apareció el cartel de misión completada")
		return false
	await _frames(5)
	await _shot("mision_completada")
	return await _press(_find_button(s.hud, "Seguir jugando"), "Seguir jugando")


# ----------------------------------------------------------------- helpers --

## Rotates the ghost with R to `yaw`, points at `spot` and clicks. Returns the preview text.
func _place_at(rack: SimDevice, spot: Vector3, yaw: float, shot_label: String) -> String:
	for _i: int in 4:
		if is_equal_approx(s.interaction._ghost_yaw, yaw):
			break
		_key(KEY_R)
		await _frames(2)
	var screen := s.camera.unproject_position(spot)
	_motion(screen)
	await _frames(5)
	var preview := s.hud._tool.text
	_note("  vista previa en %s, %d°: %s" % [_v(spot), int(yaw), preview.replace("\n", " | ")])
	await _shot(shot_label)
	await _click_screen(screen)
	_note("  -> %s" % s.hud._toast.text)
	if rack.location == &"placed" and rack.position.distance_to(spot) > 0.03:
		_note("  (colocado en %s, no en %s)" % [_v(rack.position), _v(spot)])
	return preview


func _ensure_rack_closeup(rack: SimDevice) -> bool:
	if s.interaction.mode == InteractionManager.Mode.CLOSEUP and s.interaction._closeup_device == rack.id:
		return true
	if s.interaction.mode != InteractionManager.Mode.OVERVIEW:
		await _leave()
	return await _open(&"rack", rack.id)


## Opens a close-up with a real click. If the click does not work it is a failure; the direct
## action is then used only to keep collecting information for the rest of the run.
func _open(kind: StringName, target_id: int) -> bool:
	await _click_point(s.target_center(kind, target_id))
	if not await _wait(func() -> bool: return s.interaction.mode == InteractionManager.Mode.CLOSEUP, 12.0):
		var map := s.get_world_3d().navigation_map
		var from := s.character.global_position
		var stand := s.stand_point(kind, target_id)
		var closest := NavigationServer3D.map_get_closest_point(map, stand)
		var path := NavigationServer3D.map_get_path(map, from, closest, true)
		_fail("el clic en %s %d no abrió la vista cercana (modo %d, mensaje «%s»)" % [kind, target_id, s.interaction.mode, s.hud._toast.text])
		_note("  diagnóstico: personaje %s · destino %s · punto navegable más cercano %s · ruta de %d puntos que acaba en %s" % [
			_v(from), _v(stand), _v(closest), path.size(), _v(path[path.size() - 1]) if not path.is_empty() else "-"])
		s.interaction._begin(kind, target_id)
		if not await _wait_mode(InteractionManager.Mode.CLOSEUP):
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


## Presses the inventory button of a cable (real click) and checks it became the selected cable.
func _choose_cable(item_id: StringName) -> bool:
	var label := s.world.catalog.get_item(item_id).model
	if not await _press(_find_button(s.hud._inventory_row, label), "inventario: " + label):
		return false
	var chosen := s.world.get_device(s.interaction.selected_cable)
	if chosen == null or chosen.definition.id != item_id:
		_fail("el botón «%s» no eligió ese cable" % label)
		return false
	return true


func _click_port(ref: String, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var view := s.device_views.get(PortRef.device_id(ref)) as DeviceView
	if view == null or not view.port_areas.has(ref):
		_fail("puerto %s sin vista" % ref)
		return
	var pos := (view.port_areas[ref] as Area3D).global_position
	if s.camera.is_position_behind(pos):
		_fail("puerto %s detrás de la cámara" % ref)
		return
	var before := s.hud._toast.text
	await _click_screen(s.camera.unproject_position(pos), button)
	var toast := s.hud._toast.text
	_note("  %s en %s -> %s" % ["clic derecho" if button == MOUSE_BUTTON_RIGHT else "clic", ref, toast if toast != before else "(sin mensaje)"])


func _click_slot(u: int) -> void:
	for area: Area3D in s.interaction._slot_areas:
		if area.get_meta("u") == u:
			await _click_screen(s.camera.unproject_position(area.global_position))
			_note("  montaje U%d -> %s" % [u, s.hud._toast.text])
			return
	_fail("no hay hueco U%d" % u)


func _click_point(point: Vector3, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var before := s.hud._toast.text
	await _click_screen(s.camera.unproject_position(point), button)
	if s.hud._toast.text != before:
		_note("  mensaje: " + s.hud._toast.text)


func _click_screen(screen_pos: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	_motion(screen_pos)
	await _frames(2)
	_mouse_button(screen_pos, button, true)
	await _frames(1)
	_mouse_button(screen_pos, button, false)
	await _frames(3)


## Clicks the centre of a real button and checks that it emitted `pressed`.
func _press(b: BaseButton, label: String) -> bool:
	if b == null:
		_fail("no encuentro el botón «%s»" % label)
		return false
	await _frames(2) # let containers lay it out
	var scroll := _scroll_parent(b)
	if scroll != null:
		scroll.ensure_control_visible(b) # what the player does with the mouse wheel
		await _frames(2)
	if not b.is_visible_in_tree() or b.disabled:
		_fail("el botón «%s» no está disponible" % label)
		return false
	var pressed := [false]
	var on_pressed := func() -> void: pressed[0] = true
	b.pressed.connect(on_pressed)
	await _click_screen(b.get_global_rect().get_center())
	if is_instance_valid(b) and b.pressed.is_connected(on_pressed):
		b.pressed.disconnect(on_pressed)
	if not pressed[0]:
		var vp := get_viewport()
		var hovered: Variant = vp.call(&"gui_get_hovered_control") if vp.has_method(&"gui_get_hovered_control") else null
		_fail("el clic no pulsó el botón «%s» (rect %s, válido %s, bajo el ratón: %s)" % [label,
			b.get_global_rect() if is_instance_valid(b) else "-", is_instance_valid(b), hovered])
		return false
	_note("  botón «%s»" % label)
	return true


func _find_button(root: Node, text: String) -> Button:
	for node: Node in root.find_children("*", "Button", true, false):
		var b := node as Button
		if b.text == text and b.is_visible_in_tree() and not b.is_queued_for_deletion():
			return b
	return null


## The «Añadir» button of the shop card whose title is `product`.
func _shop_add_button(product: String) -> Button:
	for node: Node in s.screen.find_children("*", "Label", true, false):
		var label := node as Label
		if label.text == product and label.is_visible_in_tree() and not label.is_queued_for_deletion():
			return _find_button(label.get_parent().get_parent(), "Añadir")
	return null


func _scroll_parent(control: Control) -> ScrollContainer:
	var node := control.get_parent()
	while node != null:
		if node is ScrollContainer:
			return node
		node = node.get_parent()
	return null


## Types a line key by key into a terminal (it must have the keyboard focus) and presses Enter.
func _type_line(terminal: TerminalView, text: String) -> void:
	await _frames(2)
	if not terminal.input.has_focus():
		_fail("la línea de órdenes no tiene el foco del teclado")
		terminal.input.grab_focus()
	for ch: String in text:
		var key := _key_for(ch)
		for pressed: bool in [true, false]:
			var e := InputEventKey.new()
			e.keycode = key
			e.physical_keycode = key
			e.unicode = ch.unicode_at(0)
			e.pressed = pressed
			Input.parse_input_event(e)
		await _frames(1)
	_key(KEY_ENTER)
	await _frames(3)
	var history := terminal.shell.history
	if history.is_empty() or history[history.size() - 1] != text:
		_fail("la orden tecleada no llegó al shell: «%s» (última: «%s»)" % [text, history[history.size() - 1] if not history.is_empty() else ""])
	_note("  tecleado: %s" % text)


## Key of a US keyboard that types `ch` (letters and digits share their ASCII code with Key).
static func _key_for(ch: String) -> Key:
	match ch:
		" ":
			return KEY_SPACE
		".":
			return KEY_PERIOD
		"/":
			return KEY_SLASH
		"-":
			return KEY_MINUS
	return ch.to_upper().unicode_at(0) as Key


func _drag(from: Vector2, delta: Vector2, button: MouseButton) -> void:
	_motion(from)
	await _frames(2)
	_mouse_button(from, button, true)
	await _frames(2)
	var steps := 10
	for i: int in steps:
		var e := InputEventMouseMotion.new()
		e.position = from + delta * float(i + 1) / steps
		e.global_position = e.position
		e.relative = delta / steps
		e.button_mask = _mask(button)
		Input.parse_input_event(e)
		await _frames(1)
	_mouse_button(from + delta, button, false)
	await _frames(3)


func _motion(screen_pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = screen_pos
	e.global_position = screen_pos
	Input.parse_input_event(e)


func _mouse_button(screen_pos: Vector2, button: MouseButton, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = screen_pos
	e.global_position = screen_pos
	e.button_index = button
	e.pressed = pressed
	e.button_mask = _mask(button) if pressed else 0
	Input.parse_input_event(e)


static func _mask(button: MouseButton) -> int:
	match button:
		MOUSE_BUTTON_RIGHT:
			return MOUSE_BUTTON_MASK_RIGHT
		MOUSE_BUTTON_MIDDLE:
			return MOUSE_BUTTON_MASK_MIDDLE
	return MOUSE_BUTTON_MASK_LEFT


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


func _mounted(rack: SimDevice, item_id: StringName) -> SimDevice:
	for d: SimDevice in s.world.mounted_in(rack):
		if d.definition.id == item_id:
			return d
	return null


func _wait_mode(mode: InteractionManager.Mode, timeout: float = STEP_TIMEOUT) -> bool:
	var ok := await _wait(func() -> bool: return s.interaction.mode == mode, timeout)
	if not ok:
		_fail("esperaba el modo %d y sigue en %d (mensaje «%s»)" % [mode, s.interaction.mode, s.hud._toast.text])
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


static func _v(p: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [p.x, p.y, p.z]


func _note(text: String) -> void:
	_log.append(text)
	print("WALK " + text)


func _fail(text: String) -> void:
	_failures.append(text)
	_note("FALLO: " + text)


func _finish() -> void:
	var tracker := s.world.mission
	var ok := _failures.is_empty() and tracker.completed
	_note("Misión completada: %s · estado %s" % [tracker.completed, str(tracker.status)])
	_note("Créditos %d · XP %d · nivel %d" % [s.world.credits, s.world.xp, s.world.level()])
	var file := FileAccess.open(out_dir.path_join("walkthrough_log.txt"), FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_log) + "\n")
	print("WALKTHROUGH %s %s (%d fallos)" % [scenario, "OK" if ok else "FAILED", _failures.size()])
	get_tree().quit(0 if ok else 1)
