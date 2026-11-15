class_name CableRenderer
extends Node3D
## Draws every cable of the world as a sagging tube between its two ports
## (docs/INTERACTION_SYSTEM.md §9). A cable with a loose end hangs from its plugged end.
## Rebuilt on cable events only; meshes are generated once per change.

const COLOR_COPPER := Color("#3B82C4")
const COLOR_POWER := Color("#151515")
const SEGMENTS := 18
const SIDES := 6

var _materials: Dictionary = {}


## `port_transform` is a Callable(port_ref: String) -> Dictionary {"found", "transform"}.
func rebuild(world: SimWorld, port_transform: Callable) -> void:
	for child: Node in get_children():
		child.queue_free()
	for cable_id: int in world.cable_ends:
		var ends: Dictionary = world.cable_ends[cable_id]
		var spec := world.get_device(cable_id).definition.get_spec(CableSpec) as CableSpec
		var a: Dictionary = port_transform.call(ends["a"])
		if not a["found"]:
			continue
		var a_xf: Transform3D = a["transform"]
		var p0 := a_xf.origin
		var out0 := a_xf.basis.z.normalized()
		var p3: Vector3
		var out3: Vector3
		if ends["b"] == "":
			p3 = p0 + out0 * 0.12 + Vector3(0.0, -0.35, 0.0)
			out3 = Vector3.UP
		else:
			var b: Dictionary = port_transform.call(ends["b"])
			if not b["found"]:
				continue
			var b_xf: Transform3D = b["transform"]
			p3 = b_xf.origin
			out3 = b_xf.basis.z.normalized()
		var radius := 0.005 if spec.media == &"power" else 0.0035
		var color := COLOR_POWER if spec.media == &"power" else COLOR_COPPER
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = _tube(p0, out0, p3, out3, radius)
		mesh_instance.material_override = _material(color)
		mesh_instance.name = "Cable%d" % cable_id
		add_child(mesh_instance)


func _tube(p0: Vector3, out0: Vector3, p3: Vector3, out3: Vector3, radius: float) -> ArrayMesh:
	var dist := p0.distance_to(p3)
	var sag := clampf(dist * 0.3, 0.04, 0.45)
	var c1 := p0 + out0 * 0.1 + Vector3(0.0, -sag, 0.0)
	var c2 := p3 + out3 * 0.1 + Vector3(0.0, -sag, 0.0)
	var points: Array[Vector3] = []
	for i: int in SEGMENTS + 1:
		var t := float(i) / SEGMENTS
		var u := 1.0 - t
		points.append(u * u * u * p0 + 3.0 * u * u * t * c1 + 3.0 * u * t * t * c2 + t * t * t * p3)
	var rings: Array[PackedVector3Array] = []
	for i: int in points.size():
		var tangent := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		var normal := tangent.cross(Vector3.UP)
		if normal.length() < 0.01:
			normal = tangent.cross(Vector3.RIGHT)
		normal = normal.normalized()
		var binormal := tangent.cross(normal).normalized()
		var ring := PackedVector3Array()
		for s: int in SIDES:
			var angle := TAU * s / SIDES
			ring.append(points[i] + (normal * cos(angle) + binormal * sin(angle)) * radius)
		rings.append(ring)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in rings.size() - 1:
		for s: int in SIDES:
			var n := (s + 1) % SIDES
			for v: Vector3 in [rings[i][s], rings[i + 1][s], rings[i + 1][n], rings[i][s], rings[i + 1][n], rings[i][n]]:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.6
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = mat
	return _materials[key]
