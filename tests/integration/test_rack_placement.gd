extends TestCase
## Where a rack can go and how the player gets out of a bad spot (docs/INTERACTION_SYSTEM.md §8.1):
## service clearance in front and behind, warnings for power cable reach, moving a placed rack
## with its devices, and picking it up again.

const GOOD_POS := Vector3(0.9, 0.0, 0.5)
const GOOD_YAW := 270.0
const FAR_POS := Vector3(1.45, 0.0, 0.65)

var world: SimWorld
var rack: SimDevice
var sw: SimDevice


func before_each() -> void:
	world = BedroomScenario.create()
	var items: Array[StringName] = [&"rack_12u_open", &"switch_16p_1u"]
	assert_true(world.purchase(items).ok, "purchase")
	world.skip_to_next_event()
	for package_id: int in world.packages.keys():
		world.open_package(package_id)
	rack = _inventory(&"rack_12u_open")
	sw = _inventory(&"switch_16p_1u")


func _inventory(item_id: StringName) -> SimDevice:
	for d: SimDevice in world.inventory():
		if d.definition.id == item_id:
			return d
	return null


func test_service_zones_follow_the_front() -> void:
	var zones := SimWorld.service_zones(rack.definition, Vector3.ZERO, 0.0)
	assert_eq(zones.size(), 2, "front and rear zones")
	assert_true(zones[0].get_center().y > 0.0, "yaw 0: the front faces +Z")
	assert_true(zones[1].get_center().y < 0.0, "yaw 0: the rear faces -Z")
	var turned := SimWorld.service_zones(rack.definition, Vector3.ZERO, 270.0)
	assert_true(turned[0].get_center().x < 0.0, "yaw 270: the front faces -X")
	assert_true(SimWorld.service_zones(sw.definition, Vector3.ZERO, 0.0).is_empty(), "only racks need clearance")


func test_rear_against_the_wall_is_rejected_with_reason() -> void:
	var problem := world.placement_problem(rack.id, Vector3(1.3, 0.0, 0.5), 90.0)
	assert_contains(problem, "libres delante y detrás", "front towards the right wall: no room to work")
	assert_eq(world.placement_problem(rack.id, Vector3(1.3, 0.0, 0.5), 180.0), "", "turned 90 degrees it fits")


func test_clearance_blocked_by_furniture() -> void:
	# The old prototype spot: the rear zone runs into the desk and the cabinet.
	assert_contains(world.placement_problem(rack.id, Vector3(1.2, 0.0, -0.3), 0.0), "libres", "rear zone hits the desk")


func test_nothing_may_be_placed_in_a_rack_service_zone() -> void:
	assert_true(world.place_device(rack.id, GOOD_POS, GOOD_YAW).ok, "place rack")
	var front := SimWorld.service_zones(rack.definition, GOOD_POS, GOOD_YAW)[0]
	var more: Array[StringName] = [&"rack_12u_open"]
	assert_true(world.purchase(more).ok, "second rack")
	world.skip_to_next_event()
	for package_id: int in world.packages.keys():
		world.open_package(package_id)
	var second := _inventory(&"rack_12u_open")
	var spot := Vector3(0.0, 0.0, 0.5) # in front of the first rack, not touching it
	assert_true(SimWorld.footprint_rect(second.definition, spot, 0.0).intersects(front), "spot overlaps the front zone")
	assert_contains(world.placement_problem(second.id, spot, 0.0), "espacio de trabajo", "keeps the first rack reachable")


func test_power_reach_estimate_warns_far_from_the_strip() -> void:
	var near := world.rack_power_estimate(rack.definition, GOOD_POS, GOOD_YAW)
	assert_true(near["needed"] <= near["longest"], "next to the desk the 3 m cord reaches (%.2f m)" % near["needed"])
	var far := world.rack_power_estimate(rack.definition, FAR_POS, 0.0)
	assert_true(far["needed"] > far["longest"], "in the far corner it does not (%.2f m)" % far["needed"])
	assert_eq(far["longest"], 3.0, "longest power cable in the catalog")
	assert_true(world.rack_power_estimate(sw.definition, GOOD_POS, 0.0).is_empty(), "only for racks")


func test_far_rack_cannot_be_powered_but_can_be_moved() -> void:
	assert_eq(world.placement_problem(rack.id, FAR_POS, 0.0), "", "the far spot itself is allowed (only a warning)")
	assert_true(world.place_device(rack.id, FAR_POS, 0.0).ok, "place far")
	assert_true(world.mount_device(sw.id, rack.id, 9).ok, "mount switch")
	var cord := _inventory(&"power_cord_3m")
	var strip := world.devices_of(&"power")[0]
	assert_true(world.connect_cable(cord.id, PortRef.make(sw.id, &"psu", 0)).ok, "first end on the switch")
	var r := world.connect_cable(cord.id, PortRef.make(strip.id, &"outlet", 2))
	assert_false(r.ok, "does not reach the strip")
	assert_contains(r.message, "no llega", "explains the length")
	assert_contains(world.placement_problem(rack.id, GOOD_POS, GOOD_YAW), "cables", "cannot move with a cable plugged in")
	assert_true(world.disconnect_port(PortRef.make(sw.id, &"psu", 0)).ok, "unplug the loose cable")
	var moved := world.place_device(rack.id, GOOD_POS, GOOD_YAW)
	assert_true(moved.ok, "move the rack: " + moved.message)
	assert_contains(moved.message, "movido", "says it was moved")
	assert_eq(sw.location, &"mounted", "the switch stays mounted while the rack moves")
	assert_true(world.device_anchor(sw).distance_to(SimWorld.rack_unit_anchor(rack.definition, GOOD_POS, GOOD_YAW, 9)) < 0.001, "and moves with it")
	assert_true(world.connect_cable(cord.id, PortRef.make(sw.id, &"psu", 0)).ok, "plug again")
	assert_true(world.connect_cable(cord.id, PortRef.make(strip.id, &"outlet", 2)).ok, "now it reaches")


func test_pick_up_needs_an_empty_rack() -> void:
	assert_true(world.place_device(rack.id, GOOD_POS, GOOD_YAW).ok, "place")
	assert_true(world.mount_device(sw.id, rack.id, 9).ok, "mount")
	assert_false(world.pick_up_device(rack.id).ok, "not with a switch inside")
	assert_true(world.unmount_device(sw.id).ok, "unmount")
	assert_true(world.pick_up_device(rack.id).ok, "empty rack back to the inventory")
	assert_eq(rack.location, &"inventory", "in the inventory")
