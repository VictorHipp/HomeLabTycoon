class_name CableRouter
extends RefCounted
## Finds where a cable lies on the floor (docs/INTERACTION_SYSTEM.md §9): a shortest path on a
## 2.5 cm grid (Godot's AStarGrid2D) that goes around furniture that stands on the floor, floor
## devices and the delivery zone, then pulled taut (line-of-sight shortcuts), so it hugs the
## corners it bends around, like a real cable. Pure logic: the presentation only draws it.

const CELL := 0.025 ## Fine enough to pass between a desk leg and the cabinet (5.75 cm gap).
const CLEARANCE := 0.012 ## Distance kept from obstacles (drawn cable radius 9.5 mm + margin).

var _grid: AStarGrid2D
var _bounds: Rect2
var _static_rects: Array[Rect2] = []


func _init(bounds: Rect2, static_obstacles: Array[Rect2]) -> void:
	_bounds = bounds
	_static_rects.assign(static_obstacles)
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(0, 0, ceili(bounds.size.x / CELL), ceili(bounds.size.y / CELL))
	_grid.cell_size = Vector2(CELL, CELL)
	_grid.offset = bounds.position + Vector2(CELL, CELL) / 2.0 # point positions = cell centres
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_grid.update()


## Floor path from `from` to `to` (x, z) around the static obstacles and `blocked` rects.
## Empty when there is no way through.
func find_path(from: Vector2, to: Vector2, blocked: Array[Rect2]) -> PackedVector2Array:
	_grid.fill_solid_region(_grid.region, false)
	for rect: Rect2 in _static_rects:
		_fill(rect)
	for rect: Rect2 in blocked:
		_fill(rect)
	var a := _free_cell_near(_cell_of(from))
	var b := _free_cell_near(_cell_of(to))
	if a.x < 0 or b.x < 0:
		return PackedVector2Array()
	var cells := _grid.get_point_path(a, b)
	if cells.is_empty():
		return cells
	var points := PackedVector2Array([from])
	points.append_array(cells)
	points.append(to)
	return _pull_taut(points)


static func length_of(points: PackedVector2Array) -> float:
	var total := 0.0
	for i: int in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total


## True if the point is on free floor for cables (inside the room, outside obstacles).
func is_free(p: Vector2) -> bool:
	var cell := _cell_of(p)
	return _grid.is_in_boundsv(cell) and not _grid.is_point_solid(cell)


func _fill(rect: Rect2) -> void:
	var r := rect.grow(CLEARANCE)
	var x0 := ceili((r.position.x - _grid.offset.x) / CELL)
	var y0 := ceili((r.position.y - _grid.offset.y) / CELL)
	var x1 := floori((r.end.x - _grid.offset.x) / CELL)
	var y1 := floori((r.end.y - _grid.offset.y) / CELL)
	var cells := Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1).intersection(_grid.region)
	if cells.size.x > 0 and cells.size.y > 0:
		_grid.fill_solid_region(cells, true)


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


## Removes every point that can be skipped with a straight, obstacle-free segment.
func _pull_taut(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array([points[0]])
	var i := 0
	while i < points.size() - 1:
		var j := points.size() - 1
		while j > i + 1 and not _segment_free(points[i], points[j]):
			j -= 1
		result.append(points[j])
		i = j
	return result


func _segment_free(a: Vector2, b: Vector2) -> bool:
	var steps := maxi(1, ceili(a.distance_to(b) / (CELL * 0.4)))
	for k: int in range(1, steps):
		var cell := _cell_of(a.lerp(b, float(k) / steps))
		if not _grid.is_in_boundsv(cell) or _grid.is_point_solid(cell):
			return false
	return true
