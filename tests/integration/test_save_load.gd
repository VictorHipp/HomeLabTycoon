extends TestCase
## Save / load of the simulation (docs/ARCHITECTURE.md §7, docs/TEST_PLAN.md H7-05/H7-06):
## save -> load -> save gives the same text, and the loaded game behaves the same.

const RACK_POS := Vector3(0.9, 0.0, 0.5)
const RACK_YAW := 90.0

var world: SimWorld


func before_each() -> void:
	world = BedroomScenario.create()


func _inventory(item_id: StringName) -> SimDevice:
	for d: SimDevice in world.inventory():
		if d.definition.id == item_id:
			return d
	return null


func _one(category: StringName) -> SimDevice:
	return world.devices_of(category)[0]


## A game in the middle of the mission: rack with switch and server, power, network, a loose
## cable end, a second order on its way.
func _mid_game() -> Dictionary:
	var items: Array[StringName] = [&"rack_12u_open", &"switch_16p_1u", &"server_1u_entry", &"cable_cat6_1m", &"cable_cat6_5m"]
	assert_true(world.purchase(items).ok, "purchase")
	world.skip_to_next_event()
	for package_id: int in world.packages.keys():
		world.open_package(package_id)
	var rack := _inventory(&"rack_12u_open")
	var sw := _inventory(&"switch_16p_1u")
	var srv := _inventory(&"server_1u_entry")
	assert_true(world.place_device(rack.id, RACK_POS, RACK_YAW).ok, "place")
	assert_true(world.mount_device(sw.id, rack.id, 9).ok, "mount switch")
	assert_true(world.mount_device(srv.id, rack.id, 5).ok, "mount server")
	var strip := _one(&"power")
	for pair: Array in [[sw, 2], [srv, 3]]:
		var cord := _inventory(&"power_cord_3m")
		world.connect_cable(cord.id, PortRef.make((pair[0] as SimDevice).id, &"psu", 0))
		world.connect_cable(cord.id, PortRef.make(strip.id, &"outlet", pair[1]))
	world.press_power(srv.id)
	world.step_minutes(3.0)
	var c1 := _inventory(&"cable_cat6_1m")
	world.connect_cable(c1.id, PortRef.make(srv.id, &"lan", 0))
	world.connect_cable(c1.id, PortRef.make(sw.id, &"lan", 0))
	var c3 := _inventory(&"cable_cat6_5m")
	assert_true(world.connect_cable(c3.id, PortRef.make(sw.id, &"lan", 1)).ok, "loose end")
	var more: Array[StringName] = [&"cable_cat6_3m"]
	assert_true(world.purchase(more).ok, "second order on its way")
	return {"rack": rack, "sw": sw, "srv": srv, "loose": c3}


func _round_trip(source: SimWorld) -> Array:
	var text := SaveGame.to_text(SaveGame.build(source, {"note": "test"}))
	var parsed := SaveGame.parse(text)
	assert_true(parsed["ok"], "parse: " + str(parsed["message"]))
	var document: Dictionary = parsed["document"]
	var loaded := BedroomScenario.restore(document["sim"])
	return [text, loaded, document]


func test_save_load_save_is_identical() -> void:
	_mid_game()
	var result := _round_trip(world)
	var again := SaveGame.to_text(SaveGame.build(result[1], {"note": "test"}))
	assert_eq(again, result[0], "save -> load -> save gives the same document")
	assert_eq((result[2] as Dictionary)["version"], float(SaveGame.VERSION), "the file carries the version")


func test_loaded_game_behaves_the_same() -> void:
	var parts := _mid_game()
	var loaded: SimWorld = _round_trip(world)[1]
	assert_eq(loaded.credits, world.credits, "credits")
	assert_eq(loaded.pending_cable(), (parts["loose"] as SimDevice).id, "the loose cable end is still loose")
	var srv := loaded.get_device((parts["srv"] as SimDevice).id)
	assert_true(srv.is_running(), "server still running")
	assert_eq(srv.rack_u, 5, "still in U5")
	# Finish the mission in the loaded game.
	var router := loaded.devices_of(&"router")[0]
	assert_true(loaded.connect_cable((parts["loose"] as SimDevice).id, PortRef.make(router.id, &"lan", 1)).ok, "plug the loose end")
	Shell.new(srv.id, "root").run(loaded, "ip address add 192.168.1.50/24 dev eth0")
	loaded.step_minutes(0.5)
	assert_true(loaded.mission.completed, "mission completed after loading")
	# The order in transit arrives.
	assert_true(loaded.skip_to_next_event().ok, "skip")
	assert_eq(loaded.packages.size(), 1, "the second order is delivered")


func test_rewards_are_not_granted_again_after_loading() -> void:
	var parts := _mid_game()
	var router := _one(&"router")
	world.connect_cable((parts["loose"] as SimDevice).id, PortRef.make(router.id, &"lan", 1))
	Shell.new((parts["srv"] as SimDevice).id, "root").run(world, "ip address add 192.168.1.50/24 dev eth0")
	world.step_minutes(0.5)
	assert_true(world.mission.completed, "completed before saving")
	var xp := world.xp
	var loaded: SimWorld = _round_trip(world)[1]
	loaded.step_minutes(5.0)
	assert_eq(loaded.xp, xp, "no second reward")
	assert_true(loaded.mission.completed, "still completed")


func test_runtime_ip_and_boot_in_progress_survive() -> void:
	var parts := _mid_game()
	var srv := parts["srv"] as SimDevice
	Shell.new(srv.id, "root").run(world, "ip address add 192.168.1.50/24 dev eth0")
	var loaded: SimWorld = _round_trip(world)[1]
	assert_eq(IPv4.format(NetworkEngine.device_ips(loaded, loaded.get_device(srv.id))[0]), "192.168.1.50", "runtime IP kept")
	# A device booting when saved keeps booting after loading.
	world.press_power(srv.id) # off
	world.step_minutes(0.5)
	world.press_power(srv.id) # on again: booting
	world.step_minutes(0.2)
	assert_eq(srv.state, &"booting", "booting before saving")
	var loaded2: SimWorld = _round_trip(world)[1]
	var srv2 := loaded2.get_device(srv.id)
	assert_eq(srv2.state, &"booting", "booting after loading")
	loaded2.step_minutes(3.0)
	assert_true(srv2.is_running(), "and finishes booting")


func test_bad_files_are_rejected_with_a_reason() -> void:
	assert_false(SaveGame.parse("hola")["ok"], "not JSON")
	assert_false(SaveGame.parse("{\"format\": \"otra cosa\"}")["ok"], "wrong format")
	var future := SaveGame.parse(JSON.stringify({"format": SaveGame.FORMAT, "version": 99, "sim": {}}))
	assert_false(future["ok"], "newer version")
	assert_contains(future["message"], "versión", "explains why")
