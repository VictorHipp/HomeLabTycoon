class_name RoomView
extends Node3D
## The bedroom: shell, furniture, colliders, navigation mesh and wall cutaway
## (docs/CAMERA_SYSTEM.md §3.3–§4). Devices and packages are added under `objects`
## so the navigation bake sees them as obstacles.

const ROOM_MODEL := "res://assets/models/rooms/room_bedroom.glb"
const ROOM_SIZE := Vector2(3.5, 3.0)
const WALL_HEIGHT := 2.6
const WALL_THICKNESS := 0.1
## [model, position, yaw degrees, blocks walking]
const FURNITURE := [
	["res://assets/models/furniture/bed_single.glb", Vector3(-1.24, 0.0, -0.465), 0.0, true],
	["res://assets/models/furniture/desk_basic.glb", Vector3(0.55, 0.0, -1.17), 0.0, true],
	["res://assets/models/furniture/chair_office.glb", Vector3(0.40, 0.0, -0.62), 180.0, true],
	["res://assets/models/furniture/cabinet_small.glb", Vector3(1.45, 0.0, -1.28), 0.0, true],
	["res://assets/models/furniture/rug_basic.glb", Vector3(0.25, 0.0, 0.35), 0.0, false],
]
const CUT_THRESHOLD := 0.25

var nav_region: NavigationRegion3D
var objects: Node3D ## Parent for device and package views (inside the navigation region).
var _walls: Array[Dictionary] = [] ## {"full": Node3D, "cut": Node3D, "normal": Vector3}
var _bake_pending: bool = false


func build() -> void:
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Navigation"
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = Layers.NAV_OBSTACLES
	mesh.cell_size = 0.05
	mesh.cell_height = 0.05
	mesh.agent_radius = 0.2 ## Multiple of cell_size (avoids precision loss).
	mesh.agent_height = 1.6
	mesh.agent_max_climb = 0.05
	# Only floor level: furniture tops never become walkable islands.
	mesh.filter_baking_aabb = AABB(Vector3(-1.8, -0.3, -1.6), Vector3(3.6, 0.6, 3.2))
	nav_region.navigation_mesh = mesh
	add_child(nav_region)
	objects = Node3D.new()
	objects.name = "Objects"
	nav_region.add_child(objects)

	var room := ModelUtil.instance_model(ROOM_MODEL)
	room.name = "RoomModel"
	nav_region.add_child(room)
	var floor_box := AABB(Vector3(-ROOM_SIZE.x / 2, -0.1, -ROOM_SIZE.y / 2), Vector3(ROOM_SIZE.x, 0.1, ROOM_SIZE.y))
	ModelUtil.add_box_body(nav_region, floor_box, Layers.FLOOR).name = "FloorBody"
	var hx := ROOM_SIZE.x / 2 + WALL_THICKNESS / 2
	var hz := ROOM_SIZE.y / 2 + WALL_THICKNESS / 2
	for spec: Array in [
			[Vector3(0, WALL_HEIGHT / 2, -hz), Vector3(ROOM_SIZE.x + 0.2, WALL_HEIGHT, WALL_THICKNESS)],
			[Vector3(0, WALL_HEIGHT / 2, hz), Vector3(ROOM_SIZE.x + 0.2, WALL_HEIGHT, WALL_THICKNESS)],
			[Vector3(-hx, WALL_HEIGHT / 2, 0), Vector3(WALL_THICKNESS, WALL_HEIGHT, ROOM_SIZE.y)],
			[Vector3(hx, WALL_HEIGHT / 2, 0), Vector3(WALL_THICKNESS, WALL_HEIGHT, ROOM_SIZE.y)]]:
		ModelUtil.add_box_body(nav_region, AABB(spec[0] - spec[1] / 2, spec[1]), Layers.WALLS)

	for spec: Array in FURNITURE:
		var piece := ModelUtil.instance_model(spec[0])
		piece.position = spec[1]
		piece.rotation_degrees.y = spec[2]
		nav_region.add_child(piece)
		if spec[3]:
			ModelUtil.add_box_body(piece, ModelUtil.local_aabb(piece), Layers.FURNITURE)

	for side: Array in [["back", Vector3(0, 0, -1)], ["front", Vector3(0, 0, 1)],
			["left", Vector3(-1, 0, 0)], ["right", Vector3(1, 0, 0)]]:
		var full := room.find_child("WALL_%s" % side[0], true, false) as Node3D
		var cut := room.find_child("WALL_%s_cut" % side[0], true, false) as Node3D
		if full != null and cut != null:
			_walls.append({"full": full, "cut": cut, "normal": side[1]})
	request_bake()


## Show the low version of the walls between the camera and the room (decision 15).
func update_cutaway(camera_position: Vector3) -> void:
	var dir := Vector3(camera_position.x, 0.0, camera_position.z)
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	for wall: Dictionary in _walls:
		var cut_mode := dir.dot(wall["normal"]) > CUT_THRESHOLD
		(wall["full"] as Node3D).visible = not cut_mode
		(wall["cut"] as Node3D).visible = cut_mode


## Re-bake the navigation mesh at the end of the frame (several changes -> one bake).
func request_bake() -> void:
	if _bake_pending:
		return
	_bake_pending = true
	_bake.call_deferred()


func _bake() -> void:
	_bake_pending = false
	if nav_region.is_baking():
		nav_region.bake_finished.connect(request_bake, CONNECT_ONE_SHOT)
		return
	nav_region.bake_navigation_mesh(true)
