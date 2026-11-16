class_name InteractionManager
extends Node
## Mouse/keyboard interaction (docs/INTERACTION_SYSTEM.md): click to walk, click an object to
## walk there and focus the camera, close-up views (rack, device, computer screen), placement,
## rack mounting, cabling and the server console. Every change goes through a SimWorld command;
## this class only turns input into commands and shows the results.

enum Mode { OVERVIEW, APPROACH, TRANSITION, CLOSEUP, SCREEN, CONSOLE, PLACEMENT }

const HINT_OVERVIEW := "Clic: caminar o usar · Arrastrar con botón derecho o central: girar · Rueda: zoom · WASD: mover la vista · Q/E: girar · F: centrar · Clic derecho en un mueble, el router o el rack: moverlo"
const HINT_CLOSEUP := "Esc: volver · R: cara frontal/trasera (rack) · Clic en un puerto: conectar el cable elegido · Clic derecho en un puerto: desconectar"
const HINT_PLACEMENT := "Clic: colocar · R: girar 90° · Arrastrar con botón derecho: girar la cámara · Esc o clic derecho: cancelar"
const SNAP := 0.05
const ZONE_FRONT_ALPHA := 0.45
const ZONE_REAR_ALPHA := 0.22

var session: GameSession
var mode: Mode = Mode.OVERVIEW
var cable_tool: CableTool ## The cable being laid, step by step (guide, glows, cancel).

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
var _ghost_furniture: StringName = &"" ## Piece of furniture being moved (with what it carries).
var _ghost_top_device: int = -1 ## Small device (router) being put on top of a piece of furniture.
var _ghost_top_piece: StringName = &"" ## The piece under it (empty: over the floor, not allowed).
var _problem_key: String = "" ## Furniture checks route every cable: only redone when the spot changes.
var _problem_cache: String = ""
var _ghost_yaw: float = 0.0
var _ghost_pos: Vector3 = Vector3.ZERO
var _hidden_views: Array[Node3D] = []
var _zone_meshes: Array[MeshInstance3D] = [] ## [front, rear] service zones of a rack ghost.
var _pending_move: int = -1 ## Rack to move once the camera is back in the overview.
var _right_down: bool = false
var _right_press_pos: Vector2 = Vector2.ZERO
var _console: CanvasLayer = null
var hover_tip: HoverTip ## Name and mouse actions of what is under the cursor in the overview.


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
	session.character.blocked.connect(_on_blocked)
	session.hud.set_hint(TranslationServer.translate(HINT_OVERVIEW))
	hover_tip = HoverTip.new()
	hover_tip.name = "HoverTip"
	add_child(hover_tip)
	hover_tip.still_valid = func() -> bool:
		return mode in [Mode.OVERVIEW, Mode.APPROACH] and not session.rig.is_dragging()
	cable_tool = CableTool.new()
	add_child(cable_tool)
	cable_tool.setup(session)
	_update_tool_text()


## Device (or rack) shown in the current close-up, or -1.
func closeup_device() -> int:
	return _closeup_device if mode == Mode.CLOSEUP else -1


# ------------------------------------------------------------------- input --

## Esc in the overview: give up the cable being laid, or open the menu. Read before the
## interface: a help text showing over a HUD button (a popup) would swallow the key otherwise.
## In the other modes Esc is read in _unhandled_input, after this (so the Esc that cancels a
## placement does not also open the menu).
func _input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"close_interaction") or event.is_echo():
		return
	if mode == Mode.CONSOLE: # before the terminal's text field sees it
		get_viewport().set_input_as_handled()
		_close_console()
		return
	if not (mode in [Mode.OVERVIEW, Mode.APPROACH]):
		return
	get_viewport().set_input_as_handled()
	hover_tip.hide_tip()
	if cable_tool.active():
		# First Esc gives up the cable being laid (its plugged end too: ADR 0011).
		cable_tool.cancel(TranslationServer.translate("Cable cancelado: ha vuelto al inventario."))
		_update_tool_text()
	else:
		session.menu.open()


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	var motion := event as InputEventMouseMotion
	match mode:
		Mode.OVERVIEW, Mode.APPROACH:
			if motion != null:
				_hover_overview(motion.position)
			elif button != null and button.pressed and event.is_action(&"interact"):
				hover_tip.hide_tip()
				_click_world(button.position)
			elif button != null and event.is_action(&"secondary"):
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
			elif button != null and button.pressed and event.is_action(&"interact"):
				_click_closeup(button.position)
			elif button != null and button.pressed and event.is_action(&"secondary"):
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
			elif button != null and button.pressed and event.is_action(&"interact"):
				_confirm_placement()
			elif button != null and event.is_action(&"secondary"):
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
		session.click_fx.reject() # nothing there: the ring under the cursor turns red
		return
	var collider := hit["collider"] as Node
	# An object that can be used lights up for a moment (the floor shows a ring where the
	# character goes instead).
	if collider.has_meta("computer_id") or collider.has_meta("package_stack") or collider.has_meta("device_id"):
		session.click_fx.flash_node(collider.get_parent() as Node3D)
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
		var ok := session.character.move_to(hit["position"])
		session.spawn_click_marker(hit["position"], ok)


## Under the cursor in the overview: what it is and what each mouse button does with it (the
## same rules as _click_world and _right_click_world), in a label by the cursor.
func _hover_overview(screen_pos: Vector2) -> void:
	if session.rig.is_dragging():
		hover_tip.hide_tip()
		return
	var info := hover_info(screen_pos)
	if info.is_empty():
		hover_tip.hide_tip()
	else:
		hover_tip.show_tip(screen_pos, info["title"], info["actions"])


## {"title": String, "actions": PackedStringArray} for what is under `screen_pos`, or {} over
## the bare floor, a wall or nothing.
func hover_info(screen_pos: Vector2) -> Dictionary:
	var hit := _ray(screen_pos, Layers.WORLD_PICK)
	if hit.is_empty():
		return {}
	var world := session.world
	var collider := hit["collider"] as Node
	var use := TranslationServer.translate("%s: ") % ControlsReference.keys_for([&"interact"])
	var move := TranslationServer.translate("%s: ") % ControlsReference.keys_for([&"secondary"])
	var actions := PackedStringArray()
	if collider.has_meta("computer_id"):
		actions.append(use + TranslationServer.translate("sentarte y usar el ordenador"))
		actions.append(move + TranslationServer.translate("mover el escritorio con todo lo suyo"))
		return {"title": world.get_device(collider.get_meta("computer_id")).display_name(), "actions": actions}
	if collider.has_meta("package_stack"):
		actions.append(use + TranslationServer.translate("ir a abrir la caja de arriba"))
		return {"title": TranslationServer.translate("Cajas de tu pedido (×%d)") % world.packages.size(), "actions": actions}
	if collider.has_meta("device_id"):
		var d := world.get_device(collider.get_meta("device_id"))
		var title := d.display_name()
		if d.location == &"mounted":
			var rack := world.get_device(d.rack_id)
			title = TranslationServer.translate("%s (en %s, U%d)") % [title, rack.display_name(), d.rack_u]
			actions.append(use + TranslationServer.translate("ver el rack de cerca"))
			actions.append(move + TranslationServer.translate("mover el rack"))
		else:
			actions.append(use + TranslationServer.translate("verlo de cerca (puertos y cables)"))
			if d.location == &"placed":
				actions.append(move + TranslationServer.translate("moverlo"))
			elif d.definition.placement == &"desk":
				actions.append(move + TranslationServer.translate("pasarlo a otro mueble"))
			else:
				actions.append(move + TranslationServer.translate("mover el mueble en el que está"))
		return {"title": title, "actions": actions}
	var furniture_id: StringName = collider.get_meta("furniture_id") if collider.has_meta("furniture_id") else world.flat_furniture_at(hit["position"])
	if furniture_id == &"":
		return {}
	actions.append(move + TranslationServer.translate("cambiar de sitio"))
	return {"title": world.get_furniture(furniture_id).display_name(), "actions": actions}


## Right click in the overview: move a placed rack or a piece of furniture directly (no need to
## walk to it, so whatever blocks the way can always be moved). The PC, the monitor and the
## keyboard go with the desk; the router goes from one furniture top to another.
func _right_click_world(screen_pos: Vector2) -> void:
	var hit := _ray(screen_pos, Layers.WORLD_PICK)
	if hit.is_empty():
		return
	var collider := hit["collider"] as Node
	if collider.has_meta("furniture_id"):
		start_furniture_move(collider.get_meta("furniture_id"))
		return
	if collider.has_meta("computer_id"):
		_move_with_furniture(session.world.get_device(collider.get_meta("computer_id")))
		return
	if not collider.has_meta("device_id"):
		# The floor: a rug lies there flat (nothing to hit), so look it up.
		var flat := session.world.flat_furniture_at(hit["position"])
		if flat != &"":
			start_furniture_move(flat)
		return
	var d := session.world.get_device(collider.get_meta("device_id"))
	if d.location == &"mounted":
		d = session.world.get_device(d.rack_id)
	if d.location == &"placed":
		start_move(d.id)
	elif d.location == &"fixed" and d.definition.placement == &"desk":
		start_top_move(d.id)
	elif d.location == &"fixed":
		_move_with_furniture(d)


## Starts moving a small device (the router) from one furniture top to another. Its cables stay
## plugged and are laid again from the new spot (or the spot is refused).
func start_top_move(device_id: int) -> void:
	var d := session.world.get_device(device_id)
	if d == null:
		return
	_cancel_placement()
	var note := cable_tool.interrupt(TranslationServer.translate("mover un equipo"))
	if note != "":
		session.hud.show_toast(note)
	_ghost_top_device = device_id
	_ghost_top_piece = d.furniture_id
	_ghost_yaw = d.yaw_degrees
	_ghost_pos = d.position
	_ghost = ModelUtil.instance_model(d.definition.model_path)
	for mesh: MeshInstance3D in ModelUtil.find_meshes_with_prefix(_ghost, ""):
		mesh.transparency = 0.45
	session.add_child(_ghost)
	for node: Node3D in [session.device_views.get(device_id) as Node3D, session.cables]:
		if node != null and node.visible:
			node.visible = false
			_hidden_views.append(node)
	mode = Mode.PLACEMENT
	session.hud.set_hint(TranslationServer.translate(HINT_PLACEMENT))
	_update_ghost()
	_move_ghost(session.get_viewport().get_mouse_position())


## A house device moves with the piece of furniture it belongs to.
func _move_with_furniture(d: SimDevice) -> void:
	var piece := session.world.get_furniture(d.furniture_id) if d != null else null
	if piece == null:
		session.hud.show_toast(TranslationServer.translate("%s forma parte de la habitación: no se mueve.") % d.display_name(), false)
		return
	start_furniture_move(piece.id)
	session.hud.show_toast(TranslationServer.translate("%s va con %s: se mueven juntos.") % [d.display_name(), piece.display_name()])


## Starts moving a piece of furniture with everything that goes with it (chair, PC, strip,
## router...). Cables stay plugged: they are routed again at the new spot, or the spot is refused.
func start_furniture_move(furniture_id: StringName) -> void:
	var piece := session.world.get_furniture(furniture_id)
	if piece == null:
		return
	_cancel_placement()
	var note := cable_tool.interrupt(TranslationServer.translate("mover un mueble"))
	if note != "":
		session.hud.show_toast(note)
	_ghost_furniture = furniture_id
	_ghost_yaw = piece.yaw_degrees
	_ghost_pos = piece.position
	_ghost = _furniture_ghost(piece)
	for mesh: MeshInstance3D in ModelUtil.find_meshes_with_prefix(_ghost, ""):
		mesh.transparency = 0.45
	session.add_child(_ghost)
	# The real piece, its parts and what it carries disappear while the ghost moves; the cables
	# are drawn again along their new routes once it is put down.
	var hide: Array[Node3D] = session.room.piece_nodes(furniture_id)
	for d: SimDevice in session.world.carried_by(furniture_id):
		var view := session.device_views.get(d.id) as Node3D
		if view != null:
			hide.append(view)
	hide.append(session.cables)
	for node: Node3D in hide:
		if node.visible:
			node.visible = false
			_hidden_views.append(node)
	mode = Mode.PLACEMENT
	session.hud.set_hint(TranslationServer.translate(HINT_PLACEMENT))
	_update_ghost()
	_move_ghost(session.get_viewport().get_mouse_position())


## See-through copy of a piece with its parts and what it carries, around the piece origin.
func _furniture_ghost(piece: SimFurniture) -> Node3D:
	var root := Node3D.new()
	root.name = "FurnitureGhost"
	root.add_child(ModelUtil.instance_model(piece.definition.model_path))
	for spec: Dictionary in piece.definition.parts:
		var wrapper := Node3D.new()
		wrapper.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(spec["yaw"]))), spec["offset"] as Vector3)
		wrapper.add_child(ModelUtil.instance_model(String(spec["model"])))
		root.add_child(wrapper)
	var inverse := Transform3D(Basis(Vector3.UP, deg_to_rad(piece.yaw_degrees)), piece.position).affine_inverse()
	for d: SimDevice in session.world.carried_by(piece.id):
		if d.definition.model_path == "":
			continue
		var wrapper := Node3D.new()
		wrapper.transform = inverse * Transform3D(Basis(Vector3.UP, deg_to_rad(d.yaw_degrees)), d.position)
		wrapper.add_child(ModelUtil.instance_model(d.definition.model_path))
		root.add_child(wrapper)
	return root


## Starts moving a placed device (with whatever is mounted in it). Cables must be unplugged.
func start_move(device_id: int) -> void:
	var d := session.world.get_device(device_id)
	if d == null or d.location != &"placed":
		return
	# Its cables stay plugged: the simulation re-routes them at the new spot (or refuses the spot
	# with the reason). While the ghost moves, the old cable drawing is hidden.
	_start_placement(d, true)


func _begin(kind: StringName, target_id: int) -> void:
	_target_kind = kind
	_target_id = target_id
	_approach_token += 1
	mode = Mode.APPROACH
	var destination := session.stand_point(kind, target_id)
	if kind == &"computer":
		# Sit at the desk: walk to the nearest reachable side of the chair (left, right, behind).
		destination = Vector3.INF
		var best := INF
		for spot: Vector3 in session.chair_spots():
			var length := session.character.path_length_to(spot)
			if length < best:
				best = length
				destination = spot
		if destination == Vector3.INF:
			mode = Mode.OVERVIEW
			session.hud.show_toast(TranslationServer.translate("No puedo llegar a la silla del escritorio: algo bloquea el acceso por los lados y por detrás."), false)
			return
	elif kind == &"device":
		for spot: Vector3 in session.device_stand_spots(target_id):
			if session.character.path_length_to(spot) < INF:
				destination = spot
				break
	if not session.character.move_to(destination):
		mode = Mode.OVERVIEW


func _on_blocked() -> void:
	mode = Mode.OVERVIEW
	session.hud.show_toast(TranslationServer.translate("Algo me bloquea el paso: me he detenido."), false)


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
			var note := cable_tool.interrupt(TranslationServer.translate("abrir una caja"))
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
			if note != "":
				text = note + " " + text
			session.hud.show_toast(text, r.ok)
			mode = Mode.OVERVIEW
		&"computer":
			_sit_and_use_computer()
		&"rack":
			_closeup_device = _target_id
			_rack_rear = false
			_focus(session.rack_anchor(_target_id, false), Mode.CLOSEUP)
		&"device":
			_closeup_device = _target_id
			_focus(session.device_anchor(_target_id), Mode.CLOSEUP)


## The character sits on the chair (it turns, sits, the chair turns back to the desk) and then
## the camera goes to the screen. Input waits in TRANSITION meanwhile.
func _sit_and_use_computer() -> void:
	mode = Mode.TRANSITION
	var note := cable_tool.interrupt(TranslationServer.translate("ponerte con el ordenador"))
	if note != "":
		session.hud.show_toast(note)
	await session.character.sit_down(session.room.chair, session.room.chair_rest_yaw())
	_focus(session.screen_anchor(), Mode.SCREEN)


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
	var character := session.character
	if character.seated:
		# Stands up while the camera flies back (both always finish: they have time limits).
		character.stand_up(session.room.chair, session.chair_spots(), session.room.chair_rest_yaw())
	await session.director.transition_finished
	var waited := 0.0
	while (character.busy or character.seated) and waited < PlayerCharacter.TRANSITION_TIMEOUT:
		await get_tree().process_frame
		waited += get_process_delta_time()
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
	cable_tool.cancel()
	session.hud.show_toast(TranslationServer.translate("%d cables desconectados y devueltos al inventario.") % count)
	_update_tool_text()
	refresh_panel()


func _move_from_closeup(rack_id: int) -> void:
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
	var text := "%s — %s" % [d.display_name(), _port_text(_hover_port)]
	if cable_tool.active() and not session.world.port_cable.has(_hover_port):
		text += "\n" + cable_tool.port_hint(_hover_port)
	session.hud.set_tool_text(text)


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
	if not cable_tool.active():
		if session.world.port_cable.has(ref):
			session.hud.show_toast(TranslationServer.translate("Este puerto ya tiene cable. Clic derecho para desconectarlo."))
		else:
			session.hud.show_toast(TranslationServer.translate("Elige primero un cable en el inventario (abajo)."), false)
		return
	cable_tool.click_port(ref)
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
	var note := cable_tool.interrupt(TranslationServer.translate("montar un equipo"))
	if note != "":
		session.hud.show_toast(note)
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
		if mode == Mode.PLACEMENT:
			_cancel_placement()
		cable_tool.choose(device_id) # the guide panel says what to look for
		_update_tool_text()
		return
	session.hud.show_toast(d.definition.description)


func _start_placement(d: SimDevice, moving: bool = false) -> void:
	_cancel_placement()
	var note := cable_tool.interrupt(TranslationServer.translate("mover el rack") if moving else TranslationServer.translate("colocar un objeto"))
	if note != "":
		session.hud.show_toast(note)
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
		if session.world.has_cables_inside(d):
			session.cables.visible = false # re-drawn along the new routes once it is placed
			_hidden_views.append(session.cables)
	mode = Mode.PLACEMENT
	session.hud.set_hint(TranslationServer.translate(HINT_PLACEMENT))
	_update_ghost()
	_move_ghost(session.get_viewport().get_mouse_position())


var _overlays: Dictionary = {}


func _ghost_overlay(valid: bool) -> StandardMaterial3D:
	if not _overlays.has(valid):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(UiStyle.OK, 0.28) if valid else Color(UiStyle.BAD, 0.5)
		_overlays[valid] = mat
	return _overlays[valid]


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
	if _ghost_top_device >= 0:
		_move_top_ghost(screen_pos)
		return
	var hit := _ray(screen_pos, Layers.FLOOR)
	if hit.is_empty():
		return
	var p: Vector3 = hit["position"]
	_ghost_pos = Vector3(snappedf(p.x, SNAP), 0.0, snappedf(p.z, SNAP))
	_update_ghost()


## A small device follows the pointer over furniture tops (finer steps: tops are small).
func _move_top_ghost(screen_pos: Vector2) -> void:
	var hit := _ray(screen_pos, Layers.FLOOR | Layers.FURNITURE)
	if hit.is_empty():
		return
	var p: Vector3 = hit["position"]
	var world := session.world
	_ghost_top_piece = world.furniture_top_at(p)
	var height := world.get_furniture(_ghost_top_piece).definition.top_height if _ghost_top_piece != &"" else 0.0
	_ghost_pos = Vector3(snappedf(p.x, 0.02), height, snappedf(p.z, 0.02))
	_update_ghost()


func _update_ghost() -> void:
	if _ghost == null:
		return
	_ghost.position = _ghost_pos
	_ghost.rotation_degrees.y = _ghost_yaw
	var problem := _placement_problem()
	var text: String = TranslationServer.translate("✓ Cabe aquí: clic para colocar") if problem == "" else "✗ " + problem
	# The ghost itself turns green or red, so an invalid spot is obvious before reading the text.
	var overlay := _ghost_overlay(problem == "")
	for mesh: MeshInstance3D in ModelUtil.find_meshes_with_prefix(_ghost, ""):
		mesh.material_overlay = overlay
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
				text += "\n" + TranslationServer.translate("⚠ Lejos de la regleta: los equipos del rack necesitarían unos %s m de cable de corriente y el más largo de la tienda mide %s m.") % [SimWorld.metres_needed(power["needed"]), SimWorld.metres(power["longest"], 0)]
			elif not power.is_empty() and power["needed"] > power["included"]:
				text += "\n" + TranslationServer.translate("⚠ Lejos de la regleta: los equipos del rack necesitarían unos %s m de cable de corriente; el que traen mide %s m (en la tienda hay de %s m).") % [SimWorld.metres_needed(power["needed"]), SimWorld.metres(power["included"], 0), SimWorld.metres(power["longest"], 0)]
	session.hud.set_tool_text(text)


## Simulation rules plus one presentation rule: never drop an object on the character.
func _placement_problem() -> String:
	if _ghost_top_device >= 0:
		var top_key := "top|%s|%.3f|%.3f|%.0f" % [_ghost_top_piece, _ghost_pos.x, _ghost_pos.z, _ghost_yaw]
		if top_key != _problem_key:
			_problem_key = top_key
			_problem_cache = session.world.top_problem(_ghost_top_device, _ghost_top_piece, _ghost_pos, _ghost_yaw)
		return _problem_cache
	if _ghost_furniture != &"":
		var c := session.character.global_position
		var key := "%s|%.3f|%.3f|%.0f|%.2f|%.2f" % [_ghost_furniture, _ghost_pos.x, _ghost_pos.z, _ghost_yaw, c.x, c.z]
		if key != _problem_key:
			_problem_key = key
			_problem_cache = _furniture_problem()
		return _problem_cache
	var problem := session.world.placement_problem(_ghost_device, _ghost_pos, _ghost_yaw)
	if problem != "":
		return problem
	var def := session.world.get_device(_ghost_device).definition
	var rect := SimWorld.footprint_rect(def, _ghost_pos, _ghost_yaw).grow(0.3)
	var c := session.character.global_position
	if rect.has_point(Vector2(c.x, c.z)):
		return TranslationServer.translate("Tu personaje está en medio: apártalo primero.")
	return ""


func _furniture_problem() -> String:
	var world := session.world
	var problem := world.furniture_problem(_ghost_furniture, _ghost_pos, _ghost_yaw)
	if problem != "":
		return problem
	var piece := world.get_furniture(_ghost_furniture)
	var taken: Array[Rect2] = piece.rects(piece.definition.blocks, _ghost_pos, _ghost_yaw)
	for d: SimDevice in world.carried_by(_ghost_furniture):
		if d.definition.placement == &"floor" and d.position.y < 0.01:
			taken.append(SimWorld.footprint_rect(d.definition, piece.carry(d.position, _ghost_pos, _ghost_yaw),
					d.yaw_degrees + _ghost_yaw - piece.yaw_degrees))
	var c := session.character.global_position
	for rect: Rect2 in taken:
		if rect.grow(0.25).has_point(Vector2(c.x, c.z)):
			return TranslationServer.translate("Tu personaje está en medio: apártalo primero.")
	return ""


func _confirm_placement() -> void:
	var problem := _placement_problem()
	if problem != "":
		session.hud.show_toast(problem, false)
		return
	if _ghost_top_device >= 0:
		var put := session.world.place_on_furniture(_ghost_top_device, _ghost_top_piece, _ghost_pos, _ghost_yaw)
		session.hud.show_toast(put.message, put.ok)
		if put.ok:
			_cancel_placement()
		return
	if _ghost_furniture != &"":
		var moved := session.world.move_furniture(_ghost_furniture, _ghost_pos, _ghost_yaw)
		session.hud.show_toast(moved.message, moved.ok)
		if moved.ok:
			_cancel_placement()
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
	_ghost_furniture = &""
	_ghost_top_device = -1
	_ghost_top_piece = &""
	_problem_key = ""
	if mode == Mode.PLACEMENT:
		mode = Mode.OVERVIEW
		session.hud.set_hint(TranslationServer.translate(HINT_OVERVIEW))
	_update_tool_text()


# ----------------------------------------------------------------- console --

func _open_console(device_id: int) -> void:
	_close_console()
	var note := cable_tool.interrupt(TranslationServer.translate("abrir la consola"))
	if note != "":
		session.hud.show_toast(note)
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


## Console (for tests and the automated walkthrough): the TerminalView in use, or null.
func console_terminal() -> TerminalView:
	if _console == null:
		return null
	return _console.find_children("*", "TerminalView", true, false)[0] as TerminalView


# ----------------------------------------------------------------- helpers --

func _is_rack(device_id: int) -> bool:
	var d := session.world.get_device(device_id)
	return d != null and d.definition.get_spec(RackSpec) != null


## The line above the inventory: placement previews and hovered sockets. The cable being laid has
## its own guide panel (CableTool).
func _update_tool_text() -> void:
	if mode != Mode.PLACEMENT:
		session.hud.set_tool_text("")
