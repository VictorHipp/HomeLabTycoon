class_name RoomView
extends Node3D
## The bedroom: shell, furniture, colliders, navigation mesh and wall cutaway
## (docs/CAMERA_SYSTEM.md §3.3–§4). Devices and packages are added under `objects`
## so the navigation bake sees them as obstacles. The furniture comes from the simulation
## (SimWorld.furniture) and follows it when the player moves a piece (sync_furniture).

const ROOM_MODEL := "res://assets/models/rooms/room_bedroom.glb"
const ROOM_SIZE := Vector2(3.5, 3.0)
const WALL_HEIGHT := 2.6
const WALL_THICKNESS := 0.1
const SKIRTING_HEIGHT := 0.08 ## Skirting boards of the room model (build_prototype_models.py).
const CUT_THRESHOLD := 0.25
## Roles of furniture parts that get colliders like the furniture itself (the monitor and the
## keyboard are the PC's: GameSession makes them open the computer).
const SOLID_PARTS: PackedStringArray = ["chair"]

var nav_region: NavigationRegion3D
var chair: Node3D ## The swivel chair at the desk (turns when the character sits down).
var objects: Node3D ## Parent for device and package views (inside the navigation region).
## furniture id -> {"root": Node3D (main model), "parts": {role -> Node3D wrapper}}
var pieces: Dictionary = {}
var _chair_piece: StringName = &""
var _chair_part_yaw: float = 0.0
var _walls: Array[Dictionary] = [] ## {"full": Node3D, "cut": Node3D, "normal": Vector3}
var _bake_pending: bool = false


func build(world: SimWorld) -> void:
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
	# Skirting boards (in the model, 8 cm high): solid too, so nothing can be dropped or drawn
	# through them. The left one stops at the door.
	var t := BedroomScenario.SKIRTING_M
	var door := BedroomScenario.DOOR_ZONE
	var sx := ROOM_SIZE.x / 2
	var sz := ROOM_SIZE.y / 2
	for box: AABB in [
			AABB(Vector3(-sx, 0, -sz), Vector3(ROOM_SIZE.x, SKIRTING_HEIGHT, t)),
			AABB(Vector3(-sx, 0, sz - t), Vector3(ROOM_SIZE.x, SKIRTING_HEIGHT, t)),
			AABB(Vector3(sx - t, 0, -sz), Vector3(t, SKIRTING_HEIGHT, ROOM_SIZE.y)),
			AABB(Vector3(-sx, 0, -sz), Vector3(t, SKIRTING_HEIGHT, door.position.y + sz)),
			AABB(Vector3(-sx, 0, door.end.y), Vector3(t, SKIRTING_HEIGHT, sz - door.end.y))]:
		if box.size.z > 0.0:
			ModelUtil.add_box_body(nav_region, box, Layers.WALLS).name = "Skirting"

	var ids: Array = world.furniture.keys()
	ids.sort()
	for furniture_id: StringName in ids:
		_build_piece(world.furniture[furniture_id] as SimFurniture)
	sync_furniture(world)

	_walls = find_walls(room)
	request_bake()


## Puts every piece of furniture (and its parts) where the simulation says. The chair goes back
## to facing its desk. Re-bakes the navigation when something moved.
func sync_furniture(world: SimWorld) -> void:
	var moved := false
	for furniture_id: StringName in pieces:
		var piece := world.get_furniture(furniture_id)
		var nodes: Dictionary = pieces[furniture_id]
		var root := nodes["root"] as Node3D
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(piece.yaw_degrees)), piece.position)
		if not root.transform.is_equal_approx(xf):
			moved = true
		root.transform = xf
		for part: Dictionary in piece.definition.parts:
			var node := (nodes["parts"] as Dictionary)[String(part["role"])] as Node3D
			node.transform = xf * Transform3D(Basis(Vector3.UP, deg_to_rad(float(part["yaw"]))), part["offset"] as Vector3)
	if moved:
		request_bake()


## Yaw (radians) at which the desk chair faces its desk.
func chair_rest_yaw() -> float:
	var root := (pieces[_chair_piece] as Dictionary)["root"] as Node3D if pieces.has(_chair_piece) else null
	return (root.rotation.y if root != null else 0.0) + deg_to_rad(_chair_part_yaw)


## The main model and parts of a piece (to hide them while the player moves it).
func piece_nodes(furniture_id: StringName) -> Array[Node3D]:
	var result: Array[Node3D] = []
	if not pieces.has(furniture_id):
		return result
	var nodes: Dictionary = pieces[furniture_id]
	result.append(nodes["root"] as Node3D)
	for node: Node3D in (nodes["parts"] as Dictionary).values():
		result.append(node)
	return result


## A part of a piece of furniture (e.g. the desk's "monitor"), or null.
func part(furniture_id: StringName, role: String) -> Node3D:
	if not pieces.has(furniture_id):
		return null
	return ((pieces[furniture_id] as Dictionary)["parts"] as Dictionary).get(role) as Node3D


func _build_piece(piece: SimFurniture) -> void:
	var def := piece.definition
	var solid := not def.blocks.is_empty()
	var root := ModelUtil.instance_model(def.model_path)
	root.name = "Furniture_%s" % piece.id
	nav_region.add_child(root)
	if solid:
		_make_solid(root, piece.id)
	var parts := {}
	for spec: Dictionary in def.parts:
		var role := String(spec["role"])
		# A wrapper per part: the model keeps its own import transform under it.
		var wrapper := Node3D.new()
		wrapper.name = "%s_%s" % [piece.id, role]
		var model := ModelUtil.instance_model(String(spec["model"]))
		wrapper.add_child(model)
		nav_region.add_child(wrapper)
		if role in SOLID_PARTS:
			_make_solid(model, piece.id)
		if role == "chair":
			chair = wrapper
			_chair_piece = piece.id
			_chair_part_yaw = float(spec["yaw"])
		parts[role] = wrapper
	pieces[piece.id] = {"root": root, "parts": parts}


## Solid parts (character, cables, clicks) and the whole footprint for the navigation bake.
## Their colliders say which piece they belong to (right click moves it).
func _make_solid(model: Node3D, furniture_id: StringName) -> void:
	ModelUtil.add_part_bodies(model, Layers.FURNITURE).set_meta("furniture_id", furniture_id)
	ModelUtil.add_box_body(model, ModelUtil.local_aabb(model), Layers.NAV_BLOCK).set_meta("furniture_id", furniture_id)


## Show the low version of the walls between the camera and the room (decision 15).
func update_cutaway(camera_position: Vector3) -> void:
	apply_cutaway(_walls, camera_position)


## The full and cut variants of each wall of a room model (WALL_<side> / WALL_<side>_cut).
static func find_walls(room: Node) -> Array[Dictionary]:
	var walls: Array[Dictionary] = []
	for side: Array in [["back", Vector3(0, 0, -1)], ["front", Vector3(0, 0, 1)],
			["left", Vector3(-1, 0, 0)], ["right", Vector3(1, 0, 0)]]:
		var full := room.find_child("WALL_%s" % side[0], true, false) as Node3D
		var cut := room.find_child("WALL_%s_cut" % side[0], true, false) as Node3D
		if full != null and cut != null:
			walls.append({"full": full, "cut": cut, "normal": side[1]})
	return walls


## Walls whose outer side faces the camera show their cut variant; the others, the full one.
static func apply_cutaway(walls: Array[Dictionary], camera_position: Vector3) -> void:
	var dir := Vector3(camera_position.x, 0.0, camera_position.z)
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	for wall: Dictionary in walls:
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
