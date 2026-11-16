extends TestCase
## CableRouter on rooms other than the bedroom (docs/INTERACTION_SYSTEM.md §9.1): the rules come
## from the room data, so any future room gets tidy cables — right angles, along walls and
## furniture, around everything, never through keep-out areas.

const ROOM := Rect2(0.0, 0.0, 5.0, 4.0) ## A larger, empty-ish office.
const TABLE := Rect2(1.5, 1.2, 1.6, 0.8) ## Solid block in the middle.
const DOOR := Rect2(0.0, 1.5, 0.9, 1.0) ## Floor in front of a door on the left wall.


func _router() -> CableRouter:
	var solid: Array[Rect2] = [TABLE]
	var covered: Array[Rect2] = [TABLE]
	var keepout: Array[Rect2] = [DOOR]
	return CableRouter.new(ROOM, solid, covered, keepout, 0.015)


func test_runs_are_at_right_angles() -> void:
	var router := _router()
	var path := router.find_path(Vector2(0.4, 0.4), Vector2(4.6, 3.6), [])
	assert_true(path.size() >= 3, "found a path with bends")
	for i: int in range(1, path.size()):
		var d := path[i] - path[i - 1]
		assert_true(absf(d.x) < 0.0015 or absf(d.y) < 0.0015, "segment %d is horizontal or vertical (%s)" % [i, d])


func test_keeps_clear_of_obstacles_walls_and_keepout() -> void:
	var router := _router()
	var blocked: Array[Rect2] = [Rect2(3.5, 0.2, 0.6, 0.6)] # a rack on the floor
	var path := router.find_path(Vector2(0.4, 3.6), Vector2(4.6, 0.4), blocked)
	assert_false(path.is_empty(), "found a way")
	var avoid: Array[Rect2] = [TABLE, DOOR, blocked[0]]
	for i: int in range(1, path.size()):
		var steps := maxi(1, ceili(path[i - 1].distance_to(path[i]) / 0.01))
		for k: int in steps + 1:
			var p := path[i - 1].lerp(path[i], float(k) / steps)
			assert_true(ROOM.grow(-0.015 - CableRouter.CLEARANCE + 0.002).has_point(p), "in front of the skirting at %s" % p)
			for rect: Rect2 in avoid:
				assert_false(rect.grow(CableRouter.CLEARANCE - 0.002).has_point(p), "clear of %s at %s" % [rect, p])


func test_prefers_walls_and_furniture_to_open_floor() -> void:
	var router := _router()
	# From one wall to the opposite wall: the straight way crosses the open floor; the tidy way
	# goes along the walls or the table.
	var from := Vector2(2.3, 0.05 + 0.03)
	var to := Vector2(2.3, 4.0 - 0.08)
	var path := router.find_path(from, to, [])
	var along := 0.0
	var total := 0.0
	for i: int in range(1, path.size()):
		var steps := maxi(1, ceili(path[i - 1].distance_to(path[i]) / 0.02))
		for k: int in steps:
			var p := path[i - 1].lerp(path[i], (k + 0.5) / steps)
			var piece := path[i - 1].distance_to(path[i]) / steps
			total += piece
			if router.is_along_edge(p):
				along += piece
	assert_true(along / total > 0.6, "mostly along walls or furniture (%.0f %%)" % (100.0 * along / total))
	var compact := router.find_path(from, to, [], 1.0)
	assert_true(CableRouter.length_of(compact) <= CableRouter.length_of(path) + 0.001, "the compact way is never longer")


func test_no_way_through_returns_empty() -> void:
	var walls: Array[Rect2] = [Rect2(2.4, 0.0, 0.2, 4.0)] # a wall-to-wall block
	var router := CableRouter.new(ROOM, walls)
	assert_true(router.find_path(Vector2(1.0, 2.0), Vector2(4.0, 2.0), []).is_empty(), "no path")


func test_few_bends_on_open_floor() -> void:
	var router := CableRouter.new(ROOM, [])
	var path := router.find_path(Vector2(1.0, 1.0), Vector2(3.0, 3.0), [], 1.0)
	assert_true(path.size() <= 4, "an L, not a staircase (%d points)" % path.size())
