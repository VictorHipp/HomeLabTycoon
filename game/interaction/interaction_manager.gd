class_name InteractionManager
extends Node
## Mouse/keyboard interaction (docs/INTERACTION_SYSTEM.md): click to walk, click an object to
## walk there and focus the camera, close-up views (rack, device, computer screen), placement,
## rack mounting, cabling and the server console. Every change goes through a SimWorld command;
## this class only turns input into commands and shows the results.

enum Mode { OVERVIEW, APPROACH, TRANSITION, CLOSEUP, SCREEN, CONSOLE, PLACEMENT }

const HINT_OVERVIEW := "Clic: caminar o usar · Arrastrar con botón derecho o central: girar · Rueda: zoom · WASD: mover la vista · Q/E: girar · F: centrar · Clic derecho en el rack: moverlo"
const HINT_CLOSEUP := "Esc: volver · R: cara frontal/trasera (rack) · Clic en un puerto: conectar el cable elegido · Clic derecho en un puerto: desconectar"
const HINT_PLACEMENT := "Clic: colocar · R: girar 90° · Arrastrar con botón derecho: girar la cámara · Esc o clic derecho: cancelar"
const SNAP := 0.05
const ZONE_FRONT_ALPHA := 0.45
const ZONE_REAR_ALPHA := 0.22

var session: GameSession
var mode: Mode = Mode.OVERVIEW
var selected_cable: int = -1

var _target_kind: StringName = &""
var _target_id: int = -1
var _approach_token: int = 0
var _closeup_device: int = -1 ## Device (or rack) shown in the close-up.
var _rack_rear: bool = false
var _mount_device: int = -1
var _slot_areas: Array[Area3D] = []
var _hover_port: String = ""
var _highlight: MeshInstance3D
var _ghost: Node3D = null
var _ghost_device: int = -1
var _ghost_yaw: float = 0.0
var _ghost_pos: Vector3 = Vector3.ZERO
var _hidden_views: Array[Node3D] = []
var _zone_meshes: Array[MeshInstance3D] = [] ## [front, rear] service zones of a rack ghost.
var _pending_move: int = -1 ## Rack to move once the camera is back in the overview.
var _right_down: bool = false
var _right_press_pos: Vector2 = Vector2.ZERO
var _console: CanvasLayer = null


func setup(game: GameSession) -> void:
	session = game
	_highlight = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.016, 0.014, 0.004) # about one RJ45 socket
	_highlight.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = UiStyle.HIGHLIGHT
	mat.emission_enabled = true
	mat.emission = UiStyle.HIGHLIGHT
	mat.emission_energy_multiplier = 3.0
	mat.no_depth_test = true
	_highlight.material_override = mat
	_highlight.visible = false
	session.add_child(_highlight)
	session.hud.inventory_item_pressed.connect(_on_inventory_item)
	session.screen.closed.connect(leave)
	session.character.arrived.connect(_on_arrived)
	session.character.unreachable.connect(_on_unreachable)
	session.hud.set_hint(TranslationServer.translate(HINT_OVERVIEW))
	_update_tool_text()


# ------------------------------------------------------------------- input --

func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	var motion := event as InputEventMouseMotion
	match mode:
		Mode.OVERVIEW, Mode.APPROACH:
			if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
				_click_world(button.position)
			elif button != null and button.button_index == MOUSE_BUTTON_RIGHT:
				# Right button: dragging turns the camera (OverviewCameraRig); a click without
				# dragging acts on the object under the cursor. Works whichever node sees the
				# release first: after a drag the rig either still reports it or consumes it.
				if button.pressed:
					_right_down = true
					_right_press_pos = button.position
				elif _right_down:
					_right_down = false
					if not session.rig.is_dragging() and button.position.distance_to(_right_press_pos) <= OverviewCameraRig.DRAG_THRESHOLD_PX:
						_right_click_world(button.position)
		Mode.TRANSITION:
			if button != null and button.pressed:
				session.director.skip()
		Mode.CLOSEUP:
			if motion != null:
				_hover_closeup(motion.position)
			elif button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
				_click_closeup(button.position)
			elif button != null and button.pressed and button.button_index == MOUSE_BUTTON_RIGHT:
				_right_click_closeup(button.position)
			elif event.is_action_pressed(&"close_interaction"):
				if _mount_device >= 0:
					_end_mount_mode()
				else:
					leave()
			elif event.is_action_pressed(&"rotate_object") and _is_rack(_closeup_device):
				_toggle_rack_side()
		Mode.PLACEMENT:
			if motion != null:
				_move_ghost(motion.position)
			elif button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
				_confirm_placement()
			elif button != null and button.button_index == MOUSE_BUTTON_RIGHT:
				# Same rule as in the overview: dragging turns the camera, a click cancels.
				if button.pressed:
					_right_down = true
					_right_press_pos = button.position
				elif _right_down:
					_right_down = false
					if not session.rig.is_dragging() and button.position.distance_to(_right_press_pos) <= OverviewCameraRig.DRAG_THRESHOLD_PX:
						_cancel_placement()
			elif event.is_action_pressed(&"close_interaction"):
				_cancel_placement()
			elif event.is_action_pressed(&"rotate_object"):
				_ghost_yaw = fposmod(_ghost_yaw + 90.0, 360.0)
				_update_ghost()
	if mode in [Mode.OVERVIEW, Mode.APPROACH] and event.is_action_pressed(&"close_interaction") and selected_cable >= 0:
		selected_cable = -1
		_update_tool_text()


## Raycast from the camera. With `areas` (ports, rack units) an area only counts when no
## solid body hides it (you cannot click a port at the back of a device).
func _ray(screen_pos: Vector2, mask: int, areas: bool = false) -> Dictionary:
	var camera := session.camera
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 30.0
	var space := session.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	query.collide_with_areas = areas
	query.collide_with_bodies = not areas
	var hit := space.intersect_ray(query)
	if areas and not hit.is_empty():
		var solid_query := PhysicsRayQueryParameters3D.create(from, to, Layers.DEVICES | Layers.FURNITURE | Layers.WALLS)
		# A rack's collider is a box around its whole volume (for clicking it in the overview);
		# it must not hide the devices mounted inside it.
		var exclude: Array[RID] = []
		for view: DeviceView in session.device_views.values():
			if _is_rack(view.device_id):
				exclude.append(view.body.get_rid())
		solid_query.exclude = exclude
		var solid := space.intersect_ray(solid_query)
		if not solid.is_empty() and from.distance_to(solid["position"]) < from.distance_to(hit["position"]) - 0.015:
			return {}
	return hit


# --------------------------------------------------------------- overview --

func _click_world(screen_pos: Vector2) -> void:
	var hit := _ray(screen_pos, Layers.WORLD_PICK)
	if hit.is_empty():
		return
	var collider := hit["collider"] as Node
	if collider.has_meta("computer_id"):
		_begin(&"computer", collider.get_meta("computer_id"))
	elif collider.has_meta("package_stack"):
		_begin(&"package", session.world.top_package_id())
	elif collider.has_meta("device_id"):
		var d := session.world.get_device(collider.get_meta("device_id"))
		if d.location == &"mounted":
			_begin(&"rack", d.rack_id)
		else:
			_begin(&"rack" if _is_rack(d.id) else &"device", d.id)
	else:
		_approach_token += 1
		mode = Mode.OVERVIEW
		if session.character.move_to(hit["position"]):
			session.spawn_click_marker(hit["position"])


## Right click in the overview: move a placed rack directly (no need to walk to it, so a rack
## that blocks the way can always be moved).
func _right_click_world(screen_pos: Vector2) -> void:
	var hit := _ray(screen_pos, Layers.WORLD_PICK)
	if hit.is_empty() or not (hit["collider"] as Node).has_meta("device_id"):
		return
	var d := session.world.get_device((hit["collider"] as Node).get_meta("device_id"))
	if d.location == &"mounted":
		d = session.world.get_device(d.rack_id)
	if d.location == &"placed":
		start_move(d.id)
	elif d.location == &"fixed":
		session.hud.show_toast(TranslationServer.translate("%s forma parte de la habitación: en esta prueba no se mueve.") % d.display_name(), false)


## Starts moving a placed device (with whatever is mounted in it). Cables must be unplugged.
func start_move(device_id: int) -> void:
	var d := session.world.get_device(device_id)
	if d == null or d.location != &"placed":
		return
	if session.world.has_cables_inside(d):
		session.hud.show_toast(TranslationServer.translate("Desconecta antes los cables de %s para moverlo (en su vista cercana: «Desconectar todos los cables»).") % d.display_name(), false)
		return
	_start_placement(d, true)


func _begin(kind: StringName, target_id: int) -> void:
	_target_kind = kind
	_target_id = target_id
	_approach_token += 1
	mode = Mode.APPROACH
	if not session.character.move_to(session.stand_point(kind, target_id)):
		mode = Mode.OVERVIEW


func _on_unreachable() -> void:
	mode = Mode.OVERVIEW
	var text: String = TranslationServer.translate("No puedo llegar ahí.")
	for rack: SimDevice in session.world.devices_of(&"rack"):
		if rack.location == &"placed":
			text += " " + TranslationServer.translate("Si el rack cierra el paso, muévelo con clic derecho sobre él.")
			break
	session.hud.show_toast(text, false)


func _on_arrived() -> void:
	if mode != Mode.APPROACH:
		return
	session.character.face_towards(session.target_center(_target_kind, _target_id))
	match _target_kind:
		&"package":
			var world := session.world
			var r := world.open_package(_target_id if world.packages.has(_target_id) else world.top_package_id())
			var left := world.packages.size()
			var text: String = r.message
			if r.ok:
				if left == 0:
					text += " " + TranslationServer.translate("No quedan más cajas.")
				elif left == 1:
					text += " " + TranslationServer.translate("Queda 1 caja.")
				else:
					text += " " + TranslationServer.translate("Quedan %d cajas.") % left
			session.hud.show_toast(text, r.ok)
			mode = Mode.OVERVIEW
		&"computer":
			_focus(session.screen_anchor(), Mode.SCREEN)
		&"rack":
			_closeup_device = _target_id
			_rack_rear = false
			_focus(session.rack_anchor(_target_id, false), Mode.CLOSEUP)
		&"device":
			_closeup_device = _target_id
			_focus(session.device_anchor(_target_id), Mode.CLOSEUP)


func _focus(anchor: Transform3D, final_mode: Mode) -> void:
	mode = Mode.TRANSITION
	var token := _approach_token
	session.director.focus_on(anchor, session.character.global_position + Vector3(0.0, 1.5, 0.0))
	await session.director.transition_finished
	if token != _approach_token or mode != Mode.TRANSITION:
		return
	session.character.set_model_visible(false)
	mode = final_mode
	if final_mode == Mode.SCREEN:
		session.screen.open()
	else:
		session.hud.set_hint(TranslationServer.translate(HINT_CLOSEUP))
		refresh_panel()


func leave() -> void:
	if not (mode in [Mode.CLOSEUP, Mode.SCREEN, Mode.CONSOLE]):
		return
	_close_console()
	_end_mount_mode()
	_highlight.visible = false
	_hover_port = ""
	session.hud.side_hide()
	session.hud.set_hint(TranslationServer.translate(HINT_OVERVIEW))
	session.character.set_model_visible(true)
	_closeup_device = -1
	_approach_token += 1
	mode = Mode.TRANSITION
	session.director.return_to_overview()
	await session.director.transition_finished
	if mode == Mode.TRANSITION:
		mode = Mode.OVERVIEW
	_update_tool_text()
	if _pending_move >= 0 and mode == Mode.OVERVIEW:
		var device_id := _pending_move
		_pending_move = -1
		start_move(device_id)


# ---------------------------------------------------------------- close-up --

## Rebuilds the side panel of the current close-up (called on world events too).
func refresh_panel() -> void:
	if mode != Mode.CLOSEUP or _closeup_device < 0:
		return
	var world := session.world
	var hud := session.hud
	var d := world.get_device(_closeup_device)
	if _is_rack(d.id):
		var spec := d.definition.get_spec(RackSpec) as RackSpec
		var used := 0
		for m: SimDevice in world.mounted_in(d):
			used += m.definition.mount_height_u
		hud.side_clear("%s — %s" % [d.display_name(), TranslationServer.translate("cara trasera") if _rack_rear else TranslationServer.translate("cara frontal")])
		hud.side_label(TranslationServer.translate("Unidades libres: %d de %dU") % [spec.capacity_u - used, spec.capacity_u], UiStyle.MIST)
		var mounted := world.mounted_in(d)
		mounted.sort_custom(func(a: SimDevice, b: SimDevice) -> bool: return a.rack_u > b.rack_u)
		for m: SimDevice in mounted:
			hud.side_label("U%d · %s — %s" % [m.rack_u, m.display_name(), _state_text(m)], UiStyle.OK if m.is_running() else UiStyle.BONE)
			_device_buttons(m, true)
		var mountable: Array = world.inventory().filter(func(x: SimDevice) -> bool: return x.definition.placement == &"rack")
		if not mountable.is_empty():
			hud.side_label(TranslationServer.translate("Montar desde el inventario:"), UiStyle.MUSTARD)
			for x: SimDevice in mountable:
				hud.side_button(x.display_name(), _start_mount_mode.bind(x.id))
		if _mount_device >= 0:
			hud.side_label(TranslationServer.translate("Haz clic en una unidad libre del rack (Esc para cancelar)."), UiStyle.HIGHLIGHT)
		hud.side_button(TranslationServer.translate("Ver cara frontal (R)") if _rack_rear else TranslationServer.translate("Ver cara trasera (R)"), _toggle_rack_side)
		if world.has_cables_inside(d):
			hud.side_button(TranslationServer.translate("Desconectar todos los cables"), _disconnect_all.bind(d.id))
		hud.side_row([[TranslationServer.translate("Mover rack"), _move_from_closeup.bind(d.id)],
			[TranslationServer.translate("Recoger rack"), _pick_up.bind(d.id)]])
	else:
		hud.side_clear(d.display_name())
		hud.side_label(TranslationServer.translate("Estado: %s") % _state_text(d), UiStyle.OK if d.is_running() else UiStyle.BONE)
		_device_buttons(d, false)
		for ref: String in d.port_refs():
			hud.side_label(_port_text(ref), UiStyle.MIST, 13)
	hud.side_button(TranslationServer.translate("Volver (Esc)"), leave)


func _device_buttons(d: SimDevice, in_rack: bool) -> void:
	var row: Array = []
	if d.definition.has_power_button:
		row.append([TranslationServer.translate("Apagar") if d.power_switch_on else TranslationServer.translate("Encender"), _press_power.bind(d.id)])
	if d.host != null:
		row.append([TranslationServer.translate("Consola"), _open_console.bind(d.id)])
	if in_rack:
		row.append([TranslationServer.translate("Desmontar"), _unmount.bind(d.id)])
	if not row.is_empty():
		session.hud.side_row(row)


func _state_text(d: SimDevice) -> String:
	match d.state:
		&"running":
			return TranslationServer.translate("encendido")
		&"booting":
			return TranslationServer.translate("arrancando…")
	if d.power_switch_on and not session.world.is_powered(d):
		return TranslationServer.translate("apagado (sin corriente)")
	return TranslationServer.translate("apagado")


func _port_text(ref: String) -> String:
	var world := session.world
	var d := world.get_device(PortRef.device_id(ref))
	var group := d.definition.find_port_group(PortRef.group(ref))
	var label := "%s %d" % [String(group.id), PortRef.index(ref) + 1]
	var link := NetworkEngine.port_link(world, ref)
	if not link["has_cable"]:
		return TranslationServer.translate("%s: libre") % label
	if link["power"]:
		return TranslationServer.translate("%s: cable de corriente") % label + ("" if link["peer"] != "" else TranslationServer.translate(" (extremo suelto)"))
	if link["up"]:
		return TranslationServer.translate("%s: enlace activo a %d Mb/s") % [label, link["speed"]]
	return TranslationServer.translate("%s: sin enlace — %s") % [label, link["reason"]]


func _press_power(device_id: int) -> void:
	var r := session.world.press_power(device_id)
	session.hud.show_toast(r.message, r.ok)
	refresh_panel()


func _unmount(device_id: int) -> void:
	var r := session.world.unmount_device(device_id)
	session.hud.show_toast(r.message, r.ok)
	refresh_panel()


## Unplugs every cable of a rack and of the devices mounted in it (each one is a SimWorld command).
func _disconnect_all(rack_id: int) -> void:
	var world := session.world
	var rack := world.get_device(rack_id)
	var inside: Array[SimDevice] = [rack]
	inside.append_array(world.mounted_in(rack))
	var count := 0
	for d: SimDevice in inside:
		for ref: String in d.port_refs():
			if world.port_cable.has(ref) and world.disconnect_port(ref).ok:
				count += 1
	selected_cable = -1
	session.hud.show_toast(TranslationServer.translate("%d cables desconectados y devueltos al inventario.") % count)
	_update_tool_text()
	refresh_panel()


func _move_from_closeup(rack_id: int) -> void:
	if session.world.has_cables_inside(session.world.get_device(rack_id)):
		session.hud.show_toast(TranslationServer.translate("Desconecta antes los cables del rack para moverlo."), false)
		return
	_pending_move = rack_id
	leave()


func _pick_up(rack_id: int) -> void:
	var r := session.world.pick_up_device(rack_id)
	session.hud.show_toast(r.message, r.ok)
	if r.ok:
		leave()


func _toggle_rack_side() -> void:
	_rack_rear = not _rack_rear
	_end_mount_mode()
	session.director.switch_anchor(session.rack_anchor(_closeup_device, _rack_rear))
	refresh_panel()


func _hover_closeup(screen_pos: Vector2) -> void:
	if _mount_device >= 0:
		var slot := _ray(screen_pos, Layers.SLOTS, true)
		_highlight.visible = not slot.is_empty()
		if not slot.is_empty():
			_highlight.global_transform = (slot["collider"] as Area3D).global_transform
			_highlight.scale = Vector3(28.0, 3.0 * session.world.get_device(_mount_device).definition.mount_height_u, 1.0)
		return
	var hit := _ray(screen_pos, Layers.PORTS, true)
	if hit.is_empty():
		_highlight.visible = false
		_hover_port = ""
		_update_tool_text()
		return
	var area := hit["collider"] as Area3D
	_hover_port = area.get_meta("port_ref")
	_highlight.global_transform = area.global_transform
	_highlight.scale = Vector3.ONE
	_highlight.visible = true
	var d := session.world.get_device(PortRef.device_id(_hover_port))
	session.hud.set_tool_text("%s — %s" % [d.display_name(), _port_text(_hover_port)])


func _click_closeup(screen_pos: Vector2) -> void:
	if _mount_device >= 0:
		var slot := _ray(screen_pos, Layers.SLOTS, true)
		if not slot.is_empty():
			var u: int = (slot["collider"] as Area3D).get_meta("u")
			var r := session.world.mount_device(_mount_device, _closeup_device, u)
			session.hud.show_toast(r.message, r.ok)
			if r.ok:
				_end_mount_mode()
			refresh_panel()
		return
	var hit := _ray(screen_pos, Layers.PORTS, true)
	if hit.is_empty():
		return
	var ref: String = (hit["collider"] as Area3D).get_meta("port_ref")
	var cable := session.world.pending_cable()
	if cable < 0:
		cable = selected_cable
	if cable < 0:
		if session.world.port_cable.has(ref):
			session.hud.show_toast(TranslationServer.translate("Este puerto ya tiene cable. Clic derecho para desconectarlo."))
		else:
			session.hud.show_toast(TranslationServer.translate("Elige primero un cable en el inventario (abajo)."), false)
		return
	var result := session.world.connect_cable(cable, ref)
	session.hud.show_toast(result.message, result.ok)
	if result.ok and session.world.pending_cable() < 0:
		selected_cable = -1
	_update_tool_text()
	refresh_panel()


func _right_click_closeup(screen_pos: Vector2) -> void:
	var hit := _ray(screen_pos, Layers.PORTS, true)
	if hit.is_empty():
		return
	var r := session.world.disconnect_port((hit["collider"] as Area3D).get_meta("port_ref"))
	session.hud.show_toast(r.message, r.ok)
	_update_tool_text()
	refresh_panel()


# ---------------------------------------------------------------- mounting --

func _start_mount_mode(device_id: int) -> void:
	_end_mount_mode()
	if _rack_rear:
		_rack_rear = false
		session.director.switch_anchor(session.rack_anchor(_closeup_device, false))
	_mount_device = device_id
	_slot_areas = session.create_rack_slots(_closeup_device)
	refresh_panel()


func _end_mount_mode() -> void:
	_mount_device = -1
	for area: Area3D in _slot_areas:
		area.queue_free()
	_slot_areas.clear()
	_highlight.visible = false
	_highlight.scale = Vector3.ONE


# --------------------------------------------------------------- placement --

func _on_inventory_item(device_id: int) -> void:
	var d := session.world.get_device(device_id)
	match d.definition.placement:
		&"floor":
			if mode != Mode.OVERVIEW:
				session.hud.show_toast(TranslationServer.translate("Vuelve a la vista general (Esc) para colocarlo."), false)
				return
			_start_placement(d)
			return
		&"rack":
			if mode == Mode.CLOSEUP and _is_rack(_closeup_device):
				_start_mount_mode(device_id)
			else:
				session.hud.show_toast(TranslationServer.translate("Se monta en el rack: haz clic en el rack y elige «Montar»."))
			return
	if d.definition.get_spec(CableSpec) != null:
		selected_cable = device_id
		_update_tool_text()
		if mode != Mode.CLOSEUP:
			session.hud.show_toast(TranslationServer.translate("Cable elegido. Acércate a un equipo (clic en él) y haz clic en sus puertos."))
		return
	session.hud.show_toast(d.definition.description)


func _start_placement(d: SimDevice, moving: bool = false) -> void:
	_cancel_placement()
	_ghost_device = d.id
	_ghost_yaw = d.yaw_degrees if moving else 0.0
	_ghost_pos = d.position if moving else Vector3.ZERO
	_ghost = ModelUtil.instance_model(d.definition.model_path)
	for mesh: MeshInstance3D in ModelUtil.find_meshes_with_prefix(_ghost, ""):
		mesh.transparency = 0.45
	_add_service_zones(d.definition)
	session.add_child(_ghost)
	if moving:
		# The real rack (and what is mounted in it) disappears while its ghost is moved.
		var ids: Array[int] = [d.id]
		for m: SimDevice in session.world.mounted_in(d):
			ids.append(m.id)
		for id: int in ids:
			var view := session.device_views.get(id) as Node3D
			if view != null:
				view.visible = false
				_hidden_views.append(view)
	mode = Mode.PLACEMENT
	session.hud.set_hint(TranslationServer.translate(HINT_PLACEMENT))
	_update_ghost()
	_move_ghost(session.get_viewport().get_mouse_position())


## Floor marks of the space a rack needs in front (bright) and behind (faint).
func _add_service_zones(def: HardwareDefinition) -> void:
	_zone_meshes.clear()
	var rack := def.get_spec(RackSpec) as RackSpec
	if rack == null or rack.service_clearance_m <= 0.0:
		return
	for side: float in [1.0, -1.0]:
		var zone := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(def.footprint_m.x, rack.service_clearance_m)
		zone.mesh = plane
		zone.position = Vector3(0.0, 0.012, side * (def.footprint_m.y + rack.service_clearance_m) / 2.0)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		zone.material_override = mat
		zone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ghost.add_child(zone)
		_zone_meshes.append(zone)


func _move_ghost(screen_pos: Vector2) -> void:
	var hit := _ray(screen_pos, Layers.FLOOR)
	if hit.is_empty():
		return
	var p: Vector3 = hit["position"]
	_ghost_pos = Vector3(snappedf(p.x, SNAP), 0.0, snappedf(p.z, SNAP))
	_update_ghost()


func _update_ghost() -> void:
	if _ghost == null:
		return
	_ghost.position = _ghost_pos
	_ghost.rotation_degrees.y = _ghost_yaw
	var problem := _placement_problem()
	var text: String = TranslationServer.translate("✓ Cabe aquí: clic para colocar") if problem == "" else "✗ " + problem
	if not _zone_meshes.is_empty():
		var color: Color = UiStyle.OK if problem == "" else UiStyle.BAD
		for i: int in _zone_meshes.size():
			(_zone_meshes[i].material_override as StandardMaterial3D).albedo_color = Color(color, ZONE_FRONT_ALPHA if i == 0 else ZONE_REAR_ALPHA)
		text += TranslationServer.translate(" · La zona clara del suelo marca el frente del rack.")
		if problem == "":
			var power := session.world.rack_power_estimate(_ghost_device, _ghost_pos, _ghost_yaw)
			if not power.is_empty() and power["needed"] == INF:
				text += "\n" + TranslationServer.translate("⚠ Desde aquí no hay por dónde llevar un cable de corriente hasta la regleta.")
			elif not power.is_empty() and power["needed"] > power["longest"]:
				text += "\n" + TranslationServer.translate("⚠ Lejos de la regleta: los equipos del rack necesitarían unos %.1f m de cable de corriente y el más largo de la tienda mide %.0f m.") % [power["needed"], power["longest"]]
			elif not power.is_empty() and power["needed"] > power["included"]:
				text += "\n" + TranslationServer.translate("⚠ Lejos de la regleta: los equipos del rack necesitarían unos %.1f m de cable de corriente; el que traen mide %.0f m (en la tienda hay de %.0f m).") % [power["needed"], power["included"], power["longest"]]
	session.hud.set_tool_text(text)


## Simulation rules plus one presentation rule: never drop an object on the character.
func _placement_problem() -> String:
	var problem := session.world.placement_problem(_ghost_device, _ghost_pos, _ghost_yaw)
	if problem != "":
		return problem
	var def := session.world.get_device(_ghost_device).definition
	var rect := SimWorld.footprint_rect(def, _ghost_pos, _ghost_yaw).grow(0.3)
	var c := session.character.global_position
	if rect.has_point(Vector2(c.x, c.z)):
		return TranslationServer.translate("Tu personaje está en medio: apártalo primero.")
	return ""


func _confirm_placement() -> void:
	var problem := _placement_problem()
	if problem != "":
		session.hud.show_toast(problem, false)
		return
	var r := session.world.place_device(_ghost_device, _ghost_pos, _ghost_yaw)
	session.hud.show_toast(r.message, r.ok)
	if r.ok:
		_cancel_placement()


func _cancel_placement() -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	_zone_meshes.clear()
	for view: Node3D in _hidden_views:
		if is_instance_valid(view):
			view.visible = true
	_hidden_views.clear()
	_ghost_device = -1
	if mode == Mode.PLACEMENT:
		mode = Mode.OVERVIEW
		session.hud.set_hint(TranslationServer.translate(HINT_OVERVIEW))
	_update_tool_text()


# ----------------------------------------------------------------- console --

func _open_console(device_id: int) -> void:
	_close_console()
	var d := session.world.get_device(device_id)
	_console = CanvasLayer.new()
	_console.layer = 12
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", UiStyle.panel(Color("#0B0E12"), 0, 18))
	_console.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var bar := HBoxContainer.new()
	column.add_child(bar)
	var title := UiStyle.label(TranslationServer.translate("Consola local de %s (como si conectaras monitor y teclado)") % d.display_name(), 17, UiStyle.HIGHLIGHT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(title)
	bar.add_child(UiStyle.button(TranslationServer.translate("Cerrar (Esc)"), _close_console))
	var terminal := TerminalView.new()
	terminal.setup(session.world, device_id, d.host.login_user)
	terminal.exit_requested.connect(_close_console)
	column.add_child(terminal)
	session.add_child(_console)
	terminal.focus_input.call_deferred()
	mode = Mode.CONSOLE


func _close_console() -> void:
	if _console != null:
		_console.queue_free()
		_console = null
		if mode == Mode.CONSOLE:
			mode = Mode.CLOSEUP
			refresh_panel()


func _input(event: InputEvent) -> void:
	if mode == Mode.CONSOLE and event.is_action_pressed(&"close_interaction"):
		get_viewport().set_input_as_handled()
		_close_console()


## Console (for tests and the automated walkthrough): the TerminalView in use, or null.
func console_terminal() -> TerminalView:
	if _console == null:
		return null
	return _console.find_children("*", "TerminalView", true, false)[0] as TerminalView


# ----------------------------------------------------------------- helpers --

func _is_rack(device_id: int) -> bool:
	var d := session.world.get_device(device_id)
	return d != null and d.definition.get_spec(RackSpec) != null


func _update_tool_text() -> void:
	var world := session.world
	var pending := world.pending_cable()
	if pending >= 0:
		session.hud.set_tool_text(TranslationServer.translate("Cable con un extremo suelto (%s): conecta el otro extremo en otro puerto. Clic derecho en el extremo conectado para retirarlo.") % world.get_device(pending).definition.model)
	elif selected_cable >= 0:
		session.hud.set_tool_text(TranslationServer.translate("Cable elegido: %s — clic en un puerto (Esc para soltarlo)") % world.get_device(selected_cable).definition.model)
	elif mode != Mode.PLACEMENT:
		session.hud.set_tool_text("")
