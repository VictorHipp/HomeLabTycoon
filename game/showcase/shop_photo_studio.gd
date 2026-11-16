extends Node3D
## Development tool (not part of the game): takes the product photos of the shop from the game's
## own models — two views per purchasable item on a light "studio" background — and saves them as
## res://assets/shop/<item id>_<n>.png. Cables have no model: they are drawn as a coil with the
## same tube and colours as in the room, plus their plugs. Run it with
## tools\capture_shop_photos.ps1 (opens a window for a few seconds).

const OUT_DIR := "res://assets/shop"
const BACKGROUND := Color("#F3F4F6")
const SETTLE_FRAMES := 12

var _camera: Camera3D
var _subject: Node3D


func _ready() -> void:
	get_viewport().msaa_3d = Viewport.MSAA_8X
	_build_studio()
	_capture_all.call_deferred()


func _build_studio() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKGROUND
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.92, 0.93, 0.96)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, 35, 0)
	key.light_energy = 1.6
	key.shadow_enabled = true
	key.shadow_blur = 2.5
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -140, 0)
	fill.light_energy = 0.55
	add_child(fill)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	floor.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BACKGROUND
	mat.roughness = 1.0
	floor.material_override = mat
	add_child(floor)
	_camera = Camera3D.new()
	_camera.fov = 30.0
	add_child(_camera)
	_camera.current = true


func _capture_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var catalog := Catalog.load_default()
	var saved := 0
	for def: HardwareDefinition in catalog.purchasable_items():
		for view: int in [1, 2]:
			_show(def, view)
			for _i: int in SETTLE_FRAMES:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			var path := "%s/%s_%d.png" % [OUT_DIR, def.id, view]
			var err := image.save_png(ProjectSettings.globalize_path(path))
			print("SHOP PHOTO %s %s" % [path, error_string(err)])
			if err == OK:
				saved += 1
	print("SHOP PHOTOS %d saved" % saved)
	get_tree().quit(0)


func _show(def: HardwareDefinition, view: int) -> void:
	if _subject != null:
		_subject.queue_free()
	_subject = Node3D.new()
	add_child(_subject)
	var cable := def.get_spec(CableSpec) as CableSpec
	if cable != null:
		_build_coil(cable, view)
	else:
		_subject.add_child(ModelUtil.instance_model(def.model_path))
	var box := ModelUtil.local_aabb(_subject)
	var centre := box.get_center()
	var radius := box.size.length() / 2.0 * 0.82 # frames the object, not its bounding sphere
	var direction := Vector3(0.95, 0.62, 1.35).normalized() if view == 1 else Vector3(-0.95, 0.55, -1.35).normalized()
	if cable != null:
		direction = Vector3(0.35, 1.25, 0.9).normalized() if view == 1 else Vector3(0.55, 0.45, 1.0).normalized()
	var distance := radius / sin(deg_to_rad(_camera.fov) / 2.0) * 1.08
	_camera.global_position = centre + direction * distance
	_camera.look_at(centre, Vector3.UP)


## A loosely coiled cable lying on the table, its two ends out with their plugs. View 2: a
## close-up of one end and its plug.
func _build_coil(cable: CableSpec, view: int) -> void:
	var power := cable.media == &"power"
	var radius := CableRenderer.RADIUS_POWER if power else CableRenderer.RADIUS_DATA
	var coil_r := 0.075
	var turns := clampf(cable.length_m / (TAU * 0.11), 1.3, 6.0)
	var points := PackedVector3Array()
	var start := Vector3(coil_r + 0.17, radius, 0.0)
	points.append(start)
	points.append(Vector3(coil_r + 0.05, radius, 0.0))
	var steps := int(turns * 48.0)
	for k: int in steps + 1:
		var t := float(k) / 48.0 * TAU
		var r := coil_r + 0.011 * t / TAU # each turn a little wider, like a real coil
		var y := radius + 0.35 * radius * sin(t * 1.5) * minf(1.0, t / PI) # turns resting on each other
		points.append(Vector3(cos(t) * r, y, sin(t) * r))
	var last := points[points.size() - 1]
	var outward := Vector3(last.x, 0.0, last.z).normalized()
	var tangent := outward.cross(Vector3.DOWN).normalized()
	var tail := Vector3(last.x, radius, last.z) + tangent * 0.08 + outward * 0.14
	points.append(tail)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = CableRenderer.COLOR_POWER if power else CableRenderer.COLOR_COPPER
	mat.roughness = 0.55
	var mesh := MeshInstance3D.new()
	mesh.material_override = mat
	_subject.add_child(mesh)
	if view == 1:
		mesh.mesh = CableRenderer.tube_mesh(CableRenderer.round_corners(points), radius)
		_plug(start, Vector3(1, 0, 0), power, radius, mat)
		_plug(tail, (tail - last).normalized(), power, radius, mat)
	else:
		mesh.mesh = CableRenderer.tube_mesh(CableRenderer.round_corners(points.slice(0, 3)), radius)
		_plug(start, Vector3(1, 0, 0), power, radius, mat)


## Plug at the cable end `at`, pointing along `out`: a boot in the cable colour, then the body
## (RJ45: clear plastic with gold contacts; power: black block).
func _plug(at: Vector3, out: Vector3, power: bool, radius: float, cable_mat: StandardMaterial3D) -> void:
	var holder := Node3D.new()
	_subject.add_child(holder)
	holder.position = Vector3(at.x, 0.0, at.z)
	holder.basis = Basis.looking_at(-Vector3(out.x, 0.0, out.z).normalized(), Vector3.UP) # +Z = out
	var boot_size := Vector3(radius * 2.6, radius * 2.6, 0.018)
	_box(holder, boot_size, Vector3(0, boot_size.y / 2.0, boot_size.z / 2.0), cable_mat)
	var body_size := Vector3(0.026, 0.02, 0.04) if power else Vector3(0.0125, 0.011, 0.024)
	var mat := StandardMaterial3D.new()
	if power:
		mat.albedo_color = Color("#1A1A1A")
		mat.roughness = 0.6
	else:
		mat.albedo_color = Color(0.62, 0.72, 0.82, 0.93)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.15
	var body_z := boot_size.z + body_size.z / 2.0
	_box(holder, body_size, Vector3(0, body_size.y / 2.0, body_z), mat)
	if not power:
		var gold := StandardMaterial3D.new()
		gold.albedo_color = Color("#D4A62A")
		gold.metallic = 0.8
		gold.roughness = 0.3
		_box(holder, Vector3(0.009, 0.0015, 0.007), Vector3(0, body_size.y, body_z + body_size.z / 2.0 - 0.0045), gold)


func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = at
	parent.add_child(mesh)
