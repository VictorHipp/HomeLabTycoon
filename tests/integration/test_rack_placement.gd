extends TestCase
## Where a rack can go and how the player gets out of a bad spot (docs/INTERACTION_SYSTEM.md §8.1):
## service clearance in front and behind, warnings for power cable reach, moving a placed rack
## with its devices, and picking it up again.

const GOOD_POS := Vector3(0.9, 0.0, 0.5)
const GOOD_YAW := 90.0 ## Front to the right wall, rear (power) towards the room.
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
	var zones := SimWorld.service_zones(rack.definition, GOOD_POS, GOOD_YAW)
	var more: Array[StringName] = [&"rack_12u_open"]
	assert_true(world.purchase(more).ok, "second rack")
	world.skip_to_next_event()
	for package_id: int in world.packages.keys():
		world.open_package(package_id)
	var second := _inventory(&"rack_12u_open")
	var spot := Vector3(0.0, 0.0, 0.5) # behind the first rack, not touching it
	var rect := SimWorld.footprint_rect(second.definition, spot, 0.0)
	assert_true(rect.intersects(zones[0]) or rect.intersects(zones[1]), "spot overlaps a working zone")
	assert_contains(world.placement_problem(second.id, spot, 0.0), "espacio de trabajo", "keeps the first rack reachable")


func test_power_reach_estimate_warns_far_from_the_strip() -> void:
	var near := world.rack_power_estimate(rack.id, GOOD_POS, GOOD_YAW)
	assert_true(near["needed"] <= near["included"], "the 3 m cord that comes with the equipment reaches (%.2f m)" % near["needed"])
	var far := world.rack_power_estimate(rack.id, FAR_POS, 0.0)
	assert_true(far["needed"] > far["included"], "in the far corner it does not (%.2f m)" % far["needed"])
	assert_true(far["needed"] <= far["longest"], "but the 5 m one from the shop would")
	assert_eq(far["included"], 3.0, "cord that comes in the boxes")
	assert_eq(far["longest"], 5.0, "longest power cable in the shop")
	assert_true(world.rack_power_estimate(sw.id, GOOD_POS, 0.0).is_empty(), "only for racks")
	assert_eq(rack.location, &"inventory", "the estimate does not leave the rack placed")


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
	assert_eq(world.placement_problem(rack.id, GOOD_POS, GOOD_YAW), "", "a loose end hangs: the rack can be moved")
	var moved := world.place_device(rack.id, GOOD_POS, GOOD_YAW)
	assert_true(moved.ok, "move the rack: " + moved.message)
	assert_contains(moved.message, "movido", "says it was moved")
	assert_eq(sw.location, &"mounted", "the switch stays mounted while the rack moves")
	assert_true(world.device_anchor(sw).distance_to(SimWorld.rack_unit_anchor(rack.definition, GOOD_POS, GOOD_YAW, 9)) < 0.001, "and moves with it")
	assert_true(world.connect_cable(cord.id, PortRef.make(strip.id, &"outlet", 2)).ok, "now it reaches")


func test_moving_with_cables_checks_them_again() -> void:
	assert_true(world.place_device(rack.id, GOOD_POS, GOOD_YAW).ok, "place")
	assert_true(world.mount_device(sw.id, rack.id, 9).ok, "mount switch")
	var cord := _inventory(&"power_cord_3m")
	var strip := world.devices_of(&"power")[0]
	world.connect_cable(cord.id, PortRef.make(sw.id, &"psu", 0))
	assert_true(world.connect_cable(cord.id, PortRef.make(strip.id, &"outlet", 2)).ok, "power connected")
	var problem := world.placement_problem(rack.id, FAR_POS, 0.0)
	assert_contains(problem, "no llegaría", "moving far would leave the cord short: refused with the reason")
	var before := world.cable_route(cord.id)["length"] as float
	var nearby := GOOD_POS + Vector3(0.0, 0.0, -0.05)
	assert_eq(world.placement_problem(rack.id, nearby, GOOD_YAW), "", "a small move keeps the cable valid")
	assert_true(world.place_device(rack.id, nearby, GOOD_YAW).ok, "move with the cable plugged in")
	var after := world.cable_route(cord.id)
	assert_true(after["ok"], "the cable is routed again")
	assert_true(not is_equal_approx(after["length"], before), "and its route follows the rack")


func test_pick_up_needs_an_empty_rack() -> void:
	assert_true(world.place_device(rack.id, GOOD_POS, GOOD_YAW).ok, "place")
	assert_true(world.mount_device(sw.id, rack.id, 9).ok, "mount")
	assert_false(world.pick_up_device(rack.id).ok, "not with a switch inside")
	assert_true(world.unmount_device(sw.id).ok, "unmount")
	assert_true(world.pick_up_device(rack.id).ok, "empty rack back to the inventory")
	assert_eq(rack.location, &"inventory", "in the inventory")


## Sweep: wherever the rack is accepted (positions x 4 turns), every laid cable still has a
## route that fits its length and never runs through furniture, devices or the delivery zone.
func test_accepted_spots_never_break_cables() -> void:
	var accepted := 0
	for ix: int in range(-6, 7):
		for iz: int in range(-5, 6):
			for yaw: float in [0.0, 90.0, 180.0, 270.0]:
				var pos := Vector3(ix * 0.25, 0.0, iz * 0.25)
				if world.placement_problem(rack.id, pos, yaw) != "":
					continue
				accepted += 1
				assert_true(world.place_device(rack.id, pos, yaw).ok, "place at %s %d" % [pos, yaw])
				for cable_id: int in world.cable_ends:
					_assert_route_clean(cable_id, "rack at %s %d" % [pos, yaw])
				assert_true(world.pick_up_device(rack.id).ok, "pick up")
	assert_true(accepted > 10, "the sweep found valid spots (%d)" % accepted)


func _assert_route_clean(cable_id: int, label: String) -> void:
	var route := world.cable_route(cable_id)
	var spec := world.get_device(cable_id).definition.get_spec(CableSpec) as CableSpec
	assert_true(route["ok"], "%s: cable %d routed" % [label, cable_id])
	if not route["ok"]:
		return
	assert_true(route["length"] <= spec.length_m, "%s: cable %d fits (%.2f m)" % [label, cable_id, route["length"]])
	var blocked: Array[Rect2] = []
	blocked.assign(world.cable_obstacles)
	blocked.append(world.delivery_zone)
	for d: SimDevice in world.devices.values():
		if d.location in [&"placed", &"fixed"] and d.definition.placement == &"floor":
			blocked.append(SimWorld.footprint_rect(d.definition, d.position, d.yaw_degrees))
	var points: PackedVector2Array = route["floor"]
	# The first and last 6 cm are the cable leaving its own device: checked from there on.
	for i: int in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var steps := maxi(1, ceili(a.distance_to(b) / 0.02))
		for k: int in steps + 1:
			var p := a.lerp(b, float(k) / steps)
			if p.distance_to(points[0]) < 0.06 or p.distance_to(points[points.size() - 1]) < 0.06:
				continue
			assert_true(world.room_bounds.has_point(p), "%s: cable %d inside the room" % [label, cable_id])
			for rect: Rect2 in blocked:
				if rect.has_point(p):
					_fail("%s: cable %d crosses %s at %s" % [label, cable_id, rect, p])
					return


