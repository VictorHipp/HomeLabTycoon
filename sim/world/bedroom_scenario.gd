class_name BedroomScenario
extends RefCounted
## Starting scenario of the first mission (decision 6): the player's bedroom with an old PC,
## the ISP router and a power strip, already cabled and running. Positions are world metres
## and match the room model (assets/models/rooms/room_bedroom.glb).

const FIRST_MISSION := "res://data/missions/first_server.tres"
const START_CREDITS := 1500
const PC_POSITION := Vector3(-0.30, 0.0, -1.22)
const ROUTER_POSITION := Vector3(1.45, 0.55, -1.30) ## On the small cabinet.
const STRIP_POSITION := Vector3(0.15, 0.0, -1.38) ## Under the desk.


static func create(catalog: Catalog = null) -> SimWorld:
	var world := SimWorld.new(catalog)
	world.credits = START_CREDITS
	world.room_bounds = Rect2(-1.75, -1.5, 3.5, 3.0)
	world.obstacles.assign([
		Rect2(-1.73, -1.485, 0.98, 2.04), # bed
		Rect2(-0.05, -1.47, 1.20, 0.60), # desk
		Rect2(1.18, -1.48, 0.54, 0.40), # cabinet
		Rect2(0.11, -0.92, 0.58, 0.60), # chair
	])
	world.delivery_point = Vector3(-1.30, 0.0, 1.02)

	var pc := world.create_device(&"pc_old", &"fixed")
	pc.position = PC_POSITION
	pc.power_switch_on = true
	var router := world.create_device(&"router_home", &"fixed")
	router.position = ROUTER_POSITION
	var strip := world.create_device(&"power_strip_4", &"fixed")
	strip.position = STRIP_POSITION

	_cable(world, &"cable_cat6_3m", PortRef.make(pc.id, &"lan", 0), PortRef.make(router.id, &"lan", 0))
	_cable(world, &"power_cord_3m", PortRef.make(pc.id, &"psu", 0), PortRef.make(strip.id, &"outlet", 0))
	_cable(world, &"power_cord_3m", PortRef.make(router.id, &"psu", 0), PortRef.make(strip.id, &"outlet", 1))

	var mission_def := load(FIRST_MISSION) as MissionDefinition
	if mission_def != null:
		world.mission = MissionTracker.new(mission_def)
	# Warm-up: the PC and the router boot and the PC gets its DHCP lease before the player starts.
	world.time_minutes = 8.0 * 60.0 - 3.0
	world.step_minutes(3.0)
	return world


static func _cable(world: SimWorld, item_id: StringName, a: String, b: String) -> void:
	var cable := world.create_device(item_id, &"inventory")
	var first := world.connect_cable(cable.id, a)
	var second := world.connect_cable(cable.id, b)
	if not first.ok or not second.ok:
		push_error("BedroomScenario: cannot cable %s: %s %s" % [item_id, first.message, second.message])
