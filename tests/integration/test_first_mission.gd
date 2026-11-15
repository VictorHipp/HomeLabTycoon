extends TestCase
## The first mission played only through simulation commands (docs/TEST_PLAN.md H7-01):
## two different valid solutions, and one negative case per requirement.

const RACK_POS := Vector3(1.2, 0.0, -0.3)

var world: SimWorld


func before_each() -> void:
	world = BedroomScenario.create()


# ----------------------------------------------------------------- helpers --

func _buy_and_unpack(items: Array[StringName]) -> void:
	var r := world.purchase(items)
	assert_true(r.ok, "purchase: " + r.message)
	assert_true(world.skip_to_next_event().ok, "skip to delivery")
	var boxes := 0
	var has_cables := false
	for item_id: StringName in items:
		if world.catalog.get_item(item_id).category == &"cable":
			has_cables = true
		else:
			boxes += 1
	assert_eq(world.packages.size(), boxes + (1 if has_cables else 0), "one box per device, cables together")
	for package_id: int in world.packages.keys():
		assert_true(world.open_package(package_id).ok, "open package")


func _first_in_inventory(item_id: StringName) -> SimDevice:
	for d: SimDevice in world.inventory():
		if d.definition.id == item_id:
			return d
	return null


func _one(category: StringName) -> SimDevice:
	return world.devices_of(category)[0]


func _connect(item_id: StringName, a: String, b: String) -> void:
	var cable := _first_in_inventory(item_id)
	assert_true(cable != null, "%s in inventory" % item_id)
	var r1 := world.connect_cable(cable.id, a)
	assert_true(r1.ok, "plug %s: %s" % [a, r1.message])
	var r2 := world.connect_cable(cable.id, b)
	assert_true(r2.ok, "plug %s: %s" % [b, r2.message])


## Rack placed, switch U9 + server U5 mounted and powered on. Returns [rack, switch, server].
func _build_rack() -> Array[SimDevice]:
	var shopping: Array[StringName] = [&"rack_12u_open", &"switch_16p_1u", &"server_1u_entry", &"cable_cat6_1m", &"cable_cat6_3m"]
	_buy_and_unpack(shopping)
	var rack := _first_in_inventory(&"rack_12u_open")
	var sw := _first_in_inventory(&"switch_16p_1u")
	var srv := _first_in_inventory(&"server_1u_entry")
	assert_true(world.place_device(rack.id, RACK_POS, 0.0).ok, "place rack")
	assert_true(world.mount_device(sw.id, rack.id, 9).ok, "mount switch")
	assert_true(world.mount_device(srv.id, rack.id, 5).ok, "mount server")
	var strip := _one(&"power")
	_connect(&"power_cord_3m", PortRef.make(sw.id, &"psu", 0), PortRef.make(strip.id, &"outlet", 2))
	_connect(&"power_cord_3m", PortRef.make(srv.id, &"psu", 0), PortRef.make(strip.id, &"outlet", 3))
	assert_true(world.press_power(srv.id).ok, "power button")
	world.step_minutes(3.0)
	assert_true(srv.is_running() and sw.is_running(), "switch and server running")
	return [rack, sw, srv]


func _root_shell(server: SimDevice, line: String) -> String:
	var shell := Shell.new(server.id, "root")
	var r := shell.run(world, line)
	world.step_minutes(0.5)
	return r["output"]


func _requirement(id: StringName) -> bool:
	world.step_minutes(0.1)
	var reqs := world.mission.definition.requirements
	for i: int in reqs.size():
		if reqs[i].id == id:
			return world.mission.status[i]
	_fail("unknown requirement %s" % id)
	return false


# --------------------------------------------------------------- solutions --

func test_solution_a_server_via_switch_pc_on_router() -> void:
	var start_credits := world.credits
	var parts := _build_rack()
	var sw := parts[1]
	var srv := parts[2]
	var router := _one(&"router")
	_connect(&"cable_cat6_1m", PortRef.make(srv.id, &"lan", 0), PortRef.make(sw.id, &"lan", 0))
	_connect(&"cable_cat6_3m", PortRef.make(sw.id, &"lan", 1), PortRef.make(router.id, &"lan", 1))
	assert_false(world.mission.completed, "not complete before the IP")
	assert_eq(_root_shell(srv, "ip address add 192.168.1.50/24 dev eth0"), "", "ip add is silent")
	assert_true(world.mission.completed, "mission completed")
	var spent := 220 + 90 + 480 + 6 + 9
	assert_eq(world.credits, start_credits - spent + 600, "reward credited once")
	assert_eq(world.xp, 150, "xp granted")
	assert_eq(world.level(), 2, "level up")
	var pc_shell := Shell.new(_one(&"computer").id, "jugador")
	assert_contains(pc_shell.run(world, "ping -c 2 192.168.1.50")["output"], "64 bytes from 192.168.1.50", "PC pings server")
	world.step_minutes(10.0)
	assert_eq(world.xp, 150, "rewards are not granted twice")


func test_solution_b_pc_moved_to_switch() -> void:
	var parts := _build_rack()
	var sw := parts[1]
	var srv := parts[2]
	var pc := _one(&"computer")
	var router := _one(&"router")
	assert_true(world.disconnect_port(PortRef.make(pc.id, &"lan", 0)).ok, "unplug PC from router")
	_connect(&"cable_cat6_3m", PortRef.make(pc.id, &"lan", 0), PortRef.make(sw.id, &"lan", 4))
	_connect(&"cable_cat6_3m", PortRef.make(sw.id, &"lan", 5), PortRef.make(router.id, &"lan", 2))
	_connect(&"cable_cat6_1m", PortRef.make(srv.id, &"lan", 1), PortRef.make(sw.id, &"lan", 6))
	_root_shell(srv, "ip address add 192.168.1.60/24 dev eth1")
	assert_true(world.mission.completed, "mission completed with a different topology and port")


# -------------------------------------------------------- negative cases ----

func test_no_ip_means_no_communication() -> void:
	var parts := _build_rack()
	_connect(&"cable_cat6_1m", PortRef.make(parts[2].id, &"lan", 0), PortRef.make(parts[1].id, &"lan", 0))
	_connect(&"cable_cat6_3m", PortRef.make(parts[1].id, &"lan", 1), PortRef.make(_one(&"router").id, &"lan", 1))
	assert_false(_requirement(&"server_ip"), "no IP yet")
	assert_false(_requirement(&"pc_server_ping"), "cannot communicate without IP")


func test_wrong_subnet_fails() -> void:
	var parts := _build_rack()
	_connect(&"cable_cat6_1m", PortRef.make(parts[2].id, &"lan", 0), PortRef.make(parts[1].id, &"lan", 0))
	_connect(&"cable_cat6_3m", PortRef.make(parts[1].id, &"lan", 1), PortRef.make(_one(&"router").id, &"lan", 1))
	_root_shell(parts[2], "ip address add 10.0.0.5/8 dev eth0")
	assert_false(_requirement(&"server_ip"), "10.0.0.5 is not in the home network")
	assert_false(_requirement(&"pc_server_ping"), "different subnets do not talk without routing")


func test_ip_conflict_fails() -> void:
	var parts := _build_rack()
	_connect(&"cable_cat6_1m", PortRef.make(parts[2].id, &"lan", 0), PortRef.make(parts[1].id, &"lan", 0))
	_connect(&"cable_cat6_3m", PortRef.make(parts[1].id, &"lan", 1), PortRef.make(_one(&"router").id, &"lan", 1))
	var pc_ip := IPv4.format(NetworkEngine.device_ips(world, _one(&"computer"))[0])
	_root_shell(parts[2], "ip address add %s/24 dev eth0" % pc_ip)
	assert_false(_requirement(&"server_ip"), "duplicated IP %s must not count" % pc_ip)


func test_switch_without_uplink_fails() -> void:
	var parts := _build_rack()
	_connect(&"cable_cat6_1m", PortRef.make(parts[2].id, &"lan", 0), PortRef.make(parts[1].id, &"lan", 0))
	_root_shell(parts[2], "ip address add 192.168.1.50/24 dev eth0")
	assert_false(_requirement(&"switch_uplink"), "switch not connected to the router")
	assert_false(_requirement(&"pc_server_ping"), "isolated switch: no communication")


func test_server_straight_to_router_does_not_count_as_switch() -> void:
	var parts := _build_rack()
	_connect(&"cable_cat6_3m", PortRef.make(parts[2].id, &"lan", 0), PortRef.make(_one(&"router").id, &"lan", 1))
	_root_shell(parts[2], "ip address add 192.168.1.50/24 dev eth0")
	assert_true(_requirement(&"pc_server_ping"), "they do communicate through the router")
	assert_false(_requirement(&"server_to_switch"), "but the mission asks for the switch")
	assert_false(world.mission.completed, "so the mission is not complete")


func test_power_loss_drops_runtime_ip() -> void:
	var parts := _build_rack()
	var srv := parts[2]
	_root_shell(srv, "ip address add 192.168.1.50/24 dev eth0")
	assert_true(world.disconnect_port(PortRef.make(srv.id, &"psu", 0)).ok, "unplug server power")
	world.step_minutes(1.0)
	assert_eq(srv.state, &"off", "server off")
	assert_true(NetworkEngine.device_ips(world, srv).is_empty(), "runtime IP lost (decision 9)")


# ------------------------------------------------------- rules on commands --

func test_shop_needs_internet_and_money() -> void:
	var router := _one(&"router")
	var expensive: Array[StringName] = [&"server_1u_entry", &"server_1u_entry", &"server_1u_entry", &"server_1u_entry"]
	assert_false(world.purchase(expensive).ok, "not enough credits")
	world.disconnect_port(PortRef.make(router.id, &"psu", 0))
	world.step_minutes(1.0)
	var cheap: Array[StringName] = [&"cable_cat6_1m"]
	var r := world.purchase(cheap)
	assert_false(r.ok, "no Internet without the router")
	assert_contains(r.message, "Internet", "message explains why")


func test_mounting_rules() -> void:
	var shopping: Array[StringName] = [&"rack_12u_open", &"switch_16p_1u", &"server_1u_entry"]
	_buy_and_unpack(shopping)
	var rack := _first_in_inventory(&"rack_12u_open")
	var sw := _first_in_inventory(&"switch_16p_1u")
	var srv := _first_in_inventory(&"server_1u_entry")
	assert_false(world.mount_device(sw.id, rack.id, 1).ok, "rack must be placed first")
	assert_false(world.place_device(rack.id, Vector3(-1.2, 0, -0.5), 0.0).ok, "cannot place on the bed")
	assert_false(world.place_device(rack.id, Vector3(1.7, 0, 0.0), 0.0).ok, "cannot place outside the room")
	assert_true(world.place_device(rack.id, RACK_POS, 0.0).ok, "place rack")
	assert_true(world.mount_device(sw.id, rack.id, 12).ok, "top unit is valid")
	assert_false(world.mount_device(srv.id, rack.id, 12).ok, "unit already taken")
	assert_false(world.mount_device(srv.id, rack.id, 13).ok, "beyond capacity")


func test_cable_rules() -> void:
	var parts := _build_rack()
	var cable := _first_in_inventory(&"cable_cat6_1m")
	var strip := _one(&"power")
	var pc := _one(&"computer")
	assert_false(world.connect_cable(cable.id, PortRef.make(strip.id, &"outlet", 0)).ok, "RJ45 cable into a power outlet")
	assert_true(world.connect_cable(cable.id, PortRef.make(parts[2].id, &"lan", 0)).ok, "first end")
	assert_eq(world.pending_cable(), cable.id, "cable with a loose end (decision 12)")
	var far := world.connect_cable(cable.id, PortRef.make(pc.id, &"psu", 0))
	assert_false(far.ok, "RJ45 into a power inlet")
	var too_short := world.connect_cable(cable.id, PortRef.make(_one(&"router").id, &"lan", 3))
	assert_false(too_short.ok, "1 m does not reach the router")
	assert_contains(too_short.message, "no llega", "explains the length")
