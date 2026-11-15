class_name CableRenderer
extends Node3D
## Draws every cable along the route computed by the simulation (SimWorld.cable_route,
## docs/INTERACTION_SYSTEM.md §9): out of the socket, to the floor next to its device (racks: down
## a post), along the floor around furniture, and up to the other socket. Corners are rounded so
## it reads as a cable. A cable with a loose end hangs from its plugged end and lies on the floor.
## The tubes are thicker than real cables on purpose: they must be visible from the overview.

const COLOR_COPPER := Color("#3B82C4")
const COLOR_POWER := Color("#202020")
const RADIUS_DATA := 0.008
const RADIUS_POWER := 0.0095
const FLOOR_Y := 0.016 ## Bottom of a cable lying on the floor (above the rug, 12.5 mm).
const SIDES := 8
const CORNER_RADIUS := 0.05
const SIDE_OUTSIDE_RACK := 0.015 ## Gap between a rack side and a cable that goes round it.

## cable id -> PackedVector3Array actually drawn (for checks: tests and the walkthrough).
var paths: Dictionary = {}
var _materials: Dictionary = {}


## `port_transform` is a Callable(port_ref: String) -> Dictionary {"found", "transform"}.
func rebuild(world: SimWorld, port_transform: Callable) -> void:
	for child: Node in get_children():
		child.queue_free()
	paths.clear()
	for cable_id: int in world.cable_ends:
		var ends: Dictionary = world.cable_ends[cable_id]
		var spec := world.get_device(cable_id).definition.get_spec(CableSpec) as CableSpec
		var radius := RADIUS_POWER if spec.media == &"power" else RADIUS_DATA
		var a: Dictionary = port_transform.call(ends["a"])
		if not a["found"]:
			continue
		var path: PackedVector3Array
		if ends["b"] == "":
			path = _loose(a["transform"], radius)
		else:
			var b: Dictionary = port_transform.call(ends["b"])
			var route := world.cable_route(cable_id)
			if not b["found"] or not route["ok"]:
				continue
			path = _routed(world, route, ends, a["transform"], b["transform"], radius)
		var smooth := _rounded(path)
		paths[cable_id] = smooth
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = _tube(smooth, radius)
		mesh_instance.material_override = _material(COLOR_POWER if spec.media == &"power" else COLOR_COPPER)
		mesh_instance.name = "Cable%d" % cable_id
		add_child(mesh_instance)


func _routed(world: SimWorld, route: Dictionary, ends: Dictionary, a_xf: Transform3D, b_xf: Transform3D, radius: float) -> PackedVector3Array:
	var y := FLOOR_Y + radius
	if route["same_rack"]:
		return _inside_rack(world, route, ends, a_xf, b_xf)
	var pts := _to_floor(route["a"], a_xf, y)
	for p: Vector2 in route["floor"]:
		pts.append(Vector3(p.x, y, p.y))
	var tail := _to_floor(route["b"], b_xf, y)
	tail.reverse()
	pts.append_array(tail)
	return _dedupe(pts)


## Socket -> straight out -> (at socket height) above the floor exit -> down to the floor.
func _to_floor(end: Dictionary, socket_xf: Transform3D, y: float) -> PackedVector3Array:
	var socket := socket_xf.origin
	var out := socket_xf.basis.z.normalized()
	var p1 := socket + out * SimWorld.PORT_OUT_M
	var exit2: Vector2 = end["exit"]
	return PackedVector3Array([socket, p1, Vector3(exit2.x, p1.y, exit2.y), Vector3(exit2.x, y, exit2.y)])


## Between two devices of one rack: in front of the face, across a free unit, or round the side.
func _inside_rack(world: SimWorld, route: Dictionary, ends: Dictionary, a_xf: Transform3D, b_xf: Transform3D) -> PackedVector3Array:
	var a_out := a_xf.origin + a_xf.basis.z.normalized() * SimWorld.PORT_OUT_M
	var b_out := b_xf.origin + b_xf.basis.z.normalized() * SimWorld.PORT_OUT_M
	var pts := PackedVector3Array([a_xf.origin, a_out])
	var cross: float = route["a"].get("cross_height", -1.0)
	if route["a"]["face"] == route["b"]["face"]:
		pass # straight up or down in front of the face
	elif cross >= 0.0:
		pts.append(Vector3(a_out.x, cross, a_out.z))
		pts.append(Vector3(b_out.x, cross, b_out.z))
	else:
		var rack := world.get_device(world.get_device(PortRef.device_id(ends["a"])).rack_id)
		var basis := Basis(Vector3.UP, deg_to_rad(rack.yaw_degrees))
		var la := basis.inverse() * (a_out - rack.position)
		var lb := basis.inverse() * (b_out - rack.position)
		var sx := rack.definition.footprint_m.x / 2.0 + SIDE_OUTSIDE_RACK
		pts.append(rack.position + basis * Vector3(sx, la.y, la.z))
		pts.append(rack.position + basis * Vector3(sx, lb.y, lb.z))
	pts.append(b_out)
	pts.append(b_xf.origin)
	return _dedupe(pts)


## A cable plugged at one end only: hangs down and lies on the floor away from the device.
func _loose(a_xf: Transform3D, radius: float) -> PackedVector3Array:
	var socket := a_xf.origin
	var out := a_xf.basis.z.normalized()
	var p1 := socket + out * 0.06
	var flat := Vector3(out.x, 0.0, out.z)
	flat = flat.normalized() if flat.length() > 0.1 else Vector3.FORWARD
	var y := FLOOR_Y + radius
	var down := Vector3(p1.x, y, p1.z) + flat * 0.05
	return PackedVector3Array([socket, p1, down, down + flat * 0.25 + flat.cross(Vector3.UP) * 0.08])


static func _dedupe(pts: PackedVector3Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	for p: Vector3 in pts:
		if result.is_empty() or result[result.size() - 1].distance_to(p) > 0.002:
			result.append(p)
	return result


## Replaces every corner by a short curve (quadratic Bézier) so the cable bends smoothly.
static func _rounded(pts: PackedVector3Array) -> PackedVector3Array:
	if pts.size() < 3:
		return pts
	var result := PackedVector3Array([pts[0]])
	for i: int in range(1, pts.size() - 1):
		var prev := pts[i - 1]
		var corner := pts[i]
		var next := pts[i + 1]
		var r := minf(CORNER_RADIUS, minf(prev.distance_to(corner), corner.distance_to(next)) * 0.45)
		var p_in := corner + (prev - corner).normalized() * r
		var p_out := corner + (next - corner).normalized() * r
		for k: int in 6:
			var t := k / 5.0
			result.append(p_in.lerp(corner, t).lerp(corner.lerp(p_out, t), t))
	result.append(pts[pts.size() - 1])
	return _dedupe(result)


## Tube along the polyline with rotation-minimising frames (no twisting at vertical runs).
func _tube(points: PackedVector3Array, radius: float) -> ArrayMesh:
	var rings: Array[PackedVector3Array] = []
	var normal := Vector3.ZERO
	for i: int in points.size():
		var tangent := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		if normal == Vector3.ZERO:
			normal = tangent.cross(Vector3.UP if absf(tangent.y) < 0.9 else Vector3.RIGHT).normalized()
		else:
			normal = (normal - tangent * normal.dot(tangent)).normalized()
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
		mat.roughness = 0.55
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = mat
	return _materials[key]
