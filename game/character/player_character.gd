class_name PlayerCharacter
extends CharacterBody3D
## The player's character (docs/CAMERA_SYSTEM.md §4): walks with NavigationAgent3D to the
## clicked point. Uses the scale mannequin until the final character is modelled.

signal arrived
signal unreachable

const MODEL := "res://assets/models/characters/mannequin_scale.glb"
const SPEED := 1.6 ## m/s
const TURN_SPEED := 12.0
const MAX_SNAP_DISTANCE := 0.45 ## How far a click may be from the walkable area.

var agent: NavigationAgent3D
var model: Node3D
var moving: bool = false


func _ready() -> void:
	collision_layer = Layers.CHARACTER
	collision_mask = Layers.WALLS | Layers.FURNITURE | Layers.DEVICES
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.2
	capsule.height = 1.7
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.85, 0.0)
	add_child(shape)
	agent = NavigationAgent3D.new()
	agent.radius = 0.2
	agent.height = 1.6
	agent.path_desired_distance = 0.12
	agent.target_desired_distance = 0.12
	add_child(agent)
	model = ModelUtil.instance_model(MODEL)
	add_child(model)


## Walk to `point`. Returns false (and emits `unreachable`) if it is far from walkable floor.
func move_to(point: Vector3) -> bool:
	var map := get_world_3d().navigation_map
	var closest := NavigationServer3D.map_get_closest_point(map, point)
	if Vector2(closest.x - point.x, closest.z - point.z).length() > MAX_SNAP_DISTANCE:
		unreachable.emit()
		return false
	# Ask the navigation server directly (the agent's own flag lags behind map re-bakes).
	var path := NavigationServer3D.map_get_path(map, global_position, closest, true)
	if path.is_empty() or Vector2(path[path.size() - 1].x - closest.x, path[path.size() - 1].z - closest.z).length() > 0.25:
		unreachable.emit()
		return false
	agent.target_position = closest
	moving = true
	return true


func stop() -> void:
	moving = false
	velocity = Vector3.ZERO


func face_towards(point: Vector3) -> void:
	var dir := point - global_position
	if Vector2(dir.x, dir.z).length() > 0.01:
		model.rotation.y = atan2(dir.x, dir.z)


## Where the character should appear when this game is loaded (a free spot on the floor).
func save_position() -> Vector3:
	return global_position


func set_model_visible(value: bool) -> void:
	model.visible = value


func _physics_process(delta: float) -> void:
	if not moving:
		return
	if agent.is_navigation_finished():
		stop()
		arrived.emit()
		return
	var next := agent.get_next_path_position()
	var dir := next - global_position
	dir.y = 0.0
	if dir.length() < 0.005:
		return
	velocity = dir.normalized() * SPEED
	move_and_slide()
	global_position.y = 0.0
	model.rotation.y = lerp_angle(model.rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-TURN_SPEED * delta))
