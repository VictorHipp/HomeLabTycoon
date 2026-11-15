extends TestCase
## Delivery zone (docs/INTERACTION_SYSTEM.md §7): every box waits in one stack inside the
## reserved zone by the entrance, keeps its own contents, and nothing may be placed there.

var world: SimWorld


func before_each() -> void:
	world = BedroomScenario.create()


func _deliver(items: Array[StringName]) -> void:
	assert_true(world.purchase(items).ok, "purchase")
	assert_true(world.skip_to_next_event().ok, "delivery")


func _inventory(item_id: StringName) -> SimDevice:
	for d: SimDevice in world.inventory():
		if d.definition.id == item_id:
			return d
	return null


func test_several_deliveries_stack_in_the_zone() -> void:
	var first: Array[StringName] = [&"rack_12u_open", &"switch_16p_1u"]
	var second: Array[StringName] = [&"server_1u_entry", &"cable_cat6_1m", &"cable_cat6_3m"]
	_deliver(first)
	_deliver(second)
	assert_eq(world.packages.size(), 4, "2 + (1 server + 1 box of cables)")
	var spot := world.delivery_spot()
	for package: Dictionary in world.packages.values():
		var p: Vector3 = package["position"]
		assert_true(p.is_equal_approx(spot), "every box in the same stack")
		assert_true(world.delivery_zone.has_point(Vector2(p.x, p.z)), "inside the delivery zone")
	assert_false(world.delivery_zone_blocked(), "zone free")


func test_each_box_keeps_its_contents_and_top_opens_first() -> void:
	var items: Array[StringName] = [&"switch_16p_1u", &"server_1u_entry"]
	_deliver(items)
	var top := world.top_package_id()
	var names: Array[String] = []
	for device_id: int in world.packages[top]["device_ids"]:
		names.append(world.get_device(device_id).definition.id)
	assert_eq(names, ["server_1u_entry", "power_cord_3m"] as Array[String], "the server box holds the server and its power cord")
	assert_true(world.open_package(top).ok, "open the top box")
	assert_eq(world.packages.size(), 1, "one box left")
	assert_true(_inventory(&"server_1u_entry") != null, "server in the inventory")
	assert_true(_inventory(&"switch_16p_1u") == null, "the switch is still boxed")


func test_nothing_can_be_placed_in_the_zone() -> void:
	var items: Array[StringName] = [&"rack_12u_open"]
	_deliver(items)
	world.open_package(world.top_package_id())
	var rack := _inventory(&"rack_12u_open")
	# Partly on the zone (clear of the bed): x -0.72..-0.18, z 0.50..1.10.
	assert_contains(world.placement_problem(rack.id, Vector3(-0.45, 0.0, 0.8), 0.0), "reservada para las entregas", "footprint on the zone")
	# A rack whose front working space (z 0.50..1.00) would cover the zone is refused as well.
	assert_contains(world.placement_problem(rack.id, Vector3(-0.45, 0.0, 0.2), 0.0), "libres", "service zone on the delivery zone")


func test_occupied_zone_in_an_old_save_keeps_objects_and_boxes() -> void:
	var items: Array[StringName] = [&"rack_12u_open", &"switch_16p_1u"]
	_deliver(items)
	world.open_package(world.packages.keys()[0] if world.get_device(world.packages[world.packages.keys()[0]]["device_ids"][0]).definition.id == &"rack_12u_open" else world.packages.keys()[1])
	var rack := _inventory(&"rack_12u_open")
	assert_true(rack != null, "rack unpacked")
	var more: Array[StringName] = [&"server_1u_entry"]
	assert_true(world.purchase(more).ok, "a box still on its way")
	# Simulate a game saved before the zone existed: the rack stands right on it.
	var c := world.delivery_zone.get_center()
	rack.location = &"placed"
	rack.position = Vector3(c.x, 0.0, c.y)
	var boxes_before := world.packages.size()
	var loaded := BedroomScenario.restore(world.save_state())
	assert_eq(loaded.get_device(rack.id).location, &"placed", "the rack is kept")
	assert_eq(loaded.packages.size(), boxes_before, "no box lost")
	assert_true(loaded.delivery_zone_blocked(), "zone reported as occupied")
	var spot := loaded.delivery_spot()
	var rack_rect := SimWorld.footprint_rect(rack.definition, rack.position, rack.yaw_degrees)
	assert_false(Rect2(spot.x - 0.25, spot.z - 0.2, 0.5, 0.4).intersects(rack_rect), "the stack moves next to it")
	for package: Dictionary in loaded.packages.values():
		assert_true((package["position"] as Vector3).is_equal_approx(spot), "boxes gathered on the new spot")
	assert_true(loaded.skip_to_next_event().ok, "the order on its way still arrives")
	assert_eq(loaded.packages.size(), boxes_before + 1, "and is stacked too")
