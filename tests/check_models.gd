extends SceneTree
## Checks imported .glb models: size in metres, Y-up, functional markers.
##
##   godot_console --headless --path . --script res://tests/check_models.gd
##
## Prints one line per model and "MODELS FAIL: ..." for every broken expectation.
## Exit code 0 = all expectations met.

const MODELS_DIR := "res://assets/models"
## Expected bounding-box size (metres, X Y Z) and marker counts for known models.
const EXPECT := {
	"switch_16p_1u": {"size": Vector3(0.4826, 0.0437, 0.223), "PORT_lan_": 16, "POWER_IN_": 1},
	"server_1u_entry": {"size": Vector3(0.4826, 0.0437, 0.5066), "PORT_lan_": 2, "POWER_IN_": 1},
	"rack_12u_open": {"PORT_": 0, "RACK_U1": 1, "STAND_POINT": 1, "CAM_rack_front": 1, "CAM_rack_rear": 1},
	"router_home": {"PORT_lan_": 4, "PORT_wan_": 1, "POWER_IN_": 1},
	"power_strip_4": {"POWER_OUT_": 4},
	"pc_tower_old": {"PORT_lan_": 1, "POWER_IN_": 1},
	"monitor_old": {"SCREEN": 1, "CAM_screen": 1},
	"character_player": {"J_": 10},
	"mannequin_scale": {"J_": 10},
}
const SIZE_TOLERANCE := 0.003

var _failures: Array[String] = []


func _initialize() -> void:
	var files: Array[String] = []
	_collect(MODELS_DIR, files)
	files.sort()
	for path: String in files:
		_check(path)
	if _failures.is_empty():
		print("MODELS OK (%d)" % files.size())
		quit(0)
	else:
		for f: String in _failures:
			printerr("MODELS FAIL: " + f)
		quit(1)


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
	for file: String in dir.get_files():
		if file.get_extension() == "glb":
			out.append(dir_path.path_join(file))


func _check(path: String) -> void:
	var model_id := path.get_file().get_basename()
	var packed := load(path) as PackedScene
	if packed == null:
		_failures.append("%s did not import" % path)
		return
	# Not added to the tree: during _initialize() global transforms are not available,
	# so transforms relative to the model root are accumulated by hand.
	var instance := packed.instantiate() as Node3D
	var aabb := AABB()
	var first := true
	var markers := {}   # name -> Transform3D relative to the model root
	var mesh_count := 0
	for entry: Array in _walk(instance, Transform3D.IDENTITY):
		var node: Node = entry[0]
		var xf: Transform3D = entry[1]
		if node is MeshInstance3D:
			mesh_count += 1
			var box := xf * (node as MeshInstance3D).get_aabb()
			aabb = box if first else aabb.merge(box)
			first = false
		if node != instance:
			markers[String(node.name)] = xf
	var size := aabb.size
	print("%-18s size=(%.4f, %.4f, %.4f) m  meshes=%d  nodes=%d" % [model_id, size.x, size.y, size.z, mesh_count, markers.size()])

	var expect: Dictionary = EXPECT.get(model_id, {})
	if expect.has("size"):
		var want: Vector3 = expect["size"]
		if (size - want).abs().x > SIZE_TOLERANCE or (size - want).abs().y > SIZE_TOLERANCE \
				or (size - want).abs().z > SIZE_TOLERANCE:
			_failures.append("%s size %s != expected %s" % [model_id, size, want])
	for key: String in expect:
		if key == "size":
			continue
		var count := 0
		for name: String in markers:
			if name.begins_with(key):
				count += 1
		if count != int(expect[key]):
			_failures.append("%s has %d nodes starting with %s, expected %d" % [model_id, count, key, expect[key]])

	# Orientation conventions (docs/ART_STYLE.md §8):
	#  sockets: +Z points out of the socket; CAM_/STAND_POINT: -Z is the view/facing direction.
	for name: String in markers:
		var xf: Transform3D = markers[name]
		if name.begins_with("CAM_"):
			var look := -xf.basis.z.normalized()
			var to_center := (aabb.get_center() - xf.origin).normalized()
			if look.dot(to_center) < 0.8:
				_failures.append("%s %s does not look at the model (dot=%.2f)" % [model_id, name, look.dot(to_center)])
		elif name.begins_with("STAND_POINT"):
			var facing := -xf.basis.z.normalized()
			var to_c := aabb.get_center() - xf.origin
			to_c.y = 0.0
			if facing.dot(to_c.normalized()) < 0.7:
				_failures.append("%s STAND_POINT does not face the model" % model_id)
		elif name.begins_with("PORT_") or name.begins_with("POWER_IN_"):
			# the socket normal (+Z) must point away from the model centre
			var out := xf.basis.z.normalized()
			var from_c := xf.origin - aabb.get_center()
			from_c.y = 0.0
			if out.dot(from_c.normalized()) < 0.5:
				_failures.append("%s %s socket normal points inwards" % [model_id, name])
	instance.free()


## Returns [[node, transform_relative_to_start], ...] for the whole subtree.
func _walk(node: Node, parent_xf: Transform3D) -> Array:
	var xf := parent_xf
	if node is Node3D:
		xf = parent_xf * (node as Node3D).transform
	var result: Array = [[node, xf]]
	for child: Node in node.get_children():
		result.append_array(_walk(child, xf))
	return result
