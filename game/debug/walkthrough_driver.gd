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
##   blocking — closes a corner of the room: "cannot get there", right click moves the rack;
##              then the three ways to the desk chair are blocked: "cannot reach the chair".
##   manual   — the basic game, taking the annotated screenshots of the in-game manual
##              (res://assets/manual/*.png).
## Also checked: camera drags, menu (Controls, manual, save / load, also while seated), sitting
## and standing up repeatedly, walking through narrow spaces, the planted foot not sliding,
## deliveries in several orders, invalid placements, every drawn cable against the colliders
## with its radius, no object inside another, click rings (red on a useless click), the shop
## product page and basket, the cable guide (steps, glowing sockets, arrows) and its
## cancellation by other work or Esc, passive income, "Mi cuenta" and second-hand selling.
## Every scenario must end with the mission completed.

const STEP_TIMEOUT := 25.0
const SCENARIOS: Array[String] = ["basic", "wall", "far", "blocking", "manual"]
const MANUAL_DIR := "res://assets/manual"
const MANUAL_SIZE := Vector2i(1280, 720)
const MARK := Color("#3CC8D8")
const POCKET := Vector3(-0.35, 0.0, -0.56) ## Floor in front of the PC tower, closed by BLOCK_SPOT.
const GOOD_SPOT := Vector3(0.2, 0.0, 0.6)
const GOOD_YAW := 0.0 ## Front to the room, rear (power sockets) towards the desk: the 3 m cords reach the strip.
const WALL_SPOT := Vector3(1.2, 0.0, 0.5)
const FAR_SPOT := Vector3(1.45, 0.0, 0.65)
const BLOCK_SPOT := Vector3(-0.35, 0.0, 0.0)
const ASIDE := Vector3(-1.35, 0.0, 0.85) ## Where the character waits while the rack is placed (by the door, outside the delivery zone).
## The uplink to the router follows the floor: about 3.1 m from the good spot, so the 5 m cable.
const SHOPPING: Array[StringName] = [&"rack_12u_open", &"switch_16p_1u", &"server_1u_entry", &"cable_cat6_1m", &"cable_cat6_5m"]

signal session_attached

const SAVE_SLOT := "user://saves/walkthrough.json" ## Never the player's save file.

static var _instance: WalkthroughDriver = null

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


## Called by every GameSession that starts with --walkthrough. The driver lives under the tree
## root, so it survives loading a game (which rebuilds the scene) and follows the new session.
static func attach(session: GameSession) -> void:
	if _instance != null:
		_instance.s = session
		_instance.session_attached.emit()
		return
	_instance = WalkthroughDriver.new()
	_instance.name = "WalkthroughDriver"
	_instance.process_mode = Node.PROCESS_MODE_ALWAYS # keeps working while a menu pauses the game
	_instance.s = session
	_instance.out_dir = requested_dir()
	var requested := _arg("--scenario=")
	if requested != "":
		_instance.scenario = requested
	SaveService.slot_path = SAVE_SLOT
	for path: String in [SAVE_SLOT, SAVE_SLOT + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.make_dir_recursive_absolute(_instance.out_dir)
	session.get_tree().root.add_child.call_deferred(_instance)
	_instance._run.call_deferred()


func _run() -> void:
	if not SCENARIOS.has(scenario):
		_fail("escenario desconocido «%s» (válidos: %s)" % [scenario, ", ".join(SCENARIOS)])
		_finish()
		return
	_note("Escenario: " + scenario)
	await _frames(90)
	await _shot("inicio")
	await _manual("01_vista_general", [_hud_rect(s.hud._credits), _hud_rect(s.hud._mission_title), _hud_rect(s.hud._inventory_row)])
	await _steps()
	_finish()


func _steps() -> void:
	if not await _camera_and_walk():
		return
	if not await _menu_controls_and_manual():
		return
	if not await _shop():
		return
	if not await _unpack():
		return
	var rack := await _place_rack()
	if rack == null:
		return
	if scenario == "basic" and not await _narrow_walks():
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
	await _manual("17_cables_suelo")
	if scenario in ["basic", "manual"] and not await _economy():
		return
	match scenario:
		"wall":
			await _epilogue_pick_up(rack)
		"basic":
			if await _sit_stand_repeatedly(3):
				await _save_and_load(rack.id)
		"blocking":
			await _chair_blocked()
		"manual":
			await _manual_epilogue()


## After the mission: the server earns passive income (seen in the HUD, paid on the hour), the
## account lists every movement, and the second-hand market buys the spare cable for less.
func _economy() -> bool:
	_note("10b. Economía: ingresos pasivos, Mi cuenta y Segunda mano")
	await _frames(10)
	var rate := s.world.economy.passive_rate(s.world)
	_note("  ingresos pasivos: %d cr/h · HUD «%s»" % [rate, s.hud._income.text])
	if rate <= 0 or not s.hud._income.text.contains("cr/h"):
		_fail("con el servidor en línea no hay ingresos pasivos o el HUD no los muestra")
	var before := s.world.credits
	if not await _press(s.hud._speed_buttons[4.0], "×4"):
		return false
	var paid := await _wait(func() -> bool: return s.world.credits > before, 40.0)
	await _press(s.hud._speed_buttons[1.0], "×1")
	if not paid:
		_fail("en una hora de juego el servidor en línea no pagó nada")
	_note("  cobrado: %d -> %d cr" % [before, s.world.credits])
	await _shot("ingreso_pasivo")
	await _manual("25_ingresos", [_hud_rect(s.hud._credits), _hud_rect(s.hud._income)])
	await _click_point(GameSession.MONITOR_POSITION + Vector3(0.0, 0.3, 0.0), MOUSE_BUTTON_LEFT, _is_computer)
	if not await _wait_mode(InteractionManager.Mode.SCREEN):
		return false
	if not await _press(_find_button(s.screen, "Mi cuenta"), "Mi cuenta"):
		return false
	await _frames(5)
	var ledger := s.screen.account.find_child("Ledger", true, false) as GridContainer
	var rows := ledger.get_child_count() / 4 - 1 if ledger != null else 0
	_note("  Mi cuenta: %d movimientos" % rows)
	if rows < 4:
		_fail("Mi cuenta no lista los movimientos (%d)" % rows)
	await _shot("mi_cuenta")
	await _manual("26_mi_cuenta", [ledger.get_global_rect() if ledger != null else Rect2()])
	if not await _press(_find_button(s.screen, "Segunda mano"), "Segunda mano"):
		return false
	await _frames(5)
	var spare := _inventory(&"cable_cat6_3m")
	if spare == null:
		return false
	var row := s.screen.market.find_child("Sell_%d" % spare.id, true, false)
	await _manual("27_segunda_mano", [_rect_of(_find_button(row, "Vender")) if row != null else Rect2()])
	if row == null or not await _press(_find_button(row, "Vender"), "Vender"):
		return false
	await _frames(3)
	row = s.screen.market.find_child("Sell_%d" % spare.id, true, false)
	before = s.world.credits
	if row == null or not await _press(_find_button(row, "Sí, vender"), "Sí, vender"):
		return false
	var expected := s.world.catalog.get_item(&"cable_cat6_3m").price * s.world.economy.rules.resale_unused_percent / 100
	_note("  venta: %s" % s.screen.market.status_text())
	if s.world.credits - before != expected or spare.location != &"sold":
		_fail("la venta no pagó %d cr (%d -> %d)" % [expected, before, s.world.credits])
	await _shot("segunda_mano_vendido")
	_key(KEY_ESCAPE)
	await _wait_mode(InteractionManager.Mode.OVERVIEW)
	await _wait(func() -> bool: return not s.character.busy, 5.0)
	return true


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
	await _manual("03_camara", [_hud_rect(s.hud._hint)])
	var toast_before := s.hud._toast.text
	await _click_screen(s.camera.unproject_position(Vector3(0.6, 0.0, 0.9)), MOUSE_BUTTON_RIGHT)
	if s.interaction.mode != InteractionManager.Mode.OVERVIEW or s.hud._toast.text != toast_before:
		_fail("un clic derecho en el suelo hizo algo")
	if s.click_fx.ring_count() == 0:
		_fail("el clic no dejó ningún anillo bajo el cursor")
	# A click on nothing (outside the room): the ring turns red with a cross.
	await _click_screen(Vector2(30.0, s.get_viewport().get_visible_rect().size.y * 0.5))
	if not s.click_fx.last_ring_rejected():
		_fail("un clic en el vacío no se marcó como inútil")
	await _shot("clic_en_el_vacio")
	# A long straight walk: the foot on the floor must not slide (measured on the real model).
	var target := Vector3(-1.2, 0.0, 0.85)
	var start := s.character.global_position
	await _click_point(target)
	if not s.character.moving:
		_fail("tras girar la cámara, el clic izquierdo no hizo caminar al personaje")
		return false
	var anim := s.character.animator
	var drift := 0.0
	var planted := {}
	var shot_taken := false
	var waited := 0.0
	while s.character.moving and waited < STEP_TIMEOUT:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if not shot_taken and waited > 0.6:
			shot_taken = true
			await _manual("02_caminar", [], [s.camera.unproject_position(target), s.camera.unproject_position(s.character.global_position + Vector3(0, 0.9, 0))])
		if anim.walk_weight < 0.99:
			planted.clear()
			continue
		for side: String in ["L", "R"]:
			var p := anim.foot_position(side)
			if anim.in_stance(side):
				if not planted.has(side):
					planted[side] = p
				drift = maxf(drift, Vector2(p.x - (planted[side] as Vector3).x, p.z - (planted[side] as Vector3).z).length())
			else:
				planted.erase(side)
	var end := s.character.global_position
	_note("  el personaje caminó de %s a %s · el pie apoyado se desplazó como máximo %.1f cm" % [_v(start), _v(end), drift * 100.0])
	if Vector2(end.x - target.x, end.z - target.z).length() > 0.25:
		_fail("el personaje no llegó al punto pulsado")
	if drift > 0.04:
		_fail("el pie apoyado se desliza %.1f cm" % (drift * 100.0))
	yaw0 = s.rig.target_yaw_deg
	await _drag(centre, Vector2(-120.0, -30.0), MOUSE_BUTTON_MIDDLE)
	_note("  arrastre con el botón central: giro %+.1f°" % (s.rig.target_yaw_deg - yaw0))
	if absf(s.rig.target_yaw_deg - yaw0) < 10.0:
		_fail("arrastrar con el botón central no giró la cámara")
	await _frames(30)
	return true


func _shop() -> bool:
	_note("1. Sentarse al ordenador y comprar (botones reales)")
	await _click_point(GameSession.MONITOR_POSITION + Vector3(0.0, 0.3, 0.0), MOUSE_BUTTON_LEFT, _is_computer)
	if not await _wait(func() -> bool: return s.character.seated, 20.0):
		_fail("el personaje no se sentó en la silla (modo %d, mensaje «%s»)" % [s.interaction.mode, s.hud._toast.text])
		return false
	await _manual("05_sentado", [], [s.camera.unproject_position(s.room.chair.global_position + Vector3(0, 0.8, 0))])
	if not await _wait_mode(InteractionManager.Mode.SCREEN):
		return false
	await _frames(10)
	await _shot("escritorio")
	if not await _shop_product_page():
		return false
	# wall: two orders in a row (several deliveries) and the long power cords that spot needs;
	# manual: one cable more for its last pictures; basic: a cable to sell later.
	var orders: Array = [SHOPPING]
	if scenario == "wall":
		orders = [[&"rack_12u_open", &"switch_16p_1u"], [&"server_1u_entry", &"cable_cat6_1m", &"cable_cat6_5m", &"power_cord_5m", &"power_cord_5m"]]
	elif scenario in ["manual", "basic"]:
		var more: Array[StringName] = SHOPPING.duplicate()
		more.append(&"cable_cat6_3m") # the spare cable sold second hand after the mission
		if scenario == "manual":
			more.append(&"cable_cat6_1m")
		orders = [more]
	var spent := 0
	var before := s.world.credits
	for order: Array in orders:
		if s.screen.shop.page != &"list" and not await _press(_find_link(s.screen.shop, "◀ Seguir comprando"), "Seguir comprando"):
			return false
		for item: StringName in order:
			var def := s.world.catalog.get_item(item)
			if not await _press(_shop_add_button(item), "Añadir a la cesta: " + def.display_name()):
				return false
			spent += def.price
			await _frames(3)
		await _shot("tienda_catalogo")
		await _manual("06_tienda", [_rect_of(_shop_add_button(&"rack_12u_open")), _rect_of(s.screen.shop._cart_button)])
		if not await _press(s.screen.shop._cart_button, "Cesta"):
			return false
		await _frames(5)
		await _shot("tienda_cesta")
		var pay := s.screen.shop.find_child("Pay", true, false) as Button
		await _manual("06c_cesta", [_rect_of(pay)])
		if not await _press(pay, "Tramitar pedido"):
			return false
		_note("  compra: " + s.screen.shop.status_text())
	if s.world.orders.size() != orders.size():
		_fail("se esperaban %d pedidos y hay %d" % [orders.size(), s.world.orders.size()])
		return false
	if s.world.credits != before - spent:
		_fail("el saldo no bajó lo que costó el pedido: %d -> %d (%d)" % [before, s.world.credits, spent])
	var floats := s.hud._root.get_children().filter(func(n: Node) -> bool: return n.has_meta("float_delta"))
	_note("  saldo %d -> %d · avisos flotantes en el HUD: %d" % [before, s.world.credits, floats.size()])
	if not await _press(_find_button(s.screen, "Pedidos"), "Pedidos"):
		return false
	await _shot("pedidos")
	await _manual("07_pedidos", [_rect_of(_find_button(s.screen, "Esperar hasta la entrega"))])
	await _manual("08_levantarse", [_rect_of(_find_button(s.screen, "Menú")), _rect_of(_find_button(s.screen, "Levantarse (Esc)"))])
	# One press per delivery still on its way.
	while _find_button(s.screen, "Esperar hasta la entrega") != null:
		if not await _press(_find_button(s.screen, "Esperar hasta la entrega"), "Esperar hasta la entrega"):
			return false
		await _frames(3)
	if not await _press(_find_button(s.screen, "Levantarse (Esc)"), "Levantarse (Esc)"):
		return false
	if not await _wait_mode(InteractionManager.Mode.OVERVIEW):
		return false
	_check_standing("tras levantarse del ordenador")
	await _frames(20)
	await _shot("paquetes_entregados")
	await _manual("09_pila_entregas", [], [s.camera.unproject_position(s.package_stack.global_position + Vector3(0, 0.5, 0))])
	return true


## After standing up: free, on the floor, collision back on, chair back facing the desk.
func _check_standing(label: String) -> void:
	var c := s.character
	if c.seated or c.busy:
		_fail("%s: el personaje sigue sentado" % label)
	if c._shape.disabled:
		_fail("%s: la colisión del personaje sigue desactivada" % label)
	if not c.capsule_fits(c.global_position):
		_fail("%s: el personaje queda dentro de algo en %s" % [label, _v(c.global_position)])
	var closest := NavigationServer3D.map_get_closest_point(s.get_world_3d().navigation_map, c.global_position)
	if Vector2(closest.x - c.global_position.x, closest.z - c.global_position.z).length() > 0.12:
		_fail("%s: el personaje queda fuera del suelo transitable en %s" % [label, _v(c.global_position)])
	if absf(angle_difference(s.room.chair.rotation.y, deg_to_rad(RoomView.CHAIR_REST_YAW))) > 0.03:
		_fail("%s: la silla no volvió a mirar al escritorio" % label)


func _unpack() -> bool:
	_note("2. Abrir las cajas de la pila de entregas (el contador baja con cada una)")
	var expected := s.world.packages.size()
	while expected > 0:
		var shown := s.package_stack.label.text
		if shown != "×%d" % expected or not s.package_stack.visible:
			_fail("el contador de la pila muestra «%s» y hay %d cajas" % [shown, expected])
		var stack_rect := Rect2(s.world.delivery_zone.position, s.world.delivery_zone.size)
		var p := s.package_stack.global_position
		if not stack_rect.has_point(Vector2(p.x, p.z)):
			_fail("la pila no está en la zona de entregas: %s" % _v(p))
		await _click_point(s.target_center(&"package", -1), MOUSE_BUTTON_LEFT, _is_package_stack)
		if not await _wait(func() -> bool: return s.world.packages.size() < expected):
			_fail("no se abrió ninguna caja (modo %d, mensaje «%s»)" % [s.interaction.mode, s.hud._toast.text])
			return false
		expected -= 1
		await _frames(3)
	await _frames(10)
	if s.package_stack.visible:
		_fail("la pila sigue visible sin cajas")
	await _shot("inventario")
	await _manual("10_inventario", [_hud_rect(s.hud._inventory_row)])
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
		"manual":
			await _invalid_spot(rack, Vector3(-0.45, 0.0, 0.8), 0.0, "reservada para las entregas", "12_colocar_invalido")
			await _place_at(rack, GOOD_SPOT, GOOD_YAW, "colocando_rack", "11_colocar_valido")
		"wall":
			_note("  posiciones no válidas: sobre la zona de entregas y sobre la cama")
			await _invalid_spot(rack, Vector3(-0.45, 0.0, 0.8), 0.0, "reservada para las entregas")
			await _invalid_spot(rack, Vector3(-1.2, 0.0, -0.4), 0.0, "mueble")
			_note("  contra la pared: el frente mira a la pared derecha")
			await _place_at(rack, WALL_SPOT, 90.0, "rechazo_pared")
			if rack.location == &"placed":
				_fail("el rack se colocó sin espacio delante")
				return null
			if not s.hud._toast.text.contains("libres delante y detrás"):
				_fail("el rechazo no explica el motivo: «%s»" % s.hud._toast.text)
			_note("  girado 90°: el frente mira a la habitación")
			await _place_at(rack, WALL_SPOT, 0.0, "colocando_rack")
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


## blocking: the rack closes the corner in front of the PC tower; a right click on the rack
## moves it (no need to walk to it).
func _blocked_then_move(rack: SimDevice) -> bool:
	_note("3b. El rack cierra el paso al rincón delante del PC")
	await _click_point(POCKET)
	await _frames(10)
	if s.interaction.mode != InteractionManager.Mode.OVERVIEW or not s.hud._toast.text.contains("No puedo llegar"):
		_fail("el rack no bloqueó el paso (modo %d, mensaje «%s»)" % [s.interaction.mode, s.hud._toast.text])
		return false
	await _shot("paso_bloqueado")
	_note("3c. Clic derecho en el rack: moverlo sin caminar")
	await _click_point(s.target_center(&"rack", rack.id), MOUSE_BUTTON_RIGHT, _is_device_or_rack.bind(rack.id))
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
	await _manual("13_mover_rack", [_rect_of(_find_button(s.hud._side_box, "Mover rack")), _rect_of(_find_button(s.hud._side_box, "Recoger rack"))])
	var first := _inventory(&"switch_16p_1u")
	if first != null:
		await _manual("14_rack_panel", [_rect_of(_find_button(s.hud._side_box, first.display_name())),
			_rect_of(_find_button(s.hud._side_box, _inventory(&"server_1u_entry").display_name()))])
	for pair: Array in [[&"switch_16p_1u", 9], [&"server_1u_entry", 5]]:
		var d := _inventory(pair[0])
		if d == null or not await _press(_find_button(s.hud._side_box, d.display_name()), "Montar " + d.display_name()):
			return false
		if pair[1] == 9 and scenario == "manual":
			for area: Area3D in s.interaction._slot_areas:
				if area.get_meta("u") == 9:
					_motion(s.camera.unproject_position(area.global_position))
					await _frames(4)
					await _manual("15_montar", [], [s.camera.unproject_position(area.global_position)])
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
	if not await _choose_cable(_power_cord()):
		return false
	if scenario == "manual":
		var psu := s.camera.unproject_position((s.device_views[sw.id] as DeviceView).port_areas[PortRef.make(sw.id, &"psu", 0)].global_position)
		_motion(psu)
		await _frames(4)
		await _manual("16_puertos", [s.hud._tool.get_global_rect(), _hud_rect(s.hud._inventory_row)], [psu])
	_check_guide("Paso 1 de 2", "toma libre de la regleta")
	await _frames(3)
	if s.interaction.cable_tool._glows.is_empty():
		_fail("en la vista cercana no brilla ningún puerto compatible")
	await _click_port(PortRef.make(sw.id, &"psu", 0))
	await _frames(2) # the guide follows on the next frame
	_check_guide("Paso 2 de 2", "toma libre de la regleta")
	await _shot("cable_corriente_pendiente")
	await _manual("16b_cable_guiado", [s.hud._cable_panel.get_global_rect()])
	await _leave()
	await _frames(5)
	_note("  guía en la vista general: %d flechas sobre equipos con tomas compatibles, en %s" % [s.interaction.cable_tool._arrows.size(), ", ".join(PackedStringArray(s.interaction.cable_tool._arrows.map(func(a: Node3D) -> String: return _v(a.global_position))))])
	if s.interaction.cable_tool._arrows.is_empty():
		_fail("en la vista general no se marca ningún equipo con tomas compatibles")
	await _shot("cable_flechas")
	await _manual("16c_cable_flechas", [s.hud._cable_panel.get_global_rect()])
	if not await _open(&"device", strip.id):
		return false
	await _manual("18_regleta", [], [s.camera.unproject_position((s.device_views[strip.id] as DeviceView).port_areas[PortRef.make(strip.id, &"outlet", 2)].global_position)])
	await _click_port(PortRef.make(strip.id, &"outlet", 2))
	await _shot("regleta")
	if not s.world.is_powered(sw):
		_fail("el switch no recibe corriente: «%s»" % s.hud._toast.text)
		return false
	await _frames(3)
	if s.hud.cable_panel_visible():
		_fail("con los dos extremos conectados, la guía del cable sigue en pantalla")
	if scenario == "basic" and not await _cable_cancelled_by_other_work(strip):
		return false

	_note("6. Corriente del servidor (regleta -> trasera del rack) y botón Encender")
	if not await _choose_cable(_power_cord()):
		return false
	await _click_port(PortRef.make(strip.id, &"outlet", 3))
	await _leave()
	if not await _open(&"rack", rack.id):
		return false
	await _rack_side(true)
	await _click_port(PortRef.make(srv.id, &"psu", 0))
	await _manual("20_encender", [_rect_of(_find_button(s.hud._side_box, "Encender"))])
	if not await _press(_find_button(s.hud._side_box, "Encender"), "Encender"):
		return false
	if not await _wait(func() -> bool: return srv.is_running() and sw.is_running()):
		_fail("switch/servidor no arrancan: switch %s, servidor %s" % [sw.state, srv.state])
		return false
	await _frames(10)
	await _shot("encendidos_trasera")
	return true


func _power_cord() -> StringName:
	return &"power_cord_5m" if scenario == "wall" else &"power_cord_3m"


## The cable guide panel is up and says `step` and `what`.
func _check_guide(step: String, what: String) -> void:
	if not s.hud.cable_panel_visible():
		_fail("no aparece la guía del cable (%s)" % step)
		return
	var text := s.hud.cable_panel_text()
	_note("  guía: " + text)
	if not text.contains(step) or not text.contains(what):
		_fail("la guía del cable no dice «%s» / «%s»: «%s»" % [step, what, text])


## basic: a cable half laid is cancelled when the player goes to do something else (the
## computer), and Esc in the overview cancels a chosen cable (ADR 0011).
func _cable_cancelled_by_other_work(strip: SimDevice) -> bool:
	_note("5b. Cable a medias: ponerse con el ordenador lo cancela; Esc también")
	if not await _choose_cable(&"power_cord_3m"):
		return false
	var cord := s.interaction.cable_tool.cable_id
	await _click_port(PortRef.make(strip.id, &"outlet", 3))
	if s.world.pending_cable() != cord:
		_fail("el primer extremo no se conectó")
		return false
	await _leave()
	await _click_point(GameSession.MONITOR_POSITION + Vector3(0.0, 0.3, 0.0), MOUSE_BUTTON_LEFT, _is_computer)
	if not await _wait_mode(InteractionManager.Mode.SCREEN):
		return false
	if s.world.pending_cable() >= 0 or s.world.get_device(cord).location != &"inventory":
		_fail("al ponerse con el ordenador el cable a medias no se canceló")
	if s.interaction.cable_tool.active():
		_fail("la guía del cable sigue activa con el ordenador")
	_note("  cancelado: cable en el inventario, toma %s libre" % PortRef.make(strip.id, &"outlet", 3))
	_key(KEY_ESCAPE)
	await _wait_mode(InteractionManager.Mode.OVERVIEW)
	await _wait(func() -> bool: return not s.character.busy, 5.0)
	if not await _choose_cable(&"power_cord_3m"):
		return false
	_key(KEY_ESCAPE)
	await _frames(3)
	if s.interaction.cable_tool.active() or s.hud.cable_panel_visible() or s.menu.visible:
		_fail("Esc en la vista general no canceló el cable elegido (o abrió el menú)")
	if not s.hud._toast.text.contains("Cable cancelado"):
		_fail("al cancelar no se avisa: «%s»" % s.hud._toast.text)
	return await _open(&"device", strip.id) # step 6 starts at the strip


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
	if not await _choose_cable(&"cable_cat6_5m"):
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
	await _check_cables_clear("tras cablear")
	await _check_no_overlaps("tras cablear")
	_check_cables_apart("tras cablear")
	return true


## Every drawn cable: visible (has a path) and no point of it inside a solid that is not one of
## its own two devices (or the rack they are in): furniture parts, walls, other devices, boxes.
func _check_cables_clear(label: String) -> void:
	await _frames(3)
	var space := s.get_world_3d().direct_space_state
	var checked := 0
	for cable_id: int in s.world.cable_ends:
		var ends: Dictionary = s.world.cable_ends[cable_id]
		if ends["b"] == "":
			continue
		if not s.cables.paths.has(cable_id):
			_fail("%s: el cable %d no se dibuja" % [label, cable_id])
			continue
		var exclude: Array[RID] = []
		for ref: String in [ends["a"], ends["b"]]:
			var d := s.world.get_device(PortRef.device_id(ref))
			for id: int in [d.id, d.rack_id]:
				var view := s.device_views.get(id) as DeviceView
				if view != null:
					exclude.append(view.body.get_rid())
		var path: PackedVector3Array = s.cables.paths[cable_id]
		# The whole tube, not only its centre line: a sphere of the cable's radius (minus 1 mm
		# for the facets of the drawn tube) slides along it.
		var spec := s.world.get_device(cable_id).definition.get_spec(CableSpec) as CableSpec
		var sphere := SphereShape3D.new()
		sphere.radius = (CableRenderer.RADIUS_POWER if spec.media == &"power" else CableRenderer.RADIUS_DATA) - 0.001
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = sphere
		query.collision_mask = Layers.FURNITURE | Layers.WALLS | Layers.DEVICES
		query.exclude = exclude
		for i: int in range(1, path.size()):
			var steps := maxi(1, ceili(path[i - 1].distance_to(path[i]) / 0.01))
			for k: int in steps + 1:
				var p := path[i - 1].lerp(path[i], float(k) / steps)
				query.transform = Transform3D(Basis.IDENTITY, p)
				var hits := space.intersect_shape(query, 1)
				checked += 1
				if not hits.is_empty():
					var what := hits[0]["collider"] as Node
					_fail("%s: el cable %s atraviesa %s en %s" % [label, s.world.get_device(cable_id).definition.model,
						(what.get_parent().name + "/" + what.name) if what != null else "?", _v(p)])
					return
	_note("  cables comprobados con su grosor (%s): %d posiciones, ninguna dentro de un sólido" % [label, checked])


## No cable runs through another one: every drawn cable, sampled each centimetre, keeps at least
## 75 % of the sum of both radii from every other cable (cables in a bundle lie side by side or
## on top of each other; drawn tubes have 8 sides, so a little contact is allowed).
func _check_cables_apart(label: String) -> void:
	const CELL := 0.02
	var grid := {} # Vector3i -> Array of [cable id, point, radius]
	var samples := 0
	for cable_id: int in s.cables.paths:
		var spec := s.world.get_device(cable_id).definition.get_spec(CableSpec) as CableSpec
		var radius := CableRenderer.RADIUS_POWER if spec.media == &"power" else CableRenderer.RADIUS_DATA
		var path: PackedVector3Array = s.cables.paths[cable_id]
		for i: int in range(1, path.size()):
			var steps := maxi(1, ceili(path[i - 1].distance_to(path[i]) / 0.01))
			for k: int in steps:
				var p := path[i - 1].lerp(path[i], float(k) / steps)
				var cell := Vector3i((p / CELL).floor())
				if not grid.has(cell):
					grid[cell] = []
				(grid[cell] as Array).append([cable_id, p, radius])
				samples += 1
	for cell: Vector3i in grid:
		for entry: Array in grid[cell]:
			for dx: int in [-1, 0, 1]:
				for dy: int in [-1, 0, 1]:
					for dz: int in [-1, 0, 1]:
						for other: Array in (grid.get(cell + Vector3i(dx, dy, dz), []) as Array):
							if int(other[0]) <= int(entry[0]):
								continue
							var gap := (entry[1] as Vector3).distance_to(other[1])
							if gap < 0.75 * (float(entry[2]) + float(other[2])):
								_fail("%s: el cable %s atraviesa el cable %s en %s" % [label,
									s.world.get_device(entry[0]).definition.model, s.world.get_device(other[0]).definition.model, _v(entry[1])])
								return
	_note("  cables entre sí (%s): %d muestras, ninguno dentro de otro" % [label, samples])


## Nothing goes through anything: every device, the monitor and keyboard and the box stack are
## checked against furniture, walls and the other devices with their colliders shrunk by 1 cm
## (touching is allowed: the router stands on the cabinet). A device mounted in a rack may of
## course be inside that rack.
func _check_no_overlaps(label: String) -> void:
	await _frames(3)
	var space := s.get_world_3d().direct_space_state
	var bodies: Array = [] # [body, allowed RIDs]
	for view: DeviceView in s.device_views.values():
		var d := s.world.get_device(view.device_id)
		var allowed: Array[RID] = [view.body.get_rid()]
		if d.location == &"mounted" and s.device_views.has(d.rack_id):
			allowed.append((s.device_views[d.rack_id] as DeviceView).body.get_rid())
		for m: SimDevice in s.world.mounted_in(d):
			if s.device_views.has(m.id):
				allowed.append((s.device_views[m.id] as DeviceView).body.get_rid())
		bodies.append([view.body, allowed, d.display_name()])
	for node: Node3D in [s.monitor, s.room.objects.get_node_or_null("Keyboard") as Node3D]:
		if node == null:
			continue
		for child: Node in node.get_children():
			if child is StaticBody3D:
				bodies.append([child, [(child as StaticBody3D).get_rid()] as Array[RID], node.name])
	if s.package_stack.visible:
		bodies.append([s.package_stack.body, [s.package_stack.body.get_rid()] as Array[RID], "cajas"])
	var checked := 0
	for entry: Array in bodies:
		var body := entry[0] as StaticBody3D
		for shape_node: Node in body.get_children():
			var shape := shape_node as CollisionShape3D
			if shape == null or not (shape.shape is BoxShape3D):
				continue
			var shrunk := BoxShape3D.new()
			shrunk.size = ((shape.shape as BoxShape3D).size - Vector3.ONE * 0.02).max(Vector3.ONE * 0.002)
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = shrunk
			query.transform = shape.global_transform
			query.collision_mask = Layers.FURNITURE | Layers.WALLS | Layers.DEVICES
			query.exclude = entry[1]
			checked += 1
			for hit: Dictionary in space.intersect_shape(query, 4):
				var other := hit["collider"] as Node
				# Two devices of the same rack: the rack box (excluded) holds both; their own boxes
				# must not overlap, so they are still checked.
				_fail("%s: %s atraviesa %s" % [label, entry[2], (other.get_parent().name + "/" + other.name) if other != null else "?"])
	_note("  objetos comprobados (%s): %d, ninguno dentro de otro" % [label, checked])


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
	await _manual("21_consola", [console.input.get_global_rect()])
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
	await _click_point(GameSession.MONITOR_POSITION + Vector3(0.0, 0.3, 0.0), MOUSE_BUTTON_LEFT, _is_computer)
	if not await _wait_mode(InteractionManager.Mode.SCREEN):
		return false
	if not await _press(_find_button(s.screen, "Terminal"), "Terminal"):
		return false
	await _frames(5)
	await _type_line(s.screen._terminal, "ping -c 4 192.168.1.50")
	await _frames(5)
	await _shot("ping_desde_pc")
	await _manual("22_ping", [_rect_of(_find_button(s.screen, "Terminal"))])
	if not s.screen._terminal.output.get_parsed_text().contains("64 bytes from 192.168.1.50"):
		_fail("el ping no respondió")
	_key(KEY_ESCAPE)
	await _wait_mode(InteractionManager.Mode.OVERVIEW)
	await _wait(func() -> bool: return not s.character.busy, 5.0)
	_check_standing("tras el ping")
	await _frames(20)
	return true


func _end_banner() -> bool:
	if not await _wait(func() -> bool: return s.hud._banner.visible, 5.0):
		_fail("no apareció el cartel de misión completada")
		return false
	await _frames(5)
	await _shot("mision_completada")
	await _manual("23_mision", [s.hud._banner.get_global_rect()])
	return await _press(_find_button(s.hud, "Seguir jugando"), "Seguir jugando")


# --------------------------------------------------------------- new checks --

## Esc opens the menu (game paused); Settings > Controls lists the real keys; F1 shows the manual
## (index, a page, Next, Index); Esc closes it again.
func _menu_controls_and_manual() -> bool:
	_note("0b. Menú: Esc lo abre (pausa), Ajustes > Controles, manual con F1, Esc lo cierra")
	_key(KEY_ESCAPE)
	await _frames(3)
	if not s.menu.visible or not get_tree().paused:
		_fail("Esc en la vista general no abrió el menú en pausa")
		return false
	if not await _press(_find_button(s.menu, "Controles"), "Controles"):
		return false
	await _frames(3)
	var texts: Array[String] = []
	for node: Node in s.menu.find_children("*", "RichTextLabel", true, false):
		texts.append((node as RichTextLabel).get_parsed_text())
	var joined := " | ".join(texts)
	for expected: String in ["Q / E", "Rueda hacia arriba", "W / A / S / D", "Esc", "F1", "Clic izquierdo"]:
		if not joined.contains(expected):
			_fail("la página de controles no muestra «%s»" % expected)
	_note("  controles: %d filas" % texts.size())
	await _shot("menu_controles")
	await _manual("04_menu_controles", [_rect_of(_find_button(s.menu, "Controles")), _rect_of(_find_button(s.menu, "Manual (F1)"))])
	_key(KEY_F1)
	await _frames(4)
	if s.menu.current != &"manual" or s.menu.manual == null:
		_fail("F1 no abrió el manual")
		return false
	var manual := s.menu.manual
	_note("  manual: %d capítulos" % manual.chapters.size())
	if not await _press(_find_button_prefix(s.menu, "1. "), "capítulo 1"):
		return false
	await _frames(3)
	var picture := s.menu.find_child("Picture", true, false) as TextureRect
	if manual.chapter != 0 or picture == null or picture.texture == null:
		_fail("la primera página del manual no muestra su imagen")
	await _shot("manual_pagina")
	if not await _press(_find_button(s.menu, "Siguiente ▶"), "Siguiente"):
		return false
	if manual.page != 1 and manual.chapter != 1:
		_fail("«Siguiente» no avanzó de página")
	if not await _press(_find_button(s.menu, "◀ Anterior"), "Anterior"):
		return false
	if manual.page != 0 or manual.chapter != 0:
		_fail("«Anterior» no volvió a la primera página")
	if not await _press(_find_button(s.menu, "Índice"), "Índice"):
		return false
	if manual.chapter != -1:
		_fail("«Índice» no volvió al índice")
	_key(KEY_ESCAPE)
	await _frames(3)
	if s.menu.visible or get_tree().paused:
		_fail("Esc no cerró el menú")
		return false
	return true


## Walking into narrow places, corners and next to the rack: the character either gets there or
## says it cannot, never stays stuck, and never ends up inside something.
func _narrow_walks() -> bool:
	_note("3d. Caminar por espacios estrechos y esquinas")
	var targets := [Vector3(1.5, 0.0, 0.5), Vector3(-1.0, 0.0, 0.72), Vector3(-1.55, 0.0, 1.3),
		Vector3(0.95, 0.0, -0.62), Vector3(1.45, 0.0, -0.85), Vector3(0.40, 0.0, -0.05), POCKET, Vector3(0.3, 0.0, 1.3)]
	for target: Vector3 in targets:
		var toast := s.hud._toast.text
		await _click_point(target)
		var finished := await _wait(func() -> bool: return not s.character.moving, 15.0)
		var c := s.character.global_position
		var floor := NavigationServer3D.map_get_closest_point(s.get_world_3d().navigation_map, target)
		var outcome := "llegó" if Vector2(c.x - floor.x, c.z - floor.z).length() < 0.3 else ("avisó: " + s.hud._toast.text if s.hud._toast.text != toast else "se detuvo en %s" % _v(c))
		_note("  hacia %s: %s" % [_v(target), outcome])
		if not finished:
			_fail("el personaje sigue caminando tras 15 s hacia %s" % _v(target))
		if not s.character.capsule_fits(c):
			_fail("el personaje quedó dentro de algo en %s" % _v(c))
	return true


func _sit_stand_repeatedly(times: int) -> bool:
	_note("11. Sentarse y levantarse %d veces seguidas" % times)
	for i: int in times:
		await _click_point(GameSession.MONITOR_POSITION + Vector3(0.0, 0.3, 0.0), MOUSE_BUTTON_LEFT, _is_computer)
		if not await _wait_mode(InteractionManager.Mode.SCREEN):
			return false
		if not s.character.seated:
			_fail("vez %d: delante del ordenador sin estar sentado" % (i + 1))
		_key(KEY_ESCAPE)
		if not await _wait_mode(InteractionManager.Mode.OVERVIEW):
			return false
		await _wait(func() -> bool: return not s.character.busy, 5.0)
		_check_standing("vez %d" % (i + 1))
		_note("  vez %d: sentado y de pie en %s" % [i + 1, _v(s.character.global_position)])
	await _click_point(Vector3(0.95, 0.0, 0.3))
	if not s.character.moving and s.character.global_position.distance_to(Vector3(0.95, 0.0, 0.3)) > 0.3:
		_fail("tras levantarse, el personaje no vuelve a caminar")
	await _wait(func() -> bool: return not s.character.moving)
	return true


## Save sitting at the PC (menu from the PC screen), change the game, load: the saved state comes
## back, the character stands on a free spot (never inside the chair), cables are drawn again.
func _save_and_load(rack_id: int) -> void:
	_note("12. Guardar sentado ante el PC, cambiar la partida y cargar")
	# Clock paused (it is saved too): no passive income can be paid between saving and checking.
	await _press(s.hud._speed_buttons[0.0], "II (pausa)")
	await _click_point(GameSession.MONITOR_POSITION + Vector3(0.0, 0.3, 0.0), MOUSE_BUTTON_LEFT, _is_computer)
	if not await _wait_mode(InteractionManager.Mode.SCREEN):
		return
	if not await _press(_find_button(s.screen, "Menú"), "Menú (pantalla del PC)"):
		return
	var saved := _snapshot()
	if not await _press(_find_button(s.menu, "Guardar partida"), "Guardar partida"):
		return
	if not s.menu._status.text.contains("guardada"):
		_fail("guardar no confirma: «%s»" % s.menu._status.text)
	await _press(_find_button(s.menu, "Continuar (Esc)"), "Continuar")
	_key(KEY_ESCAPE)
	await _wait_mode(InteractionManager.Mode.OVERVIEW)
	await _wait(func() -> bool: return not s.character.busy, 5.0)
	if not await _open(&"rack", rack_id):
		return
	await _press(_find_button(s.hud._side_box, "Desconectar todos los cables"), "Desconectar todos los cables")
	await _leave()
	if _snapshot() == saved:
		_fail("el cambio después de guardar no se notó")
	_key(KEY_ESCAPE)
	await _frames(3)
	var old_id := s.get_instance_id() # an id, not the session: the old one is freed on loading
	if not await _press(_find_button(s.menu, "Cargar partida"), "Cargar partida"):
		return
	if not await _wait(func() -> bool: return is_instance_valid(s) and s.get_instance_id() != old_id, 10.0):
		_fail("la partida no se cargó")
		return
	await _frames(90) # views, navigation bake
	var loaded := _snapshot()
	for key: String in saved:
		if str(saved[key]) != str(loaded[key]):
			_fail("tras cargar, «%s» no coincide:\n guardado %s\n cargado  %s" % [key, saved[key], loaded[key]])
	_note("  estado guardado y cargado idéntico (%d equipos, %d cables)" % [(loaded["devices"] as Array).size(), (loaded["cables"] as Array).size()])
	_check_standing("tras cargar")
	var chair := s.room.chair.global_position
	if Vector2(s.character.global_position.x - chair.x, s.character.global_position.z - chair.z).length() < 0.35:
		_fail("tras cargar, el personaje está dentro de la silla")
	await _check_cables_clear("tras cargar")
	await _check_no_overlaps("tras cargar")
	_check_cables_apart("tras cargar")
	var rack_view := s.device_views.get(rack_id) as DeviceView
	for d: SimDevice in s.world.mounted_in(s.world.get_device(rack_id)):
		var view := s.device_views.get(d.id) as DeviceView
		if view == null or not view.visible or view.global_position.distance_to(rack_view.global_position) > 0.8:
			_fail("tras cargar, %s no está en su rack" % d.display_name())
	await _shot("tras_cargar")
	await _press(s.hud._speed_buttons[1.0], "×1")


func _snapshot() -> Dictionary:
	var devices: Array = []
	for d: SimDevice in s.world.devices.values():
		devices.append([d.id, String(d.location), d.position.snapped(Vector3.ONE * 0.001), d.yaw_degrees, d.rack_id, d.rack_u, String(d.state)])
	devices.sort()
	var cables: Array = []
	for id: int in s.world.cable_ends:
		cables.append([id, s.world.cable_ends[id]["a"], s.world.cable_ends[id]["b"]])
	cables.sort()
	return {"credits": s.world.credits, "xp": s.world.xp, "completed": s.world.mission.completed, "ledger": s.world.economy.ledger.size(),
		"devices": devices, "cables": cables, "packages": s.world.packages.size()}


## blocking: the three ways to the chair are blocked (test boxes): the character says so and
## does not move or teleport; once they are gone it sits down normally.
func _chair_blocked() -> void:
	_note("12. Silla bloqueada por los dos lados y por detrás (cajas de prueba)")
	await _click_point(Vector3(0.3, 0.0, 1.0)) # away from the chair before the boxes appear
	await _wait(func() -> bool: return not s.character.moving)
	var boxes: Array[Node3D] = []
	for spot: Vector3 in s.chair_spots():
		var body := StaticBody3D.new()
		body.collision_layer = Layers.DEVICES
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.62, 0.4, 0.62)
		shape.shape = box
		shape.position = Vector3(0.0, 0.2, 0.0)
		body.add_child(shape)
		s.room.objects.add_child(body)
		body.global_position = spot
		boxes.append(body)
	await _rebake()
	var before := s.character.global_position
	await _click_point(GameSession.MONITOR_POSITION + Vector3(0.0, 0.3, 0.0), MOUSE_BUTTON_LEFT, _is_computer)
	await _frames(15)
	if s.interaction.mode != InteractionManager.Mode.OVERVIEW or not s.hud._toast.text.contains("No puedo llegar a la silla"):
		_fail("con la silla bloqueada no avisa (modo %d, «%s»)" % [s.interaction.mode, s.hud._toast.text])
	if s.character.seated or s.character.global_position.distance_to(before) > 0.05:
		_fail("con la silla bloqueada el personaje se movió o se sentó")
	await _shot("silla_bloqueada")
	for body: Node3D in boxes:
		body.queue_free()
	await _frames(2)
	await _rebake()
	await _click_point(GameSession.MONITOR_POSITION + Vector3(0.0, 0.3, 0.0), MOUSE_BUTTON_LEFT, _is_computer)
	if await _wait_mode(InteractionManager.Mode.SCREEN):
		_key(KEY_ESCAPE)
		await _wait_mode(InteractionManager.Mode.OVERVIEW)
		await _wait(func() -> bool: return not s.character.busy, 5.0)
		_check_standing("tras desbloquear la silla")


func _rebake() -> void:
	var done := [false]
	s.room.nav_region.bake_finished.connect(func() -> void: done[0] = true, CONNECT_ONE_SHOT)
	s.room.request_bake()
	await _wait(func() -> bool: return done[0], 10.0)
	await _frames(3)


## manual: the last pictures (a cable that does not reach, the save menu).
func _manual_epilogue() -> void:
	_note("11. Capturas finales del manual")
	var rack := s.world.devices_of(&"rack")[0]
	var sw := _mounted(rack, &"switch_16p_1u")
	var router := s.world.devices_of(&"router")[0]
	if not await _open(&"rack", rack.id):
		return
	await _rack_side(false)
	if not await _choose_cable(&"cable_cat6_1m"):
		return
	await _click_port(PortRef.make(sw.id, &"lan", 2))
	await _leave()
	if not await _open(&"device", router.id):
		return
	await _click_port(PortRef.make(router.id, &"lan", 2))
	if not s.hud._toast.text.contains("no llega"):
		_fail("esperaba «el cable no llega»: «%s»" % s.hud._toast.text)
	await _manual("19_cable_no_llega", [s.hud._toast.get_global_rect()])
	await _leave()
	# A cable is still chosen (first Esc would drop it): use the HUD button.
	await _press(_find_button(s.hud, "Menú (Esc)"), "Menú (HUD)")
	await _frames(3)
	await _press(_find_button(s.menu, "Guardar partida"), "Guardar partida")
	await _manual("24_menu_guardar", [_rect_of(_find_button(s.menu, "Guardar partida")), _rect_of(_find_button(s.menu, "Cargar partida")), s.menu._status.get_global_rect()])
	_key(KEY_ESCAPE)
	await _frames(3)


func _find_button_prefix(root: Node, prefix: String) -> Button:
	for node: Node in root.find_children("*", "Button", true, false):
		var b := node as Button
		if b.text.begins_with(prefix) and b.is_visible_in_tree() and not b.is_queued_for_deletion():
			return b
	return null


# ------------------------------------------------------------ manual shots --

## Screenshot for the in-game manual (scenario "manual" only): the current frame with the given
## screen rectangles framed and screen points circled, saved as res://assets/manual/<name>.png.
func _manual(name: String, rects: Array = [], points: Array = []) -> void:
	if scenario != "manual":
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	for r: Variant in rects:
		var rect: Rect2 = r
		if rect.size.x > 0.0:
			_frame(image, rect.grow(6.0))
	for p: Variant in points:
		_ring(image, p as Vector2, 34.0)
	image.resize(MANUAL_SIZE.x, MANUAL_SIZE.y, Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MANUAL_DIR))
	var path := ProjectSettings.globalize_path(MANUAL_DIR.path_join(name + ".png"))
	var err := image.save_png(path)
	_note("  manual: %s.png (%s)" % [name, error_string(err)])
	if err != OK:
		_fail("no se pudo guardar la captura del manual %s" % name)


func _frame(image: Image, rect: Rect2) -> void:
	var r := Rect2i(rect)
	var t := 4
	for band: Rect2i in [Rect2i(r.position.x, r.position.y, r.size.x, t), Rect2i(r.position.x, r.end.y - t, r.size.x, t),
			Rect2i(r.position.x, r.position.y, t, r.size.y), Rect2i(r.end.x - t, r.position.y, t, r.size.y)]:
		var clipped := band.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		if clipped.size.x > 0 and clipped.size.y > 0:
			image.fill_rect(clipped, MARK)


func _ring(image: Image, centre: Vector2, radius: float) -> void:
	var bounds := Rect2i(Vector2i.ZERO, image.get_size())
	for k: int in 720:
		var a := TAU * k / 720.0
		for w: int in 4:
			var p := Vector2i(centre + Vector2(cos(a), sin(a)) * (radius + w))
			if bounds.has_point(p):
				image.set_pixelv(p, MARK)


func _hud_rect(control: Control) -> Rect2:
	var node: Node = control
	# Frame the panel that contains the control, not just the label.
	while node != null and not (node is PanelContainer):
		node = node.get_parent()
	return (node as Control).get_global_rect() if node != null else control.get_global_rect()


func _rect_of(button: Control) -> Rect2:
	return button.get_global_rect() if button != null else Rect2()


# ----------------------------------------------------------------- helpers --

## An invalid spot: the ghost turns red, the preview gives the reason and a click does nothing.
func _invalid_spot(rack: SimDevice, spot: Vector3, yaw: float, reason: String, manual_name: String = "") -> void:
	var before := rack.location
	await _place_at(rack, spot, yaw, "no_valido", manual_name)
	if rack.location != before:
		_fail("el rack se colocó en un sitio no válido %s" % _v(spot))
	if not s.hud._toast.text.contains(reason):
		_fail("el rechazo en %s no explica «%s»: «%s»" % [_v(spot), reason, s.hud._toast.text])
	if not _ghost_is_red():
		_fail("el fantasma no se pone rojo en un sitio no válido")
	if s.interaction.mode != InteractionManager.Mode.PLACEMENT:
		_fail("tras el rechazo se perdió el modo de colocación")


func _ghost_is_red() -> bool:
	var ghost := s.interaction._ghost
	if ghost == null:
		return false
	for mesh: MeshInstance3D in ModelUtil.find_meshes_with_prefix(ghost, ""):
		var overlay := mesh.material_overlay as StandardMaterial3D
		if overlay != null and overlay.albedo_color.r > 0.8 and overlay.albedo_color.g < 0.4:
			return true
	return false


## Rotates the ghost with R to `yaw`, points at `spot` and clicks. Returns the preview text.
func _place_at(rack: SimDevice, spot: Vector3, yaw: float, shot_label: String, manual_name: String = "") -> String:
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
	if manual_name != "":
		await _manual(manual_name, [s.hud._tool.get_global_rect()], [s.camera.unproject_position(spot + Vector3(0, 0.35, 0))])
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
	await _click_point(s.target_center(kind, target_id), MOUSE_BUTTON_LEFT, _is_device_or_rack.bind(target_id))
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
	var chosen := s.world.get_device(s.interaction.cable_tool.cable_id)
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


## Clicks a world point, as a player would: if something else is in front of it from the current
## camera angle (the rack hiding the floor behind it, a box hiding the monitor), the camera is
## turned first with a right drag. `check` tells whether the first collider under the cursor is
## the intended one; without it, a floor point (y ≈ 0) must be the floor itself.
func _click_point(point: Vector3, button: MouseButton = MOUSE_BUTTON_LEFT, check: Callable = Callable()) -> void:
	for attempt: int in 8:
		if _target_visible(point, check):
			break
		_note("  %s está tapado desde esta cámara: giro la vista" % _v(point))
		var centre := s.get_viewport().get_visible_rect().size / 2.0
		await _drag(centre, Vector2(140.0, 0.0), MOUSE_BUTTON_RIGHT)
		await _frames(40)
	var before := s.hud._toast.text
	await _click_screen(s.camera.unproject_position(point), button)
	if s.hud._toast.text != before:
		_note("  mensaje: " + s.hud._toast.text)


func _target_visible(point: Vector3, check: Callable) -> bool:
	if s.interaction.mode != InteractionManager.Mode.OVERVIEW and s.interaction.mode != InteractionManager.Mode.PLACEMENT:
		return true # close-ups and placement have their own checks
	if not check.is_valid() and point.y > 0.02:
		return true
	var screen := s.camera.unproject_position(point)
	var from := s.camera.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(from, from + s.camera.project_ray_normal(screen) * 30.0, Layers.WORLD_PICK)
	var hit := s.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	if check.is_valid():
		return check.call(hit["collider"] as Node)
	var p: Vector3 = hit["position"]
	return not (hit["collider"] as Node).has_meta("device_id") and Vector2(p.x - point.x, p.z - point.z).length() < 0.1


## Collider checks for _click_point.
func _is_computer(collider: Node) -> bool:
	return collider.has_meta("computer_id")


func _is_package_stack(collider: Node) -> bool:
	return collider.has_meta("package_stack")


func _is_device_or_rack(collider: Node, device_id: int) -> bool:
	if not collider.has_meta("device_id"):
		return false
	var d := s.world.get_device(collider.get_meta("device_id"))
	return d != null and (d.id == device_id or d.rack_id == device_id)


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
	# A page that was just built can still move (containers settle over a few frames): click
	# once the button stays put, as a player's eye would.
	var settled := 0
	var last := Rect2()
	var waited := 0
	while settled < 3 and waited < 60 and is_instance_valid(b):
		var rect := b.get_global_rect()
		settled = settled + 1 if rect.is_equal_approx(last) else 0
		last = rect
		waited += 1
		await _frames(1)
	if not is_instance_valid(b):
		_fail("el botón «%s» desapareció antes del clic" % label)
		return false
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


## The «Añadir a la cesta» button of the shop card of `item_id` (catalogue page).
func _shop_add_button(item_id: StringName) -> Button:
	var card := s.screen.shop.find_child("Card_%s" % item_id, true, false)
	if card == null or card.is_queued_for_deletion():
		return null
	return card.find_child("Add_%s" % item_id, true, false) as Button


func _find_link(root: Node, text: String) -> Button:
	for node: Node in root.find_children("*", "Button", true, false):
		var link := node as Button
		if link.text == text and link.is_visible_in_tree() and not link.is_queued_for_deletion():
			return link
	return null


## The shop: a product page opened from its card (photo, gallery, specs, reviews), then back.
func _shop_product_page() -> bool:
	_note("1a. Tienda: ficha de producto con fotos, especificaciones y opiniones")
	var listing := s.world.catalog.get_listing(&"server_1u_entry")
	var title := _find_link(s.screen.shop, listing.title)
	if not await _press(title, "ficha del servidor"):
		return false
	await _frames(5)
	var photo := s.screen.shop.find_child("MainPhoto", true, false) as TextureRect
	if photo == null or photo.texture == null:
		_fail("la ficha no muestra la foto del producto")
		return false
	var texts: Array[String] = []
	for node: Node in s.screen.shop.find_children("*", "Label", true, false):
		texts.append((node as Label).text)
	var joined := " | ".join(texts)
	for expected: String in ["Opiniones de clientes", "Especificaciones", "En la caja", "Compra verificada", "2 × RJ45", "+4 cr por hora"]:
		if not joined.contains(expected):
			_fail("la ficha no muestra «%s»" % expected)
	await _shot("tienda_ficha")
	await _manual("06b_ficha_producto", [photo.get_global_rect()])
	var first := photo.texture
	var thumbs := s.screen.shop.find_children("*", "TextureButton", true, false)
	if thumbs.size() >= 2:
		await _press(thumbs[thumbs.size() - 1] as TextureButton, "segunda foto")
		await _frames(3)
		var again := s.screen.shop.find_child("MainPhoto", true, false) as TextureRect
		if again == null or again.texture == first:
			_fail("la miniatura no cambió la foto grande")
	return await _press(_find_link(s.screen.shop, "◀ Volver a los resultados"), "volver a los resultados")


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
