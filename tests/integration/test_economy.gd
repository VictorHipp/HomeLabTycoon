extends TestCase
## Economy (docs/PROGRESSION.md §8; ADR 0010): every credit has a reason in the ledger, rewards
## are paid once, passive income needs equipment really online and is capped per day, and the
## second-hand market always pays less than the shop.

const RACK_POS := Vector3(0.2, 0.0, 0.6)

var world: SimWorld


func before_each() -> void:
	world = BedroomScenario.create()


func _inventory(item_id: StringName) -> SimDevice:
	for d: SimDevice in world.inventory():
		if d.definition.id == item_id:
			return d
	return null


func _buy(items: Array[StringName]) -> void:
	assert_true(world.purchase(items).ok, "purchase")
	world.skip_to_next_event()
	for package_id: int in world.packages.keys():
		world.open_package(package_id)


func _connect(item_id: StringName, a: String, b: String) -> void:
	var cable := _inventory(item_id)
	assert_true(world.connect_cable(cable.id, a).ok, "plug %s" % a)
	var r := world.connect_cable(cable.id, b)
	assert_true(r.ok, "plug %s: %s" % [b, r.message])


## Rack, switch and server installed, powered, cabled and with an IP: the mission is done and the
## server is online.
func _server_online() -> SimDevice:
	var items: Array[StringName] = [&"rack_12u_open", &"switch_16p_1u", &"server_1u_entry", &"cable_cat6_1m", &"cable_cat6_5m"]
	_buy(items)
	var rack := _inventory(&"rack_12u_open")
	var sw := _inventory(&"switch_16p_1u")
	var srv := _inventory(&"server_1u_entry")
	var strip := world.devices_of(&"power")[0]
	var router := world.devices_of(&"router")[0]
	assert_true(world.place_device(rack.id, RACK_POS, 0.0).ok, "place rack")
	world.mount_device(sw.id, rack.id, 9)
	world.mount_device(srv.id, rack.id, 5)
	_connect(&"power_cord_3m", PortRef.make(sw.id, &"psu", 0), PortRef.make(strip.id, &"outlet", 2))
	_connect(&"power_cord_3m", PortRef.make(srv.id, &"psu", 0), PortRef.make(strip.id, &"outlet", 3))
	world.press_power(srv.id)
	world.step_minutes(3.0)
	_connect(&"cable_cat6_1m", PortRef.make(srv.id, &"lan", 0), PortRef.make(sw.id, &"lan", 0))
	_connect(&"cable_cat6_5m", PortRef.make(sw.id, &"lan", 1), PortRef.make(router.id, &"lan", 1))
	Shell.new(srv.id, "root").run(world, "ip address add 192.168.1.50/24 dev eth0")
	world.step_minutes(1.0)
	return srv


func _ledger_sum() -> int:
	var total := 0
	for line: Dictionary in world.economy.ledger:
		total += int(line["credits"])
	return total


func test_every_credit_has_a_reason() -> void:
	assert_eq(world.credits, BedroomScenario.START_CREDITS, "start credits")
	assert_eq(world.economy.ledger[0]["kind"], "start", "first line: the savings you start with")
	_server_online()
	assert_true(world.mission.completed, "mission completed")
	assert_eq(_ledger_sum(), world.credits, "the ledger adds up to the balance")
	var kinds: Array[String] = []
	for line: Dictionary in world.economy.ledger:
		if not kinds.has(String(line["kind"])):
			kinds.append(String(line["kind"]))
	for kind: String in ["start", "purchase", "skill", "reward"]:
		assert_true(kinds.has(kind), "ledger has a %s line" % kind)


func test_cash_flow_of_the_first_mission() -> void:
	# Kit: rack 220 + switch 90 + server 480 + 1 m 6 + 5 m 12 = 808, reward 600 (PROGRESSION §9).
	_server_online()
	assert_eq(world.credits, BedroomScenario.START_CREDITS - 808 + 600, "start - kit + reward")
	assert_eq(world.xp, world.mission.total_xp(), "all the mission XP")
	assert_eq(world.mission.total_xp(), 150, "150 XP in total, as confirmed")
	var tight := BedroomScenario.START_CREDITS - 808
	assert_true(tight > 0 and tight < 300, "the kit fits with a small margin (%d)" % tight)


func test_requirement_xp_is_paid_once() -> void:
	var items: Array[StringName] = [&"rack_12u_open"]
	_buy(items)
	var rack := _inventory(&"rack_12u_open")
	assert_true(world.place_device(rack.id, RACK_POS, 0.0).ok, "place")
	var xp := world.xp
	assert_eq(xp, 10, "XP for placing the rack")
	world.pick_up_device(rack.id)
	world.step_minutes(1.0)
	world.place_device(rack.id, RACK_POS, 0.0)
	world.step_minutes(1.0)
	assert_eq(world.xp, xp, "placing it again gives nothing")


func test_passive_income_needs_an_online_server_and_is_capped() -> void:
	var before := world.credits
	world.step_minutes(180.0)
	assert_eq(world.credits, before, "nothing online, nothing earned")
	var srv := _server_online()
	assert_eq(world.economy.passive_rate(world), srv.definition.online_income_per_hour, "the server earns")
	var start := world.credits
	world.step_minutes(120.0)
	var two_hours := world.credits - start
	assert_true(two_hours >= srv.definition.online_income_per_hour and two_hours <= 2 * srv.definition.online_income_per_hour,
		"about the hourly rate (%d in 2 h)" % two_hours)
	world.step_minutes(48.0 * 60.0)
	var paid_days := world.economy.passive_paid_total
	assert_true(paid_days <= 3 * world.economy.rules.passive_daily_cap, "never more than the daily cap (%d)" % paid_days)
	# Without power the server is not online: no more income.
	world.press_power(srv.id)
	world.step_minutes(1.0)
	var off := world.credits
	world.step_minutes(240.0)
	assert_eq(world.credits, off, "switched off, nothing earned")


func test_waiting_for_a_delivery_is_not_a_money_pump() -> void:
	_server_online()
	var start := world.credits
	for _i: int in 20:
		var cheap: Array[StringName] = [&"cable_cat6_1m"]
		_buy(cheap) # 6 credits and a 2 h wait each time
		for d: SimDevice in world.inventory():
			if d.definition.id == &"cable_cat6_1m":
				world.sell_device(d.id)
	var gained := world.credits - start
	var days := 20.0 * SimWorld.DELIVERY_MINUTES / 1440.0
	assert_true(gained <= ceili(days + 1.0) * world.economy.rules.passive_daily_cap, "bounded by the daily cap (%d)" % gained)


func test_second_hand_always_pays_less_than_the_shop() -> void:
	for def: HardwareDefinition in world.catalog.purchasable_items():
		var d := SimDevice.new(9999, def)
		d.bought = true
		var resale := world.economy.resale_price(d)
		for extra: StringName in def.box_contents:
			var accessory := SimDevice.new(9998, world.catalog.get_item(extra))
			accessory.bought = true
			resale += world.economy.resale_price(accessory)
		assert_true(resale < def.price, "%s: %d < %d" % [def.id, resale, def.price])
		d.used = true
		var unused := SimDevice.new(9997, def)
		unused.bought = true
		assert_true(world.economy.resale_price(d) < world.economy.resale_price(unused) or def.price < 3, "%s: used pays less" % def.id)


func test_selling_rules() -> void:
	var items: Array[StringName] = [&"rack_12u_open", &"cable_cat6_3m"]
	_buy(items)
	var rack := _inventory(&"rack_12u_open")
	var pc := world.devices_of(&"computer")[0]
	assert_false(world.sell_device(pc.id).ok, "the PC of the house is not for sale")
	# The cables the house came with were never bought: unplugged, they still cannot be sold.
	var house_cable: int = world.port_cable[PortRef.make(pc.id, &"psu", 0)]
	world.disconnect_port(PortRef.make(pc.id, &"psu", 0))
	var refused := world.sell_device(house_cable)
	assert_false(refused.ok, "a cable of the house is not for sale")
	assert_contains(refused.message, "parte de la casa", "says why")
	world.connect_cable(house_cable, PortRef.make(pc.id, &"psu", 0))
	world.connect_cable(house_cable, PortRef.make(world.devices_of(&"power")[0].id, &"outlet", 0))
	world.step_minutes(3.0) # the PC boots again and gets its address: the market needs Internet
	assert_true(pc.is_running(), "PC running again")
	assert_true(world.place_device(rack.id, RACK_POS, 0.0).ok, "place")
	var placed := world.sell_device(rack.id)
	assert_false(placed.ok, "only from the inventory")
	assert_contains(placed.message, "inventario", "says why")
	world.pick_up_device(rack.id)
	var before := world.credits
	var sold := world.sell_device(rack.id)
	assert_true(sold.ok, "sold: " + sold.message)
	assert_eq(world.credits - before, 220 * world.economy.rules.resale_used_percent / 100, "used price")
	assert_eq(rack.location, &"sold", "kept as sold")
	assert_false(world.sell_device(rack.id).ok, "cannot be sold twice")
	assert_eq(world.economy.ledger[world.economy.ledger.size() - 1]["kind"], "sale", "ledger line")
	var cable := _inventory(&"cable_cat6_3m")
	before = world.credits
	assert_true(world.sell_device(cable.id).ok, "unused cable")
	assert_eq(world.credits - before, 9 * world.economy.rules.resale_unused_percent / 100, "unused price")
	# The orders page still names what was sold.
	for order: Dictionary in world.orders:
		for group: Array in order["groups"]:
			assert_true(world.get_device(group[0]) != null, "order item still known")


func test_economy_survives_save_and_load() -> void:
	_server_online()
	world.step_minutes(90.0)
	var text := SaveGame.to_text(SaveGame.build(world, {}))
	var parsed := SaveGame.parse(text)
	assert_true(parsed["ok"], "parse")
	var loaded := BedroomScenario.restore(parsed["document"]["sim"])
	assert_eq(loaded.credits, world.credits, "credits")
	assert_eq(loaded.economy.ledger.size(), world.economy.ledger.size(), "ledger lines")
	assert_eq(loaded.economy.passive_paid_today, world.economy.passive_paid_today, "paid today")
	assert_almost(loaded.economy.passive_pending, world.economy.passive_pending, 0.0001, "pending fraction")
	assert_eq(loaded.mission.rewarded, world.mission.rewarded, "requirement XP given")


func test_version_1_saves_still_load() -> void:
	_server_online()
	var document := SaveGame.build(world, {})
	document["version"] = 1
	var sim: Dictionary = document["sim"]
	sim.erase("economy")
	(sim["mission"] as Dictionary).erase("rewarded")
	for device: Dictionary in sim["devices"]:
		device.erase("used")
		device.erase("bought")
	var parsed := SaveGame.parse(SaveGame.to_text(document))
	assert_true(parsed["ok"], "v1 parses")
	var loaded := BedroomScenario.restore(parsed["document"]["sim"])
	assert_eq(loaded.credits, world.credits, "credits kept")
	assert_true(loaded.mission.completed, "mission kept")
	var xp := loaded.xp
	loaded.step_minutes(10.0)
	assert_eq(loaded.xp, xp, "a completed v1 mission gives no XP again")
	for d: SimDevice in loaded.devices.values():
		if d.location == &"mounted":
			assert_true(d.used, "installed devices count as used")
			assert_true(d.bought, "what came in an order was bought")
		if d.location == &"fixed":
			assert_false(d.bought, "the house's devices were not bought")
