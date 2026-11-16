extends TestCase
## Rearranging the room (docs/INTERACTION_SYSTEM.md §8.2): furniture is simulation state built
## from data/furniture/, the starting layout gives exactly the room the other tests were written
## for, a piece takes what stands on it or belongs to it, cables are routed again (or the spot is
## refused with the reason) and saves keep the layout.

var world: SimWorld


func before_each() -> void:
	world = BedroomScenario.create()


## The furniture data reproduce the footprints measured on the models before furniture could move.
func test_starting_layout_matches_the_measured_room() -> void:
	_assert_same_rects(world.obstacles, [
		Rect2(-1.73, -1.485, 0.98, 2.04), Rect2(-0.05, -1.47, 1.20, 0.60),
		Rect2(1.18, -1.48, 0.54, 0.40), Rect2(0.11, -0.92, 0.58, 0.60)], "walking / placement footprints")
	_assert_same_rects(world.cable_obstacles, [
		Rect2(-1.73, -1.485, 0.98, 2.04),
		Rect2(-0.0225, -1.4425, 0.045, 0.045), Rect2(-0.0225, -0.9425, 0.045, 0.045),
		Rect2(1.0775, -1.4425, 0.045, 0.045), Rect2(1.0775, -0.9425, 0.045, 0.045),
		Rect2(0.70, -1.44, 0.40, 0.50), Rect2(1.18, -1.48, 0.54, 0.40), Rect2(0.07, -0.95, 0.66, 0.66)],
		"what stands on the floor for a cable")
	assert_eq(_device(&"pc_old").furniture_id, &"desk", "the PC goes with the desk")
	assert_eq(_device(&"power_strip_4").furniture_id, &"desk", "the strip goes with the desk")
	assert_eq(_device(&"router_home").furniture_id, &"cabinet", "the router stands on the cabinet")


func test_rects_turn_with_the_piece() -> void:
	var r := SimFurniture.place_rect(Rect2(0.1, 0.2, 0.4, 0.3), Vector3(1.0, 0.0, 2.0), 90.0)
	# local x -> world -z, local z -> world +x for a quarter turn (Godot yaw).
	assert_almost(r.size.x, 0.3, 0.0001, "width becomes the depth")
	assert_almost(r.size.y, 0.4, 0.0001, "depth becomes the width")
	assert_almost(r.position.x, 1.2, 0.0001, "x after the turn")
	assert_almost(r.position.y, 2.0 - 0.5, 0.0001, "z after the turn")


func test_rug_goes_anywhere_inside_and_under_furniture() -> void:
	assert_eq(world.furniture_problem(&"rug", Vector3(-1.0, 0.0, -0.5), 90.0), "", "under the bed is fine")
	assert_contains(world.furniture_problem(&"rug", Vector3(-1.4, 0.0, 0.0), 0.0), "se sale de la habitación", "half out of the room")
	var r := world.move_furniture(&"rug", Vector3(0.6, 0.0, 0.5), 90.0)
	assert_true(r.ok, "moved: %s" % r.message)
	assert_true(world.obstacles.size() == 4, "a rug blocks nothing")


func test_bed_collides_and_keeps_the_door_and_deliveries_free() -> void:
	assert_contains(world.furniture_problem(&"bed", Vector3(0.4, 0.0, -0.4), 0.0), "choca con", "on the desk")
	assert_contains(world.furniture_problem(&"bed", Vector3(-0.60, 0.0, 0.95), 90.0), "entregas", "on the delivery zone")
	var ok := world.move_furniture(&"bed", Vector3(1.20, 0.0, 0.40), 0.0)
	assert_true(ok.ok, "bed against the right wall: %s" % ok.message)
	assert_true(world.obstacles.has(Rect2(0.71, -0.62, 0.98, 2.04)) or _has_rect(world.obstacles, Rect2(0.71, -0.62, 0.98, 2.04)), "its footprint moved")


func test_cabinet_takes_the_router_and_its_cables_are_routed_again() -> void:
	var router := _device(&"router_home")
	var before := router.position
	var r := world.move_furniture(&"cabinet", Vector3(1.45, 0.0, -0.75), 0.0)
	assert_true(r.ok, "cabinet a bit further along the right wall: %s" % r.message)
	assert_almost(router.position.z - before.z, 0.53, 0.001, "the router went with it")
	assert_almost(router.position.y, before.y, 0.0001, "still on the top")
	for cable_id: int in world.cable_ends:
		assert_true(world.cable_route(cable_id)["ok"], "cable %d still has a way" % cable_id)
	var far := world.furniture_problem(&"cabinet", Vector3(-1.45, 0.0, 1.25), 0.0)
	assert_true(far != "", "far from the PC and the strip some house cable cannot reach")


func test_desk_turns_with_the_pc_and_the_strip() -> void:
	var desk := world.get_furniture(&"desk")
	var pc := _device(&"pc_old")
	var local := (pc.position - desk.position).rotated(Vector3.UP, 0.0)
	var problem := world.furniture_problem(&"desk", Vector3(0.55, 0.0, -1.17), 180.0)
	if problem == "":
		assert_true(world.move_furniture(&"desk", Vector3(0.55, 0.0, -1.17), 180.0).ok, "turned in place")
		var expected := Vector3(0.55, 0.0, -1.17) + local.rotated(Vector3.UP, PI)
		assert_almost(pc.position.x, expected.x, 0.001, "PC x turned with the desk")
		assert_almost(pc.position.z, expected.z, 0.001, "PC z turned with the desk")
		assert_almost(pc.yaw_degrees, 180.0, 0.001, "the PC faces the other way too")
	else:
		assert_contains(problem, "No cabe ahí", "turned in place it hits the wall: %s" % problem)


func test_move_refused_keeps_everything_where_it_was() -> void:
	var desk := world.get_furniture(&"desk")
	var pc := _device(&"pc_old")
	var before := [desk.position, desk.yaw_degrees, pc.position]
	var obstacles_before := world.obstacles.duplicate()
	var r := world.move_furniture(&"desk", Vector3(-1.0, 0.0, 1.0), 0.0)
	assert_false(r.ok, "on the bed / out of reach")
	assert_eq([desk.position, desk.yaw_degrees, pc.position], before, "nothing moved")
	assert_eq(world.obstacles, obstacles_before, "the room geometry is back")


func test_router_goes_from_one_top_to_another() -> void:
	var router := _device(&"router_home")
	assert_contains(world.top_problem(router.id, &"desk", Vector3(0.40, 0.0, -1.25), 0.0), "ocupado", "where the monitor is")
	assert_contains(world.top_problem(router.id, &"bed", Vector3(-1.24, 0.0, -0.465), 0.0), "va encima de un mueble", "the bed has no top for it")
	assert_contains(world.top_problem(router.id, &"cabinet", Vector3(1.66, 0.0, -1.28), 0.0), "borde", "half off the cabinet")
	var r := world.place_on_furniture(router.id, &"desk", Vector3(0.95, 0.0, -1.25), 180.0)
	assert_true(r.ok, r.message)
	assert_eq(router.furniture_id, &"desk", "now it belongs to the desk")
	assert_almost(router.position.y, 0.75, 0.0001, "on the desk top")
	for cable_id: int in world.cable_ends:
		assert_true(world.cable_route(cable_id)["ok"], "cable %d laid again" % cable_id)
	assert_true(world.move_furniture(&"cabinet", Vector3(1.45, 0.0, -0.75), 0.0).ok, "the cabinet moves alone now")
	assert_almost(router.position.z, -1.25, 0.0001, "the router stayed on the desk")


func test_save_keeps_the_layout() -> void:
	assert_true(world.move_furniture(&"rug", Vector3(0.6, 0.0, 0.5), 90.0).ok, "rug")
	assert_true(world.move_furniture(&"cabinet", Vector3(1.45, 0.0, -0.75), 0.0).ok, "cabinet")
	var text := SaveGame.to_text(SaveGame.build(world, {}))
	var parsed := SaveGame.parse(text)
	assert_true(parsed["ok"], "parse")
	var loaded := BedroomScenario.restore((parsed["document"] as Dictionary)["sim"])
	assert_eq(loaded.get_furniture(&"rug").yaw_degrees, 90.0, "rug turn")
	assert_almost(loaded.get_furniture(&"cabinet").position.z, -0.75, 0.0001, "cabinet spot")
	assert_eq(_device_in(loaded, &"router_home").furniture_id, &"cabinet", "router still on it")
	assert_eq(loaded.obstacles, world.obstacles, "same footprints")


func test_old_saves_get_the_starting_layout() -> void:
	var state := world.save_state()
	state.erase("furniture")
	for d: Dictionary in state["devices"]:
		d.erase("furniture")
	var loaded := BedroomScenario.restore(JSON.parse_string(JSON.stringify(state)))
	assert_eq(_device_in(loaded, &"pc_old").furniture_id, &"desk", "PC with the desk")
	assert_eq(_device_in(loaded, &"router_home").furniture_id, &"cabinet", "router on the cabinet")
	assert_eq(loaded.get_furniture(&"bed").position, Vector3(-1.24, 0.0, -0.465), "starting bed spot")


func _device(item_id: StringName) -> SimDevice:
	return _device_in(world, item_id)


func _device_in(w: SimWorld, item_id: StringName) -> SimDevice:
	for d: SimDevice in w.devices.values():
		if d.definition.id == item_id:
			return d
	return null


func _has_rect(list: Array[Rect2], wanted: Rect2) -> bool:
	for r: Rect2 in list:
		if r.position.is_equal_approx(wanted.position) and r.size.is_equal_approx(wanted.size):
			return true
	return false


func _assert_same_rects(actual: Array[Rect2], expected: Array, label: String) -> void:
	assert_eq(actual.size(), expected.size(), "%s: count" % label)
	for wanted: Rect2 in expected:
		assert_true(_has_rect(actual, wanted), "%s: %s missing (got %s)" % [label, wanted, actual])
