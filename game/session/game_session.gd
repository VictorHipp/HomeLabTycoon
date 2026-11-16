class_name GameSession
extends Node3D
## Root of the playable first-mission test: owns the SimWorld (the only source of truth) and
## builds the presentation around it — room, character, camera, device/package/cable views,
## HUD and the computer screen. Views re-sync whenever the simulation emits an event.

const PC_FURNITURE := &"desk" ## The monitor and the keyboard are parts of this piece.
const CHARACTER_START := Vector3(0.35, 0.0, 0.55)
const HUD_REFRESH_SECONDS := 0.25
const CLICK_MARKER_SECONDS := 0.55
const CAMERA_ROOM_MARGIN := 0.12 ## Close-up cameras never go closer than this to a wall.
const STAND_ROOM_MARGIN := 0.25 ## Stand points stay on walkable floor (agent radius 0.2).

var world: SimWorld
var room: RoomView
var character: PlayerCharacter
var camera: Camera3D
var rig: OverviewCameraRig
var director: CameraDirector
var hud: Hud
var screen: ComputerScreen
var interaction: InteractionManager
var menu: GameMenu
var cables: CableRenderer
var click_fx: ClickFeedback ## Rings under the cursor on every click; red when it did nothing.
var device_views: Dictionary = {} ## device id -> DeviceView
var package_stack: PackageView ## All waiting boxes, stacked in the delivery zone.
var monitor: Node3D ## Part of the desk (RoomView): clicking it opens the computer.
var pc_id: int = -1

var _views_dirty: bool = true
var _hud_timer: float = 0.0
var _click_marker: MeshInstance3D
var _click_marker_time: float = 0.0

## A loaded save waiting for the scene to be rebuilt (load = reload the scene, so no view or
## panel keeps state from the previous game).
static var _pending_load: Dictionary = {}


func _ready() -> void:
	InputBindings.ensure_defaults()
	var nav_map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(nav_map, 0.05)
	NavigationServer3D.map_set_cell_height(nav_map, 0.05)
	get_viewport().msaa_3d = Viewport.MSAA_4X
	var loading := _pending_load
	_pending_load = {}
	world = BedroomScenario.restore(loading["sim"]) if not loading.is_empty() else BedroomScenario.create()
	pc_id = world.devices_of(&"computer")[0].id
	_build_environment()
	room = RoomView.new()
	room.name = "Room"
	add_child(room)
	room.build(world)
	_build_pc_extras()
	_build_delivery_zone()
	package_stack = PackageView.new()
	room.objects.add_child(package_stack)
	package_stack.setup()
	cables = CableRenderer.new()
	cables.name = "Cables"
	add_child(cables)
	character = PlayerCharacter.new()
	character.name = "Character"
	add_child(character)
	character.global_position = CHARACTER_START
	camera = Camera3D.new()
	camera.fov = 42.0
	add_child(camera)
	camera.current = true
	rig = OverviewCameraRig.new()
	rig.camera = camera
	add_child(rig)
	rig.recenter_requested.connect(func() -> void: rig.set_focus(character.global_position + Vector3(0.0, 0.5, 0.0)))
	director = CameraDirector.new()
	add_child(director)
	director.setup(camera, rig)
	hud = Hud.new()
	add_child(hud)
	hud.setup(world)
	screen = ComputerScreen.new()
	add_child(screen)
	screen.setup(world, pc_id)
	interaction = InteractionManager.new()
	add_child(interaction)
	interaction.setup(self)
	menu = GameMenu.new()
	add_child(menu)
	menu.setup(self)
	hud.menu_requested.connect(menu.open.bind(&"controls"))
	screen.menu_requested.connect(menu.open.bind(&"controls"))
	_build_click_marker()
	click_fx = ClickFeedback.new()
	click_fx.name = "ClickFeedback"
	add_child(click_fx)
	hud.toast_shown.connect(func(ok: bool) -> void:
		if not ok:
			click_fx.reject())
	screen.message_shown.connect(func(ok: bool) -> void:
		if not ok:
			click_fx.reject())
	world.event_emitted.connect(_on_world_event)
	_sync_views()
	hud.refresh()
	if loading.is_empty():
		hud.show_toast(TranslationServer.translate("Bienvenido a tu habitación. Haz clic en el ordenador para abrir la tienda y empezar la misión."))
	else:
		_apply_presentation(loading.get("session", {}))
		var note := ""
		if not world.packages.is_empty() and world.delivery_zone_blocked():
			note = " " + TranslationServer.translate("La zona de entregas estaba ocupada: las cajas esperan junto a ella.")
		hud.show_toast(TranslationServer.translate("Partida cargada.") + note)
	print("HomeLabTycoon boot OK | Godot %s | first mission test" % Engine.get_version_info()["string"])
	if WalkthroughDriver.requested_dir() != "":
		WalkthroughDriver.attach(self)


# --------------------------------------------------------------- save / load --

## Presentation part of the save: where the character stands and how the camera looks.
func capture_presentation() -> Dictionary:
	var p := character.save_position()
	return {
		"character": {"position": [p.x, p.y, p.z], "facing": character.model.rotation.y},
		"camera": {"yaw": rig.target_yaw_deg, "pitch": rig.target_pitch_deg, "distance": rig.target_distance,
			"focus": [rig.target_focus.x, rig.target_focus.y, rig.target_focus.z]},
	}


func _apply_presentation(data: Dictionary) -> void:
	var c: Dictionary = data.get("character", {})
	if c.has("position"):
		var p: Array = c["position"]
		character.global_position = Vector3(float(p[0]), 0.0, float(p[2]))
		character.model.rotation.y = float(c.get("facing", 0.0))
		# The navigation mesh is baked after loading: then make sure the character stands on it.
		room.nav_region.bake_finished.connect(_snap_character_to_floor, CONNECT_ONE_SHOT)
	var cam: Dictionary = data.get("camera", {})
	if cam.has("yaw"):
		rig.target_yaw_deg = float(cam["yaw"])
		rig.target_pitch_deg = float(cam["pitch"])
		rig.target_distance = float(cam["distance"])
		var f: Array = cam["focus"]
		rig.target_focus = Vector3(float(f[0]), float(f[1]), float(f[2]))
		rig.snap()


func _snap_character_to_floor() -> void:
	var map := get_world_3d().navigation_map
	var closest := NavigationServer3D.map_get_closest_point(map, character.global_position)
	if Vector2(closest.x - character.global_position.x, closest.z - character.global_position.z).length() > 0.05:
		character.global_position = Vector3(closest.x, 0.0, closest.z)


## Returns {"ok", "message"}.
func save_game() -> Dictionary:
	return SaveService.write(SaveGame.build(world, capture_presentation()))


## Reads the save and rebuilds the scene with it. Returns {"ok", "message"}.
func load_game() -> Dictionary:
	var r := SaveService.read()
	if not r["ok"]:
		return r
	_pending_load = r["document"]
	get_tree().paused = false
	get_tree().reload_current_scene.call_deferred()
	return {"ok": true, "message": TranslationServer.translate("Cargando la partida…")}


func _process(delta: float) -> void:
	world.advance(delta)
	room.update_cutaway(camera.global_position)
	if _views_dirty:
		_sync_views()
	_hud_timer -= delta
	if _hud_timer <= 0.0:
		_hud_timer = HUD_REFRESH_SECONDS
		hud.refresh()
		screen.refresh()
	if _click_marker.visible:
		_click_marker_time += delta
		var k := clampf(_click_marker_time / CLICK_MARKER_SECONDS, 0.0, 1.0)
		_click_marker.scale = Vector3.ONE * lerpf(0.4, 1.25, 1.0 - pow(1.0 - k, 3.0))
		var mat := _click_marker.material_override as StandardMaterial3D
		mat.albedo_color.a = 1.0 - k
		if k >= 1.0:
			_click_marker.visible = false


func _on_world_event(type: StringName, data: Dictionary) -> void:
	_views_dirty = true
	match type:
		&"furniture_moved", &"state_loaded":
			room.sync_furniture(world)
		&"package_delivered":
			hud.show_toast(TranslationServer.translate("¡Ha llegado tu pedido! Las cajas están en la zona de entregas, junto a la puerta (×%d).") % world.packages.size())
			# If the character stands where the boxes appear, step it out once the floor is re-baked.
			var spot := world.delivery_spot()
			var c := character.global_position
			if Rect2(spot.x - 0.5, spot.z - 0.45, 1.0, 0.9).has_point(Vector2(c.x, c.z)):
				room.nav_region.bake_finished.connect(_snap_character_to_floor, CONNECT_ONE_SHOT)
		&"device_running":
			var d := world.get_device(data["device_id"])
			if d.definition.has_power_button or d.definition.category == &"switch":
				hud.show_toast(TranslationServer.translate("%s está encendido.") % d.display_name())
		&"money_changed":
			var delta: int = data.get("delta", 0)
			if delta != 0:
				hud.float_delta(("+%d cr" if delta > 0 else "−%d cr") % absi(delta), delta > 0)
		&"xp_changed":
			var gained: int = data.get("delta", 0)
			if gained > 0:
				hud.float_delta("+%d XP" % gained, true)
			if data.get("level_up", false):
				hud.show_toast(TranslationServer.translate("¡Subes a nivel %d!") % data["level"])
			elif gained > 0 and String(data.get("text", "")) != "":
				hud.show_toast("%s · +%d XP" % [data["text"], gained])
		&"mission_completed":
			hud.show_banner(TranslationServer.translate("¡Misión completada!\n«%s»\n\n+%d créditos · +%d XP\n\nTu PC y tu primer servidor ya se comunican a través del switch.\nMientras siga encendido y en la red, el servidor te dará unos pocos créditos por hora (mira «Mi cuenta» en el PC).\nFin de la prueba de la primera misión: puedes seguir experimentando.") % [world.mission.definition.title, data["credits"], data["xp"]])
	if interaction != null:
		interaction.refresh_panel()


# ------------------------------------------------------------------- views --

func _sync_views() -> void:
	_views_dirty = false
	var structural := false
	# Racks and floor devices first, so mounted devices can find their rack view.
	var ordered: Array = world.devices.values()
	ordered.sort_custom(func(a: SimDevice, b: SimDevice) -> bool:
		return int(a.location == &"mounted") < int(b.location == &"mounted"))
	for d: SimDevice in ordered:
		var show := d.is_in_world() and d.definition.model_path != ""
		if show and not device_views.has(d.id):
			var view := DeviceView.new()
			room.objects.add_child(view)
			view.setup(d)
			device_views[d.id] = view
			structural = true
		elif not show and device_views.has(d.id):
			(device_views[d.id] as Node).queue_free()
			device_views.erase(d.id)
			structural = true
		if show:
			var view := device_views[d.id] as DeviceView
			var before := view.global_transform
			_place_view(view, d)
			if not view.global_transform.is_equal_approx(before):
				structural = true
			view.refresh(world)
	var spot := world.delivery_spot()
	if not world.packages.is_empty():
		spot = world.packages[world.top_package_id()]["position"]
	if package_stack.refresh(world.packages.size(), spot):
		structural = true
	cables.rebuild(world, port_global_transform)
	if structural:
		room.request_bake()


func _place_view(view: DeviceView, d: SimDevice) -> void:
	if d.location == &"mounted":
		var rack_view := device_views.get(d.rack_id) as DeviceView
		if rack_view == null:
			return
		var u1 := ModelUtil.marker_transform(rack_view.model, "RACK_U1")
		var offset := Transform3D(Basis.IDENTITY, Vector3(0.0, (d.rack_u - 1) * SimWorld.RACK_UNIT_M, 0.0))
		view.global_transform = rack_view.global_transform * (u1["transform"] as Transform3D) * offset
	else:
		view.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(d.yaw_degrees)), d.position)


func port_global_transform(port_ref: String) -> Dictionary:
	var view := device_views.get(PortRef.device_id(port_ref)) as DeviceView
	if view == null:
		return {"found": false}
	return view.port_global_transform(port_ref)


# ------------------------------------------------- interaction geometry -----

## Where the character can stand to sit on the desk chair: beside it (left, right) or behind it,
## in the chair's resting frame. The interaction walks to the nearest reachable one.
func chair_spots() -> Array[Vector3]:
	var c := room.chair.global_position
	var basis := Basis(Vector3.UP, room.chair_rest_yaw())
	var spots: Array[Vector3] = []
	for local: Vector3 in [Vector3(0.5, 0.0, -0.07), Vector3(-0.5, 0.0, -0.07), Vector3(0.0, 0.0, -0.6)]:
		var p := c + basis * local
		spots.append(Vector3(p.x, 0.0, p.z))
	return spots


func stand_point(kind: StringName, target_id: int) -> Vector3:
	match kind:
		&"computer":
			return chair_spots()[0]
		&"package":
			var p := package_stack.global_position
			return clamp_to_room(p + Vector3(-p.x, 0.0, -p.z).normalized() * 0.55, STAND_ROOM_MARGIN)
		&"rack":
			var rack_view := device_views[target_id] as DeviceView
			var marker := ModelUtil.marker_transform(rack_view.model, "STAND_POINT")
			return clamp_to_room(rack_view.global_transform * (marker["transform"] as Transform3D).origin, STAND_ROOM_MARGIN)
	var view := device_views[target_id] as DeviceView
	var pos := view.global_position
	var toward_room := Vector3(-pos.x, 0.0, -pos.z).normalized()
	return Vector3(pos.x, 0.0, pos.z) + toward_room * 0.65


## Where the character can stand to use a device standing in the room (strip, router): the usual
## spot (towards the middle of the room) first, then round the device starting on the side its
## ports face. After rearranging (§8.2), a device can be anywhere: the interaction walks to the first
## one that can be reached.
func device_stand_spots(device_id: int) -> Array[Vector3]:
	var view := device_views[device_id] as DeviceView
	var pos := view.global_position
	var facing := Vector3.ZERO
	for area: Area3D in view.port_areas.values():
		facing += area.global_basis.z
	facing.y = 0.0
	if facing.length() < 0.01:
		facing = Vector3(-pos.x, 0.0, -pos.z)
	var base := atan2(facing.x, facing.z)
	var spots: Array[Vector3] = [stand_point(&"device", device_id)]
	for k: int in [0, 1, -1, 2, -2, 3, -3, 4]:
		var a := base + k * PI / 4.0
		for r: float in [0.6, 0.8]:
			spots.append(clamp_to_room(Vector3(pos.x + sin(a) * r, 0.0, pos.z + cos(a) * r), STAND_ROOM_MARGIN))
	return spots


func target_center(kind: StringName, target_id: int) -> Vector3:
	match kind:
		&"computer":
			return monitor.global_position
		&"package":
			return package_stack.global_position + Vector3(0.0, 0.3, 0.0)
	return (device_views[target_id] as DeviceView).global_bounds_center()


func screen_anchor() -> Transform3D:
	var marker := ModelUtil.marker_transform(monitor.get_child(0) as Node3D, "CAM_screen")
	return monitor.global_transform * (marker["transform"] as Transform3D)


func rack_anchor(rack_id: int, rear: bool) -> Transform3D:
	var rack_view := device_views[rack_id] as DeviceView
	var marker := ModelUtil.marker_transform(rack_view.model, "CAM_rack_rear" if rear else "CAM_rack_front")
	var anchor := rack_view.global_transform * (marker["transform"] as Transform3D)
	# The model's anchor is 0.8 m from the face; with the rack's 0.5 m service clearance it can
	# fall behind a wall. Then the camera moves into the room and looks at the face again.
	var bounds := rack_view.local_bounds
	var c := bounds.get_center()
	var face := rack_view.global_transform * Vector3(c.x, c.y, bounds.position.z if rear else bounds.end.z)
	var origin := clamp_to_room(anchor.origin, CAMERA_ROOM_MARGIN)
	var clear := _clear_view(face, origin, rack_id)
	if clear.is_equal_approx(anchor.origin):
		return anchor
	return Transform3D(Basis.looking_at(face - clear, Vector3.UP), clear)


## A camera position from which `target` is seen without furniture or other devices in between
## (a chair or a desk behind the rack): the wanted `origin` if it is clear, otherwise closer to
## the target and / or higher. The rack itself and what is mounted in it do not count.
func _clear_view(target: Vector3, origin: Vector3, rack_id: int) -> Vector3:
	var exclude: Array[RID] = []
	var rack := world.get_device(rack_id)
	for d: SimDevice in [rack] + world.mounted_in(rack):
		var view := device_views.get(d.id) as DeviceView
		if view != null:
			exclude.append(view.body.get_rid())
	var space := get_world_3d().direct_space_state
	for lift: float in [0.0, 0.2, 0.4, 0.65]:
		for pull: float in [1.0, 0.85, 0.7, 0.55]:
			var candidate := target + (origin - target) * pull + Vector3(0.0, lift, 0.0)
			var query := PhysicsRayQueryParameters3D.create(target, candidate, Layers.FURNITURE | Layers.DEVICES | Layers.WALLS)
			query.exclude = exclude
			query.hit_from_inside = true
			if space.intersect_ray(query).is_empty():
				return candidate
	return origin


## `point` moved horizontally inside the room, `margin` metres away from the walls.
func clamp_to_room(point: Vector3, margin: float) -> Vector3:
	var b := world.room_bounds.grow(-margin)
	return Vector3(clampf(point.x, b.position.x, b.end.x), point.y, clampf(point.z, b.position.y, b.end.y))


## Generic close-up: look at the device from the side where its ports are.
func device_anchor(device_id: int) -> Transform3D:
	var view := device_views[device_id] as DeviceView
	var center := view.global_bounds_center()
	var dir := Vector3.ZERO
	for area: Area3D in view.port_areas.values():
		dir += area.global_basis.z
	var toward_room := Vector3(-center.x, 0.0, -center.z).normalized()
	if dir.length() < 0.01:
		dir = toward_room
	dir = dir.normalized()
	if absf(dir.y) > 0.9:
		dir = (Vector3.UP * 0.75 + toward_room * 0.65).normalized()
	var size := view.local_bounds.size.length()
	var origin := clamp_to_room(center + dir * clampf(size * 1.4, 0.55, 1.4) + Vector3(0.0, 0.18, 0.0), CAMERA_ROOM_MARGIN)
	return Transform3D(Basis.looking_at(center - origin, Vector3.UP), origin)


## Clickable unit areas on the front of a rack (mount mode).
func create_rack_slots(rack_id: int) -> Array[Area3D]:
	var rack_view := device_views[rack_id] as DeviceView
	var spec := world.get_device(rack_id).definition.get_spec(RackSpec) as RackSpec
	var u1 := ModelUtil.marker_transform(rack_view.model, "RACK_U1")["transform"] as Transform3D
	var result: Array[Area3D] = []
	for u: int in range(1, spec.capacity_u + 1):
		var area := Area3D.new()
		area.collision_layer = Layers.SLOTS
		area.collision_mask = 0
		area.monitoring = false
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		# Thin: with a steep close-up camera a deep box would let the unit above catch the click.
		box.size = Vector3(0.45, SimWorld.RACK_UNIT_M * 0.95, 0.01)
		shape.shape = box
		area.add_child(shape)
		area.set_meta("u", u)
		rack_view.add_child(area)
		area.transform = u1 * Transform3D(Basis.IDENTITY, Vector3(0.0, (u - 0.5) * SimWorld.RACK_UNIT_M, 0.0))
		result.append(area)
	return result


## Ring on the floor where the player clicked: it opens and fades. Teal when the character goes
## there, red when it cannot get there.
func spawn_click_marker(point: Vector3, ok: bool = true) -> void:
	_click_marker.global_position = point + Vector3(0.0, 0.015, 0.0)
	_click_marker.scale = Vector3.ONE * 0.4
	_click_marker_time = 0.0
	var mat := _click_marker.material_override as StandardMaterial3D
	var color := UiStyle.HIGHLIGHT if ok else UiStyle.BAD
	mat.albedo_color = color
	mat.emission = color
	_click_marker.visible = true


# ------------------------------------------------------------------- build --

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.118, 0.141, 0.188)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.86, 0.88, 0.92)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = 0.8
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.2
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 160, 0)
	sun.light_color = Color(1, 0.91, 0.78)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	sun.shadow_normal_bias = 2.0
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 12.0
	add_child(sun)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.2, 2.3, -0.2)
	lamp.light_color = Color(1, 0.85, 0.66)
	lamp.light_energy = 1.1
	lamp.omni_range = 5.5
	lamp.shadow_enabled = true
	add_child(lamp)


func _build_pc_extras() -> void:
	# The PC device is the tower; monitor and keyboard stand on the desk (parts of it, so they
	# move with it), belong to the PC and open its desktop.
	monitor = room.part(PC_FURNITURE, "monitor")
	for node: Node3D in [monitor, room.part(PC_FURNITURE, "keyboard")]:
		ModelUtil.add_box_body(node, ModelUtil.local_aabb(node.get_child(0) as Node3D), Layers.DEVICES).set_meta("computer_id", pc_id)


## Floor mark of the reserved delivery zone (always visible, so the player knows it is kept free).
func _build_delivery_zone() -> void:
	var zone := world.delivery_zone
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(UiStyle.MUSTARD, 0.28)
	var mark := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = zone.size
	mark.mesh = plane
	mark.material_override = mat
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mark.position = Vector3(zone.get_center().x, 0.006, zone.get_center().y)
	mark.name = "DeliveryZone"
	room.add_child(mark)
	var text := Label3D.new()
	text.text = TranslationServer.translate("ENTREGAS")
	text.font_size = 48
	text.pixel_size = 0.0025
	text.modulate = Color(UiStyle.INK, 0.75)
	text.outline_size = 0
	text.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	text.position = Vector3(0.0, 0.002, zone.size.y / 2.0 - 0.07)
	mark.add_child(text)


func _build_click_marker() -> void:
	_click_marker = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.13
	ring.outer_radius = 0.155
	_click_marker.mesh = ring
	var mat := StandardMaterial3D.new()
	mat.albedo_color = UiStyle.HIGHLIGHT
	mat.emission_enabled = true
	mat.emission = UiStyle.HIGHLIGHT
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_click_marker.material_override = mat
	_click_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_click_marker.visible = false
	add_child(_click_marker)
