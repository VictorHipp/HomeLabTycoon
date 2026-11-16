class_name CableRouter
extends RefCounted
## Finds where a cable lies on the floor (docs/INTERACTION_SYSTEM.md §9.1). Not the shortest way
## but a tidy one, the way a person lays a cable in any room:
##   - straight runs joined at right angles, never diagonals across the floor;
##   - along the walls and the sides of furniture and equipment, or under furniture; the open
##     floor where people walk is crossed only when needed, by the shortest crossing;
##   - never through keep-out areas (doorways, the delivery zone), never inside an obstacle and
##     always CLEARANCE away from them;
##   - with as few bends as possible.
## A weighted search on a 2.5 cm grid (Godot's AStarGrid2D, no diagonals) finds the cheapest way;
## then any staircase is folded into a single bend when that costs no more. Pure logic: the
## presentation only draws the result. Rooms are described by data (bounds, furniture, keep-out
## areas), so the same rules work in any room.

const CELL := 0.025 ## Fine enough to pass between a desk leg and the cabinet (5.75 cm gap).
## Distance kept from obstacles: the drawn cable radius (9.5 mm) plus a margin that also covers
## the rounded bends of the drawing (cable_renderer.gd: a 3 cm bend cuts 1.1 cm into the corner,
## and the corner of an obstacle is at least √2 × CLEARANCE from it).
const CLEARANCE := 0.015
const EDGE_BAND := 0.08 ## Floor this close to a wall or to an obstacle counts as "along an edge".
const EDGE_COST := 1.0
## Open floor costs this many times more: a detour along walls or furniture is preferred while it
## is at most this many times longer than crossing the open floor.
const OPEN_COST := 3.0
const MAX_FOLD_LOOKAHEAD := 40 ## Corners examined ahead of each point when folding staircases.
const JOG_M := 0.04 ## Sideways steps shorter than this are straightened when the way stays clear.

var _grid: AStarGrid2D
var _bounds: Rect2
var _wall_trim: float = 0.0 ## What sticks out of the walls at floor level (skirting boards).
var _solid: Array[Rect2] = [] ## What stands on the floor for a cable (bed, desk legs...).
var _covered: Array[Rect2] = [] ## Furniture footprints: under and next to them is a good place.
var _keepout: Array[Rect2] = [] ## Never crossed, and not an edge to follow (doorway, deliveries).


## `bounds`: the floor between the walls; `wall_trim`: skirting thickness; `solid`: obstacles on
## the floor; `covered`: furniture footprints (a cable may pass under a desk between its legs and
## likes to run along furniture); `keepout`: areas a cable must not cross.
func _init(bounds: Rect2, solid: Array[Rect2], covered: Array[Rect2] = [], keepout: Array[Rect2] = [], wall_trim: float = 0.0) -> void:
	_bounds = bounds
	_wall_trim = wall_trim
	_solid.assign(solid)
	_covered.assign(covered)
	_keepout.assign(keepout)
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(0, 0, ceili(bounds.size.x / CELL), ceili(bounds.size.y / CELL))
	_grid.cell_size = Vector2(CELL, CELL)
	_grid.offset = bounds.position + Vector2(CELL, CELL) / 2.0 # point positions = cell centres
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	# Manhattan estimates break ties towards one long run and one bend (measured: an L instead
	# of a 13-bend staircase with the Euclidean heuristic).
	_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_grid.update()


## Floor path from `from` to `to` (x, z) around the room's obstacles and the `blocked` rects
## (floor devices). Empty when there is no way through. `open_cost` = 1 gives the most compact
## tidy path (still at right angles and clear of everything): used when the tidy one is longer
## than the cable (SimWorld.route_between).
func find_path(from: Vector2, to: Vector2, blocked: Array[Rect2], open_cost: float = OPEN_COST) -> PackedVector2Array:
	_prepare(blocked, open_cost)
	var a := _free_cell_near(_cell_of(from))
	var b := _free_cell_near(_cell_of(to))
	if a.x < 0 or b.x < 0:
		return PackedVector2Array()
	var cells := _grid.get_id_path(a, b)
	if cells.is_empty():
		return PackedVector2Array()
	var corners := _fold(_corners(cells))
	var points := PackedVector2Array()
	for cell: Vector2i in corners:
		points.append(_grid.get_point_position(cell))
	return _attach_ends(from, points, to)


static func length_of(points: PackedVector2Array) -> float:
	var total := 0.0
	for i: int in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total


## True if the point is on free floor for cables (inside the room, outside obstacles), with the
## obstacles of the last search.
func is_free(p: Vector2) -> bool:
	var cell := _cell_of(p)
	return _grid.is_in_boundsv(cell) and not _grid.is_point_solid(cell)


## True if the point lies along an edge (wall, furniture, equipment) in the last search.
func is_along_edge(p: Vector2) -> bool:
	var cell := _cell_of(p)
	return _grid.is_in_boundsv(cell) and _grid.get_point_weight_scale(cell) <= EDGE_COST


# ------------------------------------------------------------------ grid --

func _prepare(blocked: Array[Rect2], open_cost: float) -> void:
	var all := _grid.region
	_grid.fill_solid_region(all, false)
	_grid.fill_weight_scale_region(all, open_cost)
	# Cheap: along the four walls, under and around furniture, around equipment.
	var band := EDGE_BAND
	for wall: Rect2 in [Rect2(_bounds.position, Vector2(_bounds.size.x, band)),
			Rect2(_bounds.position.x, _bounds.end.y - band, _bounds.size.x, band),
			Rect2(_bounds.position, Vector2(band, _bounds.size.y)),
			Rect2(_bounds.end.x - band, _bounds.position.y, band, _bounds.size.y)]:
		_fill_weight(wall, EDGE_COST)
	for rect: Rect2 in _covered:
		_fill_weight(rect.grow(band), EDGE_COST)
	for rect: Rect2 in blocked:
		_fill_weight(rect.grow(band), EDGE_COST)
	for rect: Rect2 in _solid:
		_fill_solid(rect)
	for rect: Rect2 in _keepout:
		_fill_solid(rect)
	for rect: Rect2 in blocked:
		_fill_solid(rect)
	# The skirting boards: a cable runs in front of them, never through them.
	if _wall_trim > 0.0:
		var t := _wall_trim
		for trim: Rect2 in [Rect2(_bounds.position, Vector2(_bounds.size.x, t)),
				Rect2(_bounds.position.x, _bounds.end.y - t, _bounds.size.x, t),
				Rect2(_bounds.position, Vector2(t, _bounds.size.y)),
				Rect2(_bounds.end.x - t, _bounds.position.y, t, _bounds.size.y)]:
			_fill_solid(trim)


## Cells whose centre is inside `rect` grown by CLEARANCE become solid.
func _fill_solid(rect: Rect2) -> void:
	var cells := _cells_inside(rect.grow(CLEARANCE))
	if cells.size.x > 0 and cells.size.y > 0:
		_grid.fill_solid_region(cells, true)


func _fill_weight(rect: Rect2, weight: float) -> void:
	var cells := _cells_inside(rect)
	if cells.size.x > 0 and cells.size.y > 0:
		_grid.fill_weight_scale_region(cells, weight)


func _cells_inside(r: Rect2) -> Rect2i:
	var x0 := ceili((r.position.x - _grid.offset.x) / CELL)
	var y0 := ceili((r.position.y - _grid.offset.y) / CELL)
	var x1 := floori((r.end.x - _grid.offset.x) / CELL)
	var y1 := floori((r.end.y - _grid.offset.y) / CELL)
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1).intersection(_grid.region)


func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(roundi((p.x - _grid.offset.x) / CELL), roundi((p.y - _grid.offset.y) / CELL))


## The cell itself if free, else the nearest free cell within 3 cells (an exit point right next
## to a device lies in the clearance band of that device); (-1, -1) if none.
func _free_cell_near(cell: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for dx: int in range(-3, 4):
		for dy: int in range(-3, 4):
			var c := cell + Vector2i(dx, dy)
			if _grid.is_in_boundsv(c) and not _grid.is_point_solid(c):
				var d := Vector2(dx, dy).length()
				if d < best_d:
					best_d = d
					best = c
	return best


# ------------------------------------------------------------- shaping ----

## The cells where the path changes direction (plus both ends).
static func _corners(cells: Array[Vector2i]) -> Array[Vector2i]:
	var result: Array[Vector2i] = [cells[0]]
	for i: int in range(1, cells.size() - 1):
		if cells[i] - cells[i - 1] != cells[i + 1] - cells[i]:
			result.append(cells[i])
	if cells.size() > 1:
		result.append(cells[cells.size() - 1])
	return result


## Replaces runs of bends by a single bend (an L) or a straight run when that way is free and
## costs no more (on uniform floor a staircase and an L cost the same: fewer bends wins).
func _fold(corners: Array[Vector2i]) -> Array[Vector2i]:
	if corners.size() <= 3:
		return corners
	var prefix: Array[float] = [0.0] # cost from corners[0] to corners[k]
	for k: int in range(1, corners.size()):
		prefix.append(prefix[k - 1] + _run_cost(corners[k - 1], corners[k]))
	var result: Array[Vector2i] = [corners[0]]
	var i := 0
	while i < corners.size() - 1:
		var best_j := i + 1
		var best_via := Vector2i(-1, -1)
		var last := mini(corners.size() - 1, i + MAX_FOLD_LOOKAHEAD)
		for j: int in range(last, i + 1, -1):
			var budget := prefix[j] - prefix[i] + 0.001
			var via := _best_bend(corners[i], corners[j], budget)
			if via.x != -2:
				best_j = j
				best_via = via
				break
		if best_via.x >= 0:
			result.append(best_via)
		result.append(corners[best_j])
		i = best_j
	return _corners_only(result)


## The bend cell of the cheapest free L (or straight run) from `a` to `b` within `budget`:
## (-1, -1) for a straight run, (-2, -2) if there is none.
func _best_bend(a: Vector2i, b: Vector2i, budget: float) -> Vector2i:
	if a.x == b.x or a.y == b.y:
		return Vector2i(-1, -1) if _run_cost(a, b) <= budget else Vector2i(-2, -2)
	var best := Vector2i(-2, -2)
	var best_cost := budget
	for via: Vector2i in [Vector2i(b.x, a.y), Vector2i(a.x, b.y)]:
		var cost := _run_cost(a, via) + _run_cost(via, b)
		if cost <= best_cost:
			best_cost = cost
			best = via
	return best


## Cost of a straight run of cells from `a` (excluded) to `b` (included); INF if any is solid.
func _run_cost(a: Vector2i, b: Vector2i) -> float:
	var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var cost := 0.0
	var c := a
	while c != b:
		c += step
		if _grid.is_point_solid(c):
			return INF
		cost += _grid.get_point_weight_scale(c)
	return cost


## Joins the exact end points to the grid path without little zigzags: the first and the last
## straight runs are moved sideways (less than a cell) onto the line of their end point when they
## stay clear; then points in line with their neighbours are dropped.
func _attach_ends(from: Vector2, mid: PackedVector2Array, to: Vector2) -> PackedVector2Array:
	var pts := mid.duplicate()
	if pts.size() >= 2:
		_align_run(pts, 0, 1, from)
		_align_run(pts, pts.size() - 1, pts.size() - 2, to)
	var result := PackedVector2Array([from])
	result.append_array(pts)
	result.append(to)
	return _straighten_jogs(_simplify(_dedupe(result)))


## Removes small sideways steps (shorter than JOG_M) between two parallel runs by moving one run
## onto the other's line, when it stays clear. The end points never move.
func _straighten_jogs(points: PackedVector2Array) -> PackedVector2Array:
	var pts := points.duplicate()
	var k := 1
	while k < pts.size() - 2:
		var jog := pts[k + 1] - pts[k]
		if jog.length() >= JOG_M or jog.length() < 0.0005:
			k += 1
			continue
		var fixed := false
		# Move the run after the step back onto the line of the run before it...
		if k + 2 < pts.size() - 1:
			var a := pts[k + 1] - jog
			var b := pts[k + 2] - jog
			if _line_free(pts[k], b) and _line_free(b, pts[k + 3]):
				pts[k + 1] = a
				pts[k + 2] = b
				fixed = true
		# ...or the run before it onto the line of the run after it.
		if not fixed and k - 1 > 0:
			var a := pts[k - 1] + jog
			var b := pts[k] + jog
			if _line_free(pts[k - 2], a) and _line_free(a, pts[k + 1]):
				pts[k - 1] = a
				pts[k] = b
				fixed = true
		if fixed:
			pts = _simplify(_dedupe(pts))
			k = 1
		else:
			k += 1
	return pts


## Moves the straight run pts[i]–pts[j] sideways so that it lines up with `end`.
func _align_run(pts: PackedVector2Array, i: int, j: int, end: Vector2) -> void:
	var a := pts[i]
	var b := pts[j]
	var horizontal := absf(a.y - b.y) < 0.001
	var na := Vector2(a.x, end.y) if horizontal else Vector2(end.x, a.y)
	var nb := Vector2(b.x, end.y) if horizontal else Vector2(end.x, b.y)
	if na.distance_to(a) > CELL * 1.01 or na.distance_to(a) < 0.0005:
		return
	if _line_free(na, nb) and _line_free(end, na):
		pts[i] = na
		pts[j] = nb


func _line_free(a: Vector2, b: Vector2) -> bool:
	var steps := maxi(1, ceili(a.distance_to(b) / (CELL * 0.4)))
	for k: int in steps + 1:
		var cell := _cell_of(a.lerp(b, float(k) / steps))
		if not _grid.is_in_boundsv(cell) or _grid.is_point_solid(cell):
			return false
	return true


## Drops every point that lies on the line through its neighbours (also when the way doubles
## back on itself along that line).
static func _simplify(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	var changed := true
	while changed and result.size() > 2:
		changed = false
		for k: int in range(1, result.size() - 1):
			var d1 := result[k] - result[k - 1]
			var d2 := result[k + 1] - result[k]
			if absf(d1.cross(d2)) < 1e-6:
				result.remove_at(k)
				changed = true
				break
	return result


static func _corners_only(points: Array[Vector2i]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for p: Vector2i in points:
		if result.is_empty() or result[result.size() - 1] != p:
			result.append(p)
	if result.size() < 3:
		return result
	var kept: Array[Vector2i] = [result[0]]
	for i: int in range(1, result.size() - 1):
		var d1 := result[i] - kept[kept.size() - 1]
		var d2 := result[i + 1] - result[i]
		var straight := (d1.x == 0 and d2.x == 0) or (d1.y == 0 and d2.y == 0)
		if not straight:
			kept.append(result[i])
	kept.append(result[result.size() - 1])
	return kept


static func _dedupe(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for p: Vector2 in points:
		if result.is_empty() or result[result.size() - 1].distance_to(p) > 0.002:
			result.append(p)
	return result
