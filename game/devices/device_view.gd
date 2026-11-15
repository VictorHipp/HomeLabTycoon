class_name DeviceView
extends Node3D
## 3D view of one SimDevice: model, collider, clickable port areas and LEDs.
## It reads the simulation and never changes it; clicks become commands in InteractionManager.
## LED colours follow the simulated state (docs/NETWORK_SIMULATION.md §9).

const COLOR_GREEN := Color("#4ADE80")
const COLOR_AMBER := Color("#F5A524")
const COLOR_RED := Color("#EF4444")
const COLOR_OFF := Color("#2A2F38")
## Click areas of the sockets: thin in depth, so from a steep close-up camera the socket above
## never catches the click meant for the one below (switch ports are 17 mm apart).
const PORT_SIZE_DATA := Vector3(0.018, 0.015, 0.006)
const PORT_SIZE_POWER := Vector3(0.036, 0.03, 0.01)

static var _led_materials: Dictionary = {}

var device_id: int = -1
var model: Node3D
var body: StaticBody3D
var local_bounds: AABB
var port_areas: Dictionary = {} ## port_ref -> Area3D
var _leds: Array[MeshInstance3D] = []


func setup(device: SimDevice) -> void:
	device_id = device.id
	name = "Device%d" % device.id
	model = ModelUtil.instance_model(device.definition.model_path)
	add_child(model)
	local_bounds = ModelUtil.local_aabb(model)
	body = ModelUtil.add_box_body(self, local_bounds, Layers.DEVICES)
	body.set_meta("device_id", device.id)
	for group: PortDefinition in device.definition.ports:
		var is_power := group.kind in [PortDefinition.Kind.POWER_C13, PortDefinition.Kind.POWER_C14]
		for i: int in group.count:
			var marker := ModelUtil.marker_transform(model, PortRef.marker_name(group.kind, group.id, i))
			if not marker["found"]:
				continue
			var area := Area3D.new()
			area.collision_layer = Layers.PORTS
			area.collision_mask = 0
			area.monitoring = false
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = PORT_SIZE_POWER if is_power else PORT_SIZE_DATA
			shape.shape = box
			area.add_child(shape)
			area.transform = marker["transform"]
			var ref := PortRef.make(device.id, group.id, i)
			area.set_meta("port_ref", ref)
			add_child(area)
			port_areas[ref] = area
	_leds = ModelUtil.find_meshes_with_prefix(model, "LED_")


func port_global_transform(port_ref: String) -> Dictionary:
	if not port_areas.has(port_ref):
		return {"found": false}
	return {"found": true, "transform": (port_areas[port_ref] as Area3D).global_transform}


func global_bounds_center() -> Vector3:
	return global_transform * local_bounds.get_center()


## Updates the LEDs from the simulated state.
func refresh(world: SimWorld) -> void:
	var device := world.get_device(device_id)
	if device == null:
		return
	for led: MeshInstance3D in _leds:
		led.material_override = _material(_led_color(world, device, String(led.name)))


func _led_color(world: SimWorld, d: SimDevice, led_name: String) -> Color:
	if d.definition.get_spec(PowerStripSpec) != null:
		return COLOR_RED if world.is_powered(d) else COLOR_OFF
	var running := d.is_running()
	if led_name in ["LED_power", "LED_system"]:
		if running:
			return COLOR_GREEN
		return COLOR_AMBER if d.state == &"booting" else COLOR_OFF
	for prefix: String in ["LED_lan_", "LED_wan_"]:
		if led_name.begins_with(prefix) and led_name.substr(prefix.length()).is_valid_int():
			var group := StringName(prefix.trim_prefix("LED_").trim_suffix("_"))
			var ref := PortRef.make(d.id, group, led_name.substr(prefix.length()).to_int())
			return COLOR_GREEN if NetworkEngine.port_link(world, ref)["up"] else COLOR_OFF
	if led_name == "LED_internet":
		var router := d.definition.get_spec(RouterSpec) as RouterSpec
		return COLOR_GREEN if running and router != null and router.has_internet else COLOR_OFF
	if led_name.begins_with("LED_drive_") or led_name == "LED_disk":
		return COLOR_GREEN if running else COLOR_OFF
	return COLOR_OFF ## LED_id, LED_wifi...: not simulated yet, so they stay off (honest).


static func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _led_materials.has(key):
		return _led_materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if color != COLOR_OFF:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 4.0
	_led_materials[key] = mat
	return mat
