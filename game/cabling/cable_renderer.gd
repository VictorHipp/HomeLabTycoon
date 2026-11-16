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
const CORNER_RADIUS := 0.03 ## Cuts 1.1 cm into a right-angle bend: CableRouter.CLEARANCE allows for it.
const SIDE_OUTSIDE_RACK := 0.015 ## Gap between a rack side and a cable that goes round it.
const LANE_GAP := 0.02 ## Between cables that share a stretch (a bit more than a cable diameter).
const BUNDLE_STEP := 0.04 ## Floor runs are sampled this often to find shared stretches.
const LONG_RUN_M := 0.08 ## A run this long over a furniture top before going down is a "long run".
## Closer than this on the floor: the later cable lies on top (and comes down only once clear).
const BUNDLE_NEAR := 0.03

## cable id -> PackedVector3Array actually drawn (for checks: tests and the walkthrough).
var paths: Dictionary = {}
var _materials: Dictionary = {}
var _floor_drawn: Array[PackedVector2Array] = [] ## Floor samples of the cables drawn so far.
var _drop_offset: Dictionary = {} ## "<cable id>:a|b" -> shift of its way down (_plan_drops).
var _run_offset: Dictionary = {} ## "<cable id>:a|b" -> shift of its first floor run (_plan_drops).
var _rise: Dictionary = {} ## "<cable id>:a|b" -> extra height of its run over a top face (_plan_drops).


## `port_transform` is a Callable(port_ref: String) -> Dictionary {"found", "transform"}.
func rebuild(world: SimWorld, port_transform: Callable) -> void:
	for child: Node in get_children():
		child.queue_free()
	paths.clear()
	_floor_drawn.clear()
	_plan_drops(world, port_transform)
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
			path = _bundle(_routed(world, route, cable_id, ends, a["transform"], b["transform"], radius), radius)
		var smooth := round_corners(path)
		paths[cable_id] = smooth
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = tube_mesh(smooth, radius)
		mesh_instance.material_override = _material(COLOR_POWER if spec.media == &"power" else COLOR_COPPER)
		mesh_instance.name = "Cable%d" % cable_id
		add_child(mesh_instance)


func _routed(world: SimWorld, route: Dictionary, cable_id: int, ends: Dictionary, a_xf: Transform3D, b_xf: Transform3D, radius: float) -> PackedVector3Array:
	var y := FLOOR_Y + radius
	if route["same_rack"]:
		return _inside_rack(world, route, ends, a_xf, b_xf)
	var off_a: Vector3 = _drop_offset.get("%d:a" % cable_id, Vector3.ZERO)
	var off_b: Vector3 = _drop_offset.get("%d:b" % cable_id, Vector3.ZERO)
	var floor := PackedVector3Array()
	for p: Vector2 in route["floor"]:
		floor.append(Vector3(p.x, y, p.y))
	floor = _shift_first_run(floor, _run_offset.get("%d:a" % cable_id, off_a))
	floor.reverse()
	floor = _shift_first_run(floor, _run_offset.get("%d:b" % cable_id, off_b))
	floor.reverse()
	var pts := _to_floor(route["a"], a_xf, y, off_a, _rise.get("%d:a" % cable_id, 0.0))
	var tail := _to_floor(route["b"], b_xf, y, off_b, _rise.get("%d:b" % cable_id, 0.0))
	tail.reverse()
	# A cable that went down past the start of the common way joins it directly (no doubling back).
	if floor.size() >= 2 and (floor[1] - pts[pts.size() - 1]).dot(floor[0] - pts[pts.size() - 1]) < 0.0:
		floor.remove_at(0)
	if floor.size() >= 2 and (floor[floor.size() - 2] - tail[0]).dot(floor[floor.size() - 1] - tail[0]) < 0.0:
		floor.remove_at(floor.size() - 1)
	pts.append_array(floor)
	pts.append_array(tail)
	return _dedupe(pts)


## Moves the first straight run of a floor path sideways by `offset` (a cable that goes down
## beside others keeps beside them until the first bend, then joins the common way).
static func _shift_first_run(floor: PackedVector3Array, offset: Vector3) -> PackedVector3Array:
	if offset.length() < 0.0005 or floor.size() < 2:
		return floor
	var result := floor.duplicate()
	result[0] = floor[0] + offset
	if floor.size() == 2:
		result.insert(1, floor[1] + offset)
	else:
		result[1] = floor[1] + offset
	return result


## Several cables that go down at the same spot go down side by side instead of inside one
## another (fills _drop_offset: "<cable id>:a|b" -> shift of its way down and first floor run):
##   - cables leaving in opposite directions on the floor go down half a lane towards their own
##     way, so they part without touching;
##   - cables leaving in the same direction go down in parallel lanes, side by side across their
##     way (away from the device), the one whose socket is nearest the spot closest to it, so the
##     short runs from the sockets never cross another cable going down.
func _plan_drops(world: SimWorld, port_transform: Callable) -> void:
	_drop_offset.clear()
	_run_offset.clear()
	_rise.clear()
	var tops: Array = [] # [device id, slot key, socket, exit] of sockets plugged from above
	var groups := {} # exit key -> [[lateral, slot key, way (Vector3), out (Vector3)], ...]
	for cable_id: int in world.cable_ends:
		var ends: Dictionary = world.cable_ends[cable_id]
		if ends["b"] == "":
			continue
		var route := world.cable_route(cable_id)
		if not route.get("ok", false) or route["same_rack"]:
			continue
		var floor: PackedVector2Array = route["floor"]
		for end_name: String in ["a", "b"]:
			var xf: Dictionary = port_transform.call(ends[end_name])
			if not xf["found"] or floor.size() < 2:
				continue
			var end: Dictionary = route[end_name]
			var socket_xf: Transform3D = xf["transform"]
			var out := socket_xf.basis.z.normalized()
			var p1 := socket_xf.origin + out * SimWorld.PORT_OUT_M
			var exit2: Vector2 = end["exit"]
			var exit := Vector3(exit2.x, p1.y, exit2.y)
			var first := floor[1] - floor[0] if end_name == "a" else floor[floor.size() - 2] - floor[floor.size() - 1]
			var way := Vector3(first.x, 0.0, first.y).normalized()
			var flat_out := Vector3(out.x, 0.0, out.z)
			if flat_out.length() < 0.3: # plugged from above (power strip): away from the device
				flat_out = Vector3(exit.x - p1.x, 0.0, exit.z - p1.z)
			flat_out = flat_out.normalized() if flat_out.length() > 0.001 else Vector3.FORWARD
			var key := "%d,%d" % [roundi(exit2.x * 100.0), roundi(exit2.y * 100.0)]
			if not groups.has(key):
				groups[key] = []
			if float(end.get("side", 0.0)) != 0.0:
				# To a rack post: one lane further from the face, in front of the patch cables
				# between devices of the rack.
				_rise["%d:%s" % [cable_id, end_name]] = LANE_GAP
			if absf(out.y) > 0.5:
				tops.append([PortRef.device_id(ends[end_name]), "%d:%s" % [cable_id, end_name], socket_xf.origin, exit])
			# A long run over a piece of furniture before going down (the router on its cabinet).
			var long_run := absf(out.y) < 0.5 and Vector3(exit.x - p1.x, 0.0, exit.z - p1.z).dot(flat_out) > LONG_RUN_M
			(groups[key] as Array).append([_lateral(p1, exit, way), "%d:%s" % [cable_id, end_name], way, flat_out, long_run, p1, exit])
	# Plugged from above (power strip): a cable whose run passes over other plugged sockets on its
	# way to the edge goes one lane higher per socket, over the cables rising from them.
	for a: Array in tops:
		var from := Vector2((a[2] as Vector3).x, (a[2] as Vector3).z)
		var to := Vector2((a[3] as Vector3).x, (a[3] as Vector3).z)
		var count := 0
		for b: Array in tops:
			if b[1] == a[1] or b[0] != a[0]:
				continue
			var p := Vector2((b[2] as Vector3).x, (b[2] as Vector3).z)
			var t := (p - from).dot(to - from) / maxf((to - from).length_squared(), 0.0001)
			var closest := from + (to - from) * clampf(t, 0.0, 1.0)
			if t > 0.0 and t < 1.0 and p.distance_to(closest) < 0.03:
				count += 1
		if count > 0:
			_rise[a[1]] = float(_rise.get(a[1], 0.0)) + count * LANE_GAP
	for key: String in groups:
		var group: Array = groups[key]
		if group.size() < 2:
			continue
		if group.all(func(entry: Array) -> bool: return entry[4]):
			# Long runs: each cable goes straight out from its own socket and down in front of it
			# (parallel, never converging). On the floor, the cable furthest along the way keeps
			# the near lane and each one behind it takes a lane further out, so none runs under
			# another one coming down.
			group.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) > float(q[0]))
			for i: int in group.size():
				var way: Vector3 = group[i][2]
				var flat_out: Vector3 = group[i][3]
				var lanes := flat_out * i * LANE_GAP
				var along := way * float(group[i][0]) if absf(way.dot(flat_out)) < 0.7 else Vector3.ZERO
				_drop_offset[group[i][1]] = along + lanes
				_run_offset[group[i][1]] = lanes
			continue
		var ways := {} # snapped way -> entries
		for entry: Array in group:
			var w: Vector3 = entry[2]
			var way_key := "%d,%d" % [roundi(w.x), roundi(w.z)]
			if not ways.has(way_key):
				ways[way_key] = []
			(ways[way_key] as Array).append(entry)
		var planned := {} # slot key -> offset
		for way_key: String in ways:
			var same: Array = ways[way_key]
			var way: Vector3 = same[0][2]
			var base := way * LANE_GAP * 0.5 if ways.size() > 1 else Vector3.ZERO
			var side := way.cross(Vector3.UP).normalized()
			var flat_out: Vector3 = same[0][3]
			if absf(way.dot(flat_out)) < 0.7:
				if side.dot(flat_out) < 0.0:
					side = -side # along the face: the lanes go away from the device
			elif float(same[0][0]) < 0.0:
				side = -side # straight out: the lanes go towards the sockets' side
			same.sort_custom(func(p: Array, q: Array) -> bool: return absf(float(p[0])) < absf(float(q[0])))
			for i: int in same.size():
				planned[same[i][1]] = base + side * i * LANE_GAP
		if ways.size() > 1 and _crossing_risk(group, planned):
			# Cables leaving one spot in different directions, with a low socket on the far side
			# of a higher cable's way down: the one from the lowest socket goes down nearest the
			# face and each higher one a lane and a half further out (beyond the half lane a
			# lower one may already go out), so a cable only ever passes over
			# (never through) one going down.
			group.sort_custom(func(p: Array, q: Array) -> bool: return (p[5] as Vector3).y < (q[5] as Vector3).y)
			for i: int in group.size():
				planned[group[i][1]] = (group[i][2] as Vector3) * LANE_GAP * 0.5 + (group[i][3] as Vector3) * i * LANE_GAP * 1.5
		for slot: String in planned:
			_drop_offset[slot] = planned[slot]


## Would a cable run (at its socket height, from just out of the socket to its way down) pass
## through the way down of a cable plugged higher up? Checked on the floor plan: closer than 75 %
## of both radii (the same margin the walkthrough checks between drawn cables).
static func _crossing_risk(group: Array, offsets: Dictionary) -> bool:
	for a: Array in group:
		for b: Array in group:
			var p1_a: Vector3 = a[5]
			var p1_b: Vector3 = b[5]
			if a == b or p1_a.y >= p1_b.y:
				continue
			var from := Vector2(p1_a.x, p1_a.z)
			var drop_a: Vector3 = (a[6] as Vector3) + (offsets[a[1]] as Vector3)
			var to := Vector2(drop_a.x, drop_a.z)
			var drop_b: Vector3 = (b[6] as Vector3) + (offsets[b[1]] as Vector3)
			var column := Vector2(drop_b.x, drop_b.z)
			var t := clampf((column - from).dot(to - from) / maxf((to - from).length_squared(), 0.000001), 0.0, 1.0)
			if column.distance_to(from + (to - from) * t) < (RADIUS_DATA + RADIUS_POWER) * 0.75:
				return true
	return false


## Signed distance of a socket from the way down, across the cable's way on the floor.
static func _lateral(p1: Vector3, exit: Vector3, way: Vector3) -> float:
	var flat := Vector3(p1.x - exit.x, 0.0, p1.z - exit.z)
	return flat.dot(way) if way.length() > 0.5 else flat.length()


## Socket -> straight out -> (at socket height) above the floor exit -> down to the floor.
## `offset` moves the way down beside the other cables of the same spot (see _plan_drops).
func _to_floor(end: Dictionary, socket_xf: Transform3D, y: float, offset: Vector3, rise: float = 0.0) -> PackedVector3Array:
	var socket := socket_xf.origin
	var out := socket_xf.basis.z.normalized()
	var p1 := socket + out * (SimWorld.PORT_OUT_M + rise)
	var exit2: Vector2 = end["exit"]
	var exit := Vector3(exit2.x, p1.y, exit2.y) + offset
	return PackedVector3Array([socket, p1, exit, Vector3(exit.x, y, exit.z)])


## Cables that share a stretch of floor lie on top of each other (a bundle) instead of being
## drawn inside one another: each floor point is raised by the number of cables already drawn
## through it.
func _bundle(pts: PackedVector3Array, radius: float) -> PackedVector3Array:
	var floor_top := FLOOR_Y + radius + 0.002
	var result := PackedVector3Array()
	var samples := PackedVector2Array()
	for i: int in pts.size():
		var p := pts[i]
		var on_floor := p.y <= floor_top
		var next_on_floor := i + 1 < pts.size() and pts[i + 1].y <= floor_top
		var pieces := 1
		if on_floor and next_on_floor:
			pieces = maxi(1, ceili(Vector2(p.x, p.z).distance_to(Vector2(pts[i + 1].x, pts[i + 1].z)) / BUNDLE_STEP))
		for k: int in pieces:
			var q := p.lerp(pts[i + 1], float(k) / pieces) if pieces > 1 else p
			if on_floor:
				var flat := Vector2(q.x, q.z)
				samples.append(flat)
				q.y += _lane_at(flat) * LANE_GAP
			result.append(q)
	_floor_drawn.append(samples)
	return _dedupe(result)


func _lane_at(p: Vector2) -> int:
	var lane := 0
	for drawn: PackedVector2Array in _floor_drawn:
		for s: Vector2 in drawn:
			if s.distance_squared_to(p) < BUNDLE_NEAR * BUNDLE_NEAR:
				lane += 1
				break
	return lane


## Between two devices of one rack: in front of the face, across a free unit, or round the side.
## Patch cables stand two lanes further out than the cables that leave the rack, so they hang in
## front of the sockets below them instead of through the cables plugged there.
func _inside_rack(world: SimWorld, route: Dictionary, ends: Dictionary, a_xf: Transform3D, b_xf: Transform3D) -> PackedVector3Array:
	var a_out := a_xf.origin + a_xf.basis.z.normalized() * (SimWorld.PORT_OUT_M + 2.0 * LANE_GAP)
	var b_out := b_xf.origin + b_xf.basis.z.normalized() * (SimWorld.PORT_OUT_M + 2.0 * LANE_GAP)
	var pts := PackedVector3Array([a_xf.origin, a_out])
	var cross: float = route["a"].get("cross_height", -1.0)
	if route["a"]["face"] == route["b"]["face"]:
		# Straight down in front of the upper socket, then across at the lower socket's height (as
		# a patch cable is dressed: it never slants across the neighbouring sockets).
		if a_out.y >= b_out.y:
			pts.append(Vector3(a_out.x, b_out.y, a_out.z))
		else:
			pts.append(Vector3(b_out.x, a_out.y, b_out.z))
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
static func round_corners(pts: PackedVector3Array) -> PackedVector3Array:
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
static func tube_mesh(points: PackedVector3Array, radius: float) -> ArrayMesh:
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
