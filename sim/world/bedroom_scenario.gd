class_name BedroomScenario
extends RefCounted
## Starting scenario of the first mission (decision 6): the player's bedroom with an old PC,
## the ISP router and a power strip, already cabled and running. Positions are world metres
## and match the room model (assets/models/rooms/room_bedroom.glb).

const FIRST_MISSION := "res://data/missions/first_server.tres"
## Enough for the mission kit (rack, switch, server, two network cables: 808) with a small margin
## for mistakes (docs/PROGRESSION.md §9: "poco margen").
const START_CREDITS := 1000
const PC_POSITION := Vector3(-0.30, 0.0, -1.22)
const ROUTER_POSITION := Vector3(1.45, 0.55, -1.30) ## On the small cabinet.
const ROUTER_YAW := 180.0 ## Rear ports face the room (not the wall or the desk) so they can be reached.
const STRIP_POSITION := Vector3(-0.30, 0.0, -0.85) ## On the floor in front of the PC tower.
## Inside the entrance, against the front wall and right of the door (door: left wall,
## z 0.62..1.42). Clear of the door swing and of the way into the room.
const DELIVERY_ZONE := Rect2(-0.95, 0.95, 0.60, 0.50)
## Floor the door needs (left wall, z 0.62..1.42, 0.80 m wide): no object and no cable there.
const DOOR_ZONE := Rect2(-1.75, 0.57, 0.80, 0.90)
const SKIRTING_M := 0.015 ## Skirting boards of the room model (build_prototype_models.py).
## Starting layout: [instance id, definition, origin, yaw degrees]. The player can move every
## piece (SimWorld.move_furniture); the desk takes the chair, the PC and the strip with it and
## the cabinet takes the router standing on it.
const FURNITURE := [
	[&"bed", "res://data/furniture/bed_single.tres", Vector3(-1.24, 0.0, -0.465), 0.0],
	[&"desk", "res://data/furniture/desk_basic.tres", Vector3(0.55, 0.0, -1.17), 0.0],
	[&"cabinet", "res://data/furniture/cabinet_small.tres", Vector3(1.45, 0.0, -1.28), 0.0],
	[&"rug", "res://data/furniture/rug_basic.tres", Vector3(0.25, 0.0, 0.35), 0.0],
]
## What goes with which piece at the start (catalog id -> furniture instance id).
const CARRIED := {&"pc_old": &"desk", &"power_strip_4": &"desk", &"router_home": &"cabinet"}


## A new game.
static func create(catalog: Catalog = null) -> SimWorld:
	var world := new_room(catalog)
	world.grant_rewards(START_CREDITS, 0, &"start", world.tr("Ahorros con los que empiezas"))

	var pc := world.create_device(&"pc_old", &"fixed")
	pc.position = PC_POSITION
	pc.power_switch_on = true
	var router := world.create_device(&"router_home", &"fixed")
	router.position = ROUTER_POSITION
	router.yaw_degrees = ROUTER_YAW
	var strip := world.create_device(&"power_strip_4", &"fixed")
	strip.position = STRIP_POSITION
	_attach_house_devices(world)

	# Cables follow the floor (under the desk, behind the drawers): the router needs 5 m ones.
	_cable(world, &"cable_cat6_5m", PortRef.make(pc.id, &"lan", 0), PortRef.make(router.id, &"lan", 0))
	_cable(world, &"power_cord_3m", PortRef.make(pc.id, &"psu", 0), PortRef.make(strip.id, &"outlet", 0))
	_cable(world, &"power_cord_5m", PortRef.make(router.id, &"psu", 0), PortRef.make(strip.id, &"outlet", 1))

	var mission_def := load(FIRST_MISSION) as MissionDefinition
	if mission_def != null:
		world.mission = MissionTracker.new(mission_def)
	# Warm-up: the PC and the router boot and the PC gets its DHCP lease before the player starts.
	world.time_minutes = 8.0 * 60.0 - 3.0
	world.step_minutes(3.0)
	return world


## A saved game of this scenario: the room is rebuilt, the dynamic state comes from the save.
static func restore(state: Dictionary, catalog: Catalog = null) -> SimWorld:
	var world := new_room(catalog)
	world.load_state(state)
	if not state.has("furniture"):
		_attach_house_devices(world) # saves before version 3: the starting layout
	return world


## The house devices go with the furniture they stand on or belong to.
static func _attach_house_devices(world: SimWorld) -> void:
	for d: SimDevice in world.devices.values():
		if d.location == &"fixed" and CARRIED.has(d.definition.id):
			d.furniture_id = CARRIED[d.definition.id]


## The room alone: floor area and furniture (no devices).
static func new_room(catalog: Catalog = null) -> SimWorld:
	var world := SimWorld.new(catalog)
	world.room_bounds = Rect2(-1.75, -1.5, 3.5, 3.0)
	# Furniture footprints and what stands on the floor for a cable (bed frame, desk legs and
	# drawers, chair base, cabinet) come from data/furniture/ (measured on the models,
	# tests/integration/test_furniture.gd).
	for spec: Array in FURNITURE:
		world.add_furniture(spec[0], load(spec[1]) as FurnitureDefinition, spec[2], spec[3])
	world.delivery_zone = DELIVERY_ZONE
	world.door_zones.assign([DOOR_ZONE])
	world.wall_trim_m = SKIRTING_M
	return world


static func _cable(world: SimWorld, item_id: StringName, a: String, b: String) -> void:
	var cable := world.create_device(item_id, &"inventory")
	var first := world.connect_cable(cable.id, a)
	var second := world.connect_cable(cable.id, b)
	if not first.ok or not second.ok:
		push_error("BedroomScenario: cannot cable %s: %s %s" % [item_id, first.message, second.message])
