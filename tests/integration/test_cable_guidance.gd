extends TestCase
## Read-only queries behind the guided cabling (docs/INTERACTION_SYSTEM.md §9; ADR 0011): which
## free sockets fit the cable now, whether the second end reaches, and cancelling a cable that
## is half laid.

var world: SimWorld
var rack: SimDevice
var sw: SimDevice
var srv: SimDevice


func before_each() -> void:
	world = BedroomScenario.create()
	var items: Array[StringName] = [&"rack_12u_open", &"switch_16p_1u", &"server_1u_entry", &"cable_cat6_1m"]
	world.purchase(items)
	world.skip_to_next_event()
	for package_id: int in world.packages.keys():
		world.open_package(package_id)
	rack = _inventory(&"rack_12u_open")
	sw = _inventory(&"switch_16p_1u")
	srv = _inventory(&"server_1u_entry")
	world.place_device(rack.id, Vector3(0.2, 0.0, 0.6), 0.0)
	world.mount_device(sw.id, rack.id, 9)
	world.mount_device(srv.id, rack.id, 5)


func _inventory(item_id: StringName) -> SimDevice:
	for d: SimDevice in world.inventory():
		if d.definition.id == item_id:
			return d
	return null


func _kinds(refs: Array[String]) -> Array[int]:
	var kinds: Array[int] = []
	for ref: String in refs:
		var d := world.get_device(PortRef.device_id(ref))
		var kind := d.definition.find_port_group(PortRef.group(ref)).kind
		if not kinds.has(kind):
			kinds.append(kind)
	return kinds


func test_power_cord_steps() -> void:
	var cord := _inventory(&"power_cord_3m")
	var first := world.compatible_ports(cord.id)
	var kinds := _kinds(first)
	assert_true(kinds.has(PortDefinition.Kind.POWER_C13) and kinds.has(PortDefinition.Kind.POWER_C14), "step 1: outlets and power inlets")
	assert_false(first.has(PortRef.make(sw.id, &"lan", 0)), "never a network port")
	assert_true(world.connect_cable(cord.id, PortRef.make(sw.id, &"psu", 0)).ok, "first end on the switch inlet")
	var second := world.compatible_ports(cord.id)
	assert_eq(_kinds(second), [PortDefinition.Kind.POWER_C13] as Array[int], "step 2: only free outlets")
	assert_contains(world.cable_port_problem(cord.id, PortRef.make(srv.id, &"psu", 0)), "toma de la regleta", "inlet to inlet is explained")
	var strip := world.devices_of(&"power")[0]
	assert_true(world.cable_reach(cord.id, PortRef.make(strip.id, &"outlet", 2))["ok"], "reaches the strip from this spot")


func test_network_cable_steps() -> void:
	var cable := _inventory(&"cable_cat6_1m")
	var first := world.compatible_ports(cable.id)
	assert_eq(_kinds(first), [PortDefinition.Kind.RJ45] as Array[int], "only RJ45")
	var pc := world.devices_of(&"computer")[0]
	assert_false(first.has(PortRef.make(pc.id, &"lan", 0)), "occupied ports are not offered")
	world.connect_cable(cable.id, PortRef.make(srv.id, &"lan", 0))
	var second := world.compatible_ports(cable.id)
	assert_false(second.has(PortRef.make(srv.id, &"lan", 1)), "not the same device")
	assert_true(second.has(PortRef.make(sw.id, &"lan", 0)), "the switch is offered")
	var router := world.devices_of(&"router")[0]
	var far := world.cable_reach(cable.id, PortRef.make(router.id, &"lan", 1))
	assert_false(far["ok"], "1 m does not reach the router")
	assert_contains(String(far["reason"]), "no llega", "and says so")
	assert_true(world.cable_reach(cable.id, PortRef.make(sw.id, &"lan", 0))["ok"], "reaches the switch in the same rack")


func test_cancel_returns_the_cable() -> void:
	var cable := _inventory(&"cable_cat6_1m")
	world.connect_cable(cable.id, PortRef.make(srv.id, &"lan", 0))
	assert_eq(world.pending_cable(), cable.id, "half laid")
	assert_true(world.cancel_cable(cable.id).ok, "cancel")
	assert_eq(cable.location, &"inventory", "back in the inventory")
	assert_eq(world.pending_cable(), -1, "nothing half laid")
	assert_false(world.port_cable.has(PortRef.make(srv.id, &"lan", 0)), "socket free again")
	world.connect_cable(cable.id, PortRef.make(srv.id, &"lan", 0))
	world.connect_cable(cable.id, PortRef.make(sw.id, &"lan", 0))
	assert_false(world.cancel_cable(cable.id).ok, "a finished cable is not cancelled")
	assert_eq(cable.location, &"cabled", "and stays")


func test_needed_metres_round_up() -> void:
	assert_eq(SimWorld.metres_needed(3.02), "3,1", "3.02 m needed is 3,1")
	assert_eq(SimWorld.metres_needed(3.0), "3,0", "exact stays")
