class_name CableTool
extends Node
## The cable being laid, step by step (docs/INTERACTION_SYSTEM.md §9; ADR 0011):
##   step 1 — a cable was chosen in the inventory: a panel says which socket to look for
##            (a free power outlet or a power inlet; a free RJ45 port) and the compatible free
##            sockets glow; in the overview, an arrow floats over the equipment that has one.
##   step 2 — one end is plugged: the panel says where the other end must go; in a close-up the
##            compatible sockets glow green if the cable reaches them, orange if it does not.
## It ends when both ends are plugged, or it is cancelled: with Esc in the overview or the
## panel button, or by starting something else (the computer, the console, placing or moving
## an object, opening a box, mounting a device). Cancelling unplugs the plugged end and the
## cable goes back to the inventory. Which socket fits is decided by the simulation
## (SimWorld.cable_port_problem / cable_reach); this class only guides and shows.

const PULSE_SPEED := 4.0
const GLOW_DATA := Vector3(0.024, 0.021, 0.008)
const GLOW_POWER := Vector3(0.044, 0.038, 0.012)

var session: GameSession
var cable_id: int = -1 ## Chosen cable (the one with a loose end, when there is one).
var _holder: Node3D
var _glows: Array[MeshInstance3D] = []
var _arrows: Array[Node3D] = []
var _dirty: bool = true
var _shown_key: String = ""
var _time: float = 0.0
var _materials: Dictionary = {}


func setup(game: GameSession) -> void:
	session = game
	name = "CableTool"
	_holder = Node3D.new()
	_holder.name = "CableGuides"
	session.add_child(_holder)
	cable_id = session.world.pending_cable() # a loaded game can have a cable half laid
	session.world.event_emitted.connect(func(_type: StringName, _data: Dictionary) -> void: _dirty = true)


# ------------------------------------------------------------------ state --

func active() -> bool:
	if cable_id < 0:
		return false
	var d := session.world.get_device(cable_id)
	return d != null and d.location in [&"inventory", &"cabled"]


## 0 = no cable, 1 = choose the first socket, 2 = the other end.
func step() -> int:
	if not active():
		return 0
	return 2 if session.world.pending_cable() == cable_id else 1


func choose(device_id: int) -> void:
	var world := session.world
	var pending := world.pending_cable()
	if pending >= 0 and pending != device_id:
		world.cancel_cable(pending)
		session.hud.show_toast(TranslationServer.translate("El cable que tenías a medias ha vuelto al inventario."))
	cable_id = device_id
	_dirty = true


## Unplugs a loose end (if any) and forgets the cable. `reason` is shown when not empty.
func cancel(reason: String = "") -> void:
	if not active():
		cable_id = -1
		_dirty = true
		return
	var world := session.world
	if world.pending_cable() == cable_id:
		world.cancel_cable(cable_id)
	cable_id = -1
	_dirty = true
	if reason != "":
		session.hud.show_toast(reason)


## The player starts `activity` (a phrase like "usar el ordenador"): an unfinished cable is
## cancelled. Returns the sentence that tells the player ("" if there was no cable), so the
## caller can show it together with its own message.
func interrupt(activity: String) -> String:
	if not active():
		return ""
	cancel()
	return TranslationServer.translate("Cable cancelado al %s: ha vuelto al inventario.") % activity


## A click on a socket in a close-up while a cable is chosen.
func click_port(ref: String) -> void:
	var world := session.world
	var result := world.connect_cable(cable_id, ref)
	session.hud.show_toast(result.message, result.ok)
	if result.ok and world.pending_cable() != cable_id:
		cable_id = -1 # both ends plugged: done
	_dirty = true


## Hover text for a socket while a cable is chosen: whether it fits and, for the second end,
## whether the cable reaches it.
func port_hint(ref: String) -> String:
	var world := session.world
	var problem := world.cable_port_problem(cable_id, ref)
	if problem != "":
		return "✗ " + problem
	if step() == 2:
		var reach := world.cable_reach(cable_id, ref)
		if not reach["ok"]:
			return "✗ " + String(reach["reason"])
		return TranslationServer.translate("✓ Llega: harán falta unos %s m de los %s m del cable. Clic para conectar.") % [
			SimWorld.metres(reach["length"]), SimWorld.metres(_length(), 0)]
	return TranslationServer.translate("✓ Compatible: clic para conectar el primer extremo.")


# ------------------------------------------------------------------ texts --

func title() -> String:
	return TranslationServer.translate("Tendiendo un cable: %s") % session.world.get_device(cable_id).definition.model


func instruction() -> String:
	var world := session.world
	var spec := world.get_device(cable_id).definition.get_spec(CableSpec) as CableSpec
	var in_overview := session.interaction.mode in [InteractionManager.Mode.OVERVIEW, InteractionManager.Mode.APPROACH]
	var text: String
	if step() == 1:
		if spec.media == &"power":
			text = TranslationServer.translate("Paso 1 de 2 · Busca una toma libre de la regleta o la entrada de alimentación de un equipo (switch, servidor…) y haz clic en ella.")
		else:
			text = TranslationServer.translate("Paso 1 de 2 · Busca un puerto de red RJ45 libre (switch, router, servidor o PC) y haz clic en él.")
	else:
		var first := world.cable_ends[cable_id]["a"] as String
		var first_device := world.get_device(PortRef.device_id(first))
		var group := first_device.definition.find_port_group(PortRef.group(first))
		if spec.media == &"power" and group.kind == PortDefinition.Kind.POWER_C13:
			text = TranslationServer.translate("Paso 2 de 2 · Un extremo ya está en la regleta. Ahora conecta el otro en la entrada de alimentación de un equipo.")
		elif spec.media == &"power":
			text = TranslationServer.translate("Paso 2 de 2 · Un extremo ya está en %s. Ahora conecta el otro en una toma libre de la regleta.") % first_device.display_name()
		else:
			text = TranslationServer.translate("Paso 2 de 2 · Un extremo ya está en %s. Ahora conecta el otro en un puerto RJ45 libre de otro equipo.") % first_device.display_name()
	var count := world.compatible_ports(cable_id).size()
	if count == 0:
		text += " " + TranslationServer.translate("Ahora mismo no hay ningún puerto libre compatible.")
	elif in_overview:
		text += " " + TranslationServer.translate("Haz clic en un equipo marcado con una flecha para acercarte.")
	elif step() == 2:
		text += " " + TranslationServer.translate("Los puertos compatibles brillan: verde si el cable llega, naranja si no.")
	else:
		text += " " + TranslationServer.translate("Los puertos compatibles brillan en verde.")
	return text


func _length() -> float:
	var spec := session.world.get_device(cable_id).definition.get_spec(CableSpec) as CableSpec
	return spec.length_m if spec != null else 0.0


# ----------------------------------------------------------------- frames --

func _process(delta: float) -> void:
	_time += delta
	var interaction := session.interaction
	var key := "%d|%d|%d|%d" % [cable_id, step(), interaction.mode, interaction.closeup_device()]
	if _dirty or key != _shown_key:
		_dirty = false
		_shown_key = key
		_rebuild()
	var pulse := 0.55 + 0.45 * sin(_time * PULSE_SPEED)
	for glow: MeshInstance3D in _glows:
		glow.scale = Vector3.ONE * (1.0 + 0.18 * pulse)
	for i: int in _arrows.size():
		var arrow := _arrows[i]
		arrow.position.y = float(arrow.get_meta("base_y")) + 0.06 * sin(_time * 3.0 + i)
		arrow.rotation.y = _time * 1.5


func _rebuild() -> void:
	for node: Node in _holder.get_children():
		node.queue_free()
	_glows.clear()
	_arrows.clear()
	var hud := session.hud
	if not active():
		cable_id = -1
		hud.hide_cable_panel()
		return
	hud.show_cable_panel(title(), instruction(), cancel.bind(TranslationServer.translate("Cable cancelado: ha vuelto al inventario.")),
		session.interaction.mode == InteractionManager.Mode.CLOSEUP)
	var world := session.world
	var interaction := session.interaction
	var ports := world.compatible_ports(cable_id)
	match interaction.mode:
		InteractionManager.Mode.CLOSEUP:
			var shown := _closeup_devices(interaction.closeup_device())
			for ref: String in ports:
				if not shown.has(PortRef.device_id(ref)):
					continue
				var view := session.device_views.get(PortRef.device_id(ref)) as DeviceView
				if view == null or not view.port_areas.has(ref):
					continue
				var reach_ok := step() == 1 or bool(world.cable_reach(cable_id, ref)["ok"])
				_add_glow((view.port_areas[ref] as Area3D).global_transform, _is_power(ref), reach_ok)
		InteractionManager.Mode.OVERVIEW, InteractionManager.Mode.APPROACH:
			var marked: Array[int] = []
			for ref: String in ports:
				var d := world.get_device(PortRef.device_id(ref))
				var holder_id := d.rack_id if d.location == &"mounted" else d.id
				if marked.has(holder_id):
					continue
				marked.append(holder_id)
				var view := session.device_views.get(holder_id) as DeviceView
				if view != null:
					_add_arrow(view)


func _closeup_devices(device_id: int) -> Array[int]:
	var ids: Array[int] = [device_id]
	var d := session.world.get_device(device_id)
	if d != null:
		for m: SimDevice in session.world.mounted_in(d):
			ids.append(m.id)
	return ids


func _is_power(ref: String) -> bool:
	var d := session.world.get_device(PortRef.device_id(ref))
	var group := d.definition.find_port_group(PortRef.group(ref))
	return group.kind in [PortDefinition.Kind.POWER_C13, PortDefinition.Kind.POWER_C14]


func _add_glow(at: Transform3D, power: bool, reach_ok: bool) -> void:
	var glow := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = GLOW_POWER if power else GLOW_DATA
	glow.mesh = box
	glow.material_override = _material(UiStyle.OK if reach_ok else UiStyle.WARN, 0.55, true)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_holder.add_child(glow)
	glow.global_transform = at
	_glows.append(glow)


func _add_arrow(view: DeviceView) -> void:
	var arrow := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.09
	cone.bottom_radius = 0.0
	cone.height = 0.22
	cone.radial_segments = 4
	arrow.mesh = cone
	arrow.material_override = _material(UiStyle.HIGHLIGHT, 0.95, false)
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_holder.add_child(arrow)
	var top := view.global_transform * Vector3(view.local_bounds.get_center().x, view.local_bounds.end.y, view.local_bounds.get_center().z)
	arrow.global_position = top + Vector3(0.0, 0.22, 0.0)
	arrow.set_meta("base_y", arrow.position.y)
	_arrows.append(arrow)


## `depth_test`: socket glows are hidden by what is in front of them (a socket at the back of a
## device is not offered as clickable); the overview arrows are always visible.
func _material(color: Color, alpha: float, depth_test: bool) -> StandardMaterial3D:
	var key := "%s/%.2f/%s" % [color.to_html(), alpha, depth_test]
	if not _materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(color, alpha)
		mat.no_depth_test = not depth_test
		mat.render_priority = 2
		_materials[key] = mat
	return _materials[key]
