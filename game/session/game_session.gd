class_name GameSession
extends Node3D
## Root of the playable first-mission test: owns the SimWorld (the only source of truth) and
## builds the presentation around it — room, character, camera, device/package/cable views,
## HUD and the computer screen. Views re-sync whenever the simulation emits an event.

const PC_STAND := Vector3(-0.05, 0.0, -0.55)
const MONITOR_MODEL := "res://assets/models/compute/monitor_old.glb"
const KEYBOARD_MODEL := "res://assets/models/compute/keyboard_mouse.glb"
const MONITOR_POSITION := Vector3(0.40, 0.75, -1.30)
const KEYBOARD_POSITION := Vector3(0.40, 0.75, -1.02)
const CHARACTER_START := Vector3(0.35, 0.0, 0.55)
const HUD_REFRESH_SECONDS := 0.25
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
var cables: CableRenderer
var device_views: Dictionary = {} ## device id -> DeviceView
var package_views: Dictionary = {} ## package id -> PackageView
var monitor: Node3D
var pc_id: int = -1

var _views_dirty: bool = true
var _hud_timer: float = 0.0
var _click_marker: MeshInstance3D


func _ready() -> void:
	InputBindings.ensure_defaults()
	var nav_map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(nav_map, 0.05)
	NavigationServer3D.map_set_cell_height(nav_map, 0.05)
	get_viewport().msaa_3d = Viewport.MSAA_4X
	world = BedroomScenario.create()
	pc_id = world.devices_of(&"computer")[0].id
	_build_environment()
	room = RoomView.new()
	room.name = "Room"
	add_child(room)
	room.build()
	_build_pc_extras()
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
	_build_click_marker()
	world.event_emitted.connect(_on_world_event)
	_sync_views()
	hud.refresh()
	hud.show_toast(TranslationServer.translate("Bienvenido a tu habitación. Haz clic en el ordenador para abrir la tienda y empezar la misión."))
	print("HomeLabTycoon boot OK | Godot %s | first mission test" % Engine.get_version_info()["string"])
	var walkthrough_dir := WalkthroughDriver.requested_dir()
	if walkthrough_dir != "":
		var driver := WalkthroughDriver.new()
		add_child(driver)
		driver.start(self, walkthrough_dir)


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
		_click_marker.scale *= 0.94
		if _click_marker.scale.x < 0.1:
			_click_marker.visible = false


func _on_world_event(type: StringName, data: Dictionary) -> void:
	_views_dirty = true
	match type:
		&"package_delivered":
			hud.show_toast(TranslationServer.translate("¡Ha llegado tu pedido! Los paquetes están junto a la puerta."))
		&"device_running":
			var d := world.get_device(data["device_id"])
			if d.definition.has_power_button or d.definition.category == &"switch":
				hud.show_toast(TranslationServer.translate("%s está encendido.") % d.display_name())
		&"mission_completed":
			hud.show_banner(TranslationServer.translate("¡Misión completada!\n«%s»\n\n+%d créditos · +%d XP\n\nTu PC y tu primer servidor ya se comunican a través del switch.\nFin de la prueba de la primera misión: puedes seguir experimentando.") % [world.mission.definition.title, data["credits"], data["xp"]])
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
	for package_id: int in world.packages:
		if not package_views.has(package_id):
			var pv := PackageView.new()
			room.objects.add_child(pv)
			pv.setup(world.packages[package_id])
			package_views[package_id] = pv
			structural = true
	for package_id: int in package_views.keys():
		if not world.packages.has(package_id):
			(package_views[package_id] as Node).queue_free()
			package_views.erase(package_id)
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

func stand_point(kind: StringName, target_id: int) -> Vector3:
	match kind:
		&"computer":
			return PC_STAND
		&"package":
			var pv := package_views.get(target_id) as PackageView
			return pv.global_position + (Vector3.ZERO - pv.global_position).normalized() * 0.55
		&"rack":
			var rack_view := device_views[target_id] as DeviceView
			var marker := ModelUtil.marker_transform(rack_view.model, "STAND_POINT")
			return clamp_to_room(rack_view.global_transform * (marker["transform"] as Transform3D).origin, STAND_ROOM_MARGIN)
	var view := device_views[target_id] as DeviceView
	var pos := view.global_position
	var toward_room := Vector3(-pos.x, 0.0, -pos.z).normalized()
	return Vector3(pos.x, 0.0, pos.z) + toward_room * 0.65


func target_center(kind: StringName, target_id: int) -> Vector3:
	match kind:
		&"computer":
			return MONITOR_POSITION
		&"package":
			return (package_views[target_id] as Node3D).global_position
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
	if origin.is_equal_approx(anchor.origin):
		return anchor
	return Transform3D(Basis.looking_at(face - origin, Vector3.UP), origin)


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


func spawn_click_marker(point: Vector3) -> void:
	_click_marker.global_position = point + Vector3(0.0, 0.01, 0.0)
	_click_marker.scale = Vector3.ONE
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
	# The PC device is the tower; monitor and keyboard belong to it and open its desktop.
	monitor = Node3D.new()
	monitor.name = "Monitor"
	monitor.position = MONITOR_POSITION
	monitor.add_child(ModelUtil.instance_model(MONITOR_MODEL))
	room.objects.add_child(monitor)
	ModelUtil.add_box_body(monitor, ModelUtil.local_aabb(monitor.get_child(0) as Node3D), Layers.DEVICES).set_meta("computer_id", pc_id)
	var keyboard := Node3D.new()
	keyboard.name = "Keyboard"
	keyboard.position = KEYBOARD_POSITION
	keyboard.add_child(ModelUtil.instance_model(KEYBOARD_MODEL))
	room.objects.add_child(keyboard)
	ModelUtil.add_box_body(keyboard, ModelUtil.local_aabb(keyboard.get_child(0) as Node3D), Layers.DEVICES).set_meta("computer_id", pc_id)


func _build_click_marker() -> void:
	_click_marker = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.12
	ring.outer_radius = 0.16
	_click_marker.mesh = ring
	var mat := StandardMaterial3D.new()
	mat.albedo_color = UiStyle.HIGHLIGHT
	mat.emission_enabled = true
	mat.emission = UiStyle.HIGHLIGHT
	_click_marker.material_override = mat
	_click_marker.visible = false
	add_child(_click_marker)
