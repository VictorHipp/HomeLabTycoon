class_name PlayerCharacter
extends CharacterBody3D
## The player's character (docs/CAMERA_SYSTEM.md §4): walks with NavigationAgent3D to the
## clicked point using move_and_slide (it collides with walls, furniture parts and devices),
## accelerates and slows down smoothly, and stops with a warning if something blocks it.
## The articulated mannequin is animated procedurally from the distance really travelled
## (CharacterAnimator). It can sit on the swivel chair and stand up again.

signal arrived
signal unreachable
signal blocked ## Stopped because it could not advance (something in the way).

const MODEL := "res://assets/models/characters/mannequin_scale.glb"
const SPEED := 1.4 ## m/s
const ACCEL := 5.0 ## m/s²
const SLOW_DOWN_DISTANCE := 0.35 ## starts braking this far from the destination
const TURN_SPEED := 10.0
const MAX_SNAP_DISTANCE := 0.45 ## How far a click may be from the walkable area.
const CAPSULE_RADIUS := 0.17 ## Thinner than the navigation agent (0.2): paths never scrape corners.
const STUCK_TIME := 0.8
const STUCK_DISTANCE := 0.05
const SIT_TURN_TIME := 0.3
const SIT_MOVE_TIME := 0.55
const SWIVEL_TIME := 0.45
const TRANSITION_TIMEOUT := 4.0 ## A sit / stand transition can never last longer than this.

var agent: NavigationAgent3D
var model: Node3D
var animator: CharacterAnimator
var moving: bool = false
var seated: bool = false
var busy: bool = false ## Sitting down or standing up.

var _shape: CollisionShape3D
var _speed: float = 0.0
var _measured_speed: float = 0.0
var _stuck_timer: float = 0.0
var _stuck_origin: Vector3 = Vector3.ZERO
var _stand_spot: Vector3 = Vector3.ZERO ## Where it stood before sitting (a free spot).


func _ready() -> void:
	collision_layer = Layers.CHARACTER
	collision_mask = Layers.WALLS | Layers.FURNITURE | Layers.DEVICES
	_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = CAPSULE_RADIUS
	capsule.height = 1.7
	_shape.shape = capsule
	_shape.position = Vector3(0.0, 0.85, 0.0)
	add_child(_shape)
	agent = NavigationAgent3D.new()
	agent.radius = 0.2
	agent.height = 1.6
	agent.path_desired_distance = 0.12
	agent.target_desired_distance = 0.12
	add_child(agent)
	model = ModelUtil.instance_model(MODEL)
	add_child(model)
	animator = CharacterAnimator.new()
	animator.setup(model)


## Walk to `point`. Returns false (and emits `unreachable`) if it cannot get there.
func move_to(point: Vector3) -> bool:
	if busy or seated:
		return false
	var closest := reachable_point(point)
	if closest == Vector3.INF:
		unreachable.emit()
		return false
	agent.target_position = closest
	moving = true
	_stuck_timer = 0.0
	_stuck_origin = global_position
	return true


## The walkable point next to `point` if a path leads there from here, else Vector3.INF.
func reachable_point(point: Vector3) -> Vector3:
	var map := get_world_3d().navigation_map
	var closest := NavigationServer3D.map_get_closest_point(map, point)
	if Vector2(closest.x - point.x, closest.z - point.z).length() > MAX_SNAP_DISTANCE:
		return Vector3.INF
	# Ask the navigation server directly (the agent's own flag lags behind map re-bakes).
	var path := NavigationServer3D.map_get_path(map, global_position, closest, true)
	if path.is_empty() or Vector2(path[path.size() - 1].x - closest.x, path[path.size() - 1].z - closest.z).length() > 0.25:
		return Vector3.INF
	return closest


## Length of the walk to `point` (INF if it cannot get there).
func path_length_to(point: Vector3) -> float:
	var target := reachable_point(point)
	if target == Vector3.INF:
		return INF
	var path := NavigationServer3D.map_get_path(get_world_3d().navigation_map, global_position, target, true)
	var total := 0.0
	for i: int in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


func stop() -> void:
	moving = false
	velocity = Vector3.ZERO


func face_towards(point: Vector3) -> void:
	var dir := point - global_position
	if Vector2(dir.x, dir.z).length() > 0.01:
		model.rotation.y = atan2(dir.x, dir.z)


func set_model_visible(value: bool) -> void:
	model.visible = value


## Where the character should appear when this game is loaded: never inside the chair.
func save_position() -> Vector3:
	return _stand_spot if (seated or busy) else global_position


func _physics_process(delta: float) -> void:
	var before := global_position
	if moving and not busy:
		_walk(delta)
	else:
		_speed = 0.0
	var moved := 0.0 if busy else Vector2(global_position.x - before.x, global_position.z - before.z).length()
	if delta > 0.0:
		_measured_speed = lerpf(_measured_speed, moved / delta, 1.0 - exp(-12.0 * delta))
	animator.update(delta, moved, _measured_speed)


func _walk(delta: float) -> void:
	if agent.is_navigation_finished():
		stop()
		arrived.emit()
		return
	var next := agent.get_next_path_position()
	var dir := next - global_position
	dir.y = 0.0
	var remaining := agent.distance_to_target()
	var target_speed := SPEED if remaining > SLOW_DOWN_DISTANCE else maxf(0.45, SPEED * remaining / SLOW_DOWN_DISTANCE)
	_speed = move_toward(_speed, target_speed, ACCEL * delta)
	if dir.length() > 0.005:
		velocity = dir.normalized() * _speed
		move_and_slide()
		global_position.y = 0.0
		model.rotation.y = lerp_angle(model.rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-TURN_SPEED * delta))
	_stuck_timer += delta
	if _stuck_timer >= STUCK_TIME:
		if global_position.distance_to(_stuck_origin) < STUCK_DISTANCE:
			stop()
			blocked.emit()
		_stuck_timer = 0.0
		_stuck_origin = global_position


# --------------------------------------------------------------- sitting --

## From the current spot (next to the chair): the chair turns towards the character, the
## character turns its back to the seat and sits down, and the chair turns back to `facing_yaw`.
## The capsule is off while seated (the body is on the chair). Returns when seated.
func sit_down(chair: Node3D, facing_yaw: float) -> void:
	if seated or busy:
		return
	stop()
	busy = true
	_stand_spot = global_position
	_shape.disabled = true
	var seat := Vector3(chair.global_position.x, 0.0, chair.global_position.z)
	var spot := global_position
	var towards_spot := atan2(spot.x - seat.x, spot.z - seat.z)
	var start_facing := model.rotation.y
	var chair_start := chair.rotation.y
	await _animate(SIT_TURN_TIME, func(t: float) -> void:
		model.rotation.y = lerp_angle(start_facing, towards_spot, t)
		chair.rotation.y = lerp_angle(chair_start, towards_spot, t))
	await _animate(SIT_MOVE_TIME, func(t: float) -> void:
		var e := smoothstep(0.0, 1.0, t)
		global_position = spot.lerp(seat, e)
		animator.sit_weight = e)
	await _animate(SWIVEL_TIME, func(t: float) -> void:
		var yaw := lerp_angle(towards_spot, facing_yaw, smoothstep(0.0, 1.0, t))
		chair.rotation.y = yaw
		model.rotation.y = yaw)
	seated = true
	busy = false


## Turns towards the first free spot, stands up and steps there; the capsule comes back only
## on a spot checked to be free. Never leaves the character inside the chair.
func stand_up(chair: Node3D, spots: Array[Vector3], chair_rest_yaw: float) -> void:
	if not seated or busy:
		return
	busy = true
	var seat := Vector3(chair.global_position.x, 0.0, chair.global_position.z)
	var candidates: Array[Vector3] = [_stand_spot]
	candidates.append_array(spots)
	var target := _free_spot(candidates)
	var towards := atan2(target.x - seat.x, target.z - seat.z)
	var chair_start := chair.rotation.y
	await _animate(SWIVEL_TIME, func(t: float) -> void:
		var yaw := lerp_angle(chair_start, towards, smoothstep(0.0, 1.0, t))
		chair.rotation.y = yaw
		model.rotation.y = yaw)
	await _animate(SIT_MOVE_TIME, func(t: float) -> void:
		var e := smoothstep(0.0, 1.0, t)
		global_position = seat.lerp(target, e)
		animator.sit_weight = 1.0 - e)
	await _animate(SIT_TURN_TIME, func(t: float) -> void:
		chair.rotation.y = lerp_angle(towards, chair_rest_yaw, t))
	animator.sit_weight = 0.0
	global_position = target
	_shape.disabled = false
	seated = false
	busy = false


## The first spot where the standing capsule fits and that is on walkable floor; if none, the
## walkable point closest to the first one (so the character always ends on the floor).
func _free_spot(spots: Array[Vector3]) -> Vector3:
	var map := get_world_3d().navigation_map
	for spot: Vector3 in spots:
		var on_floor := NavigationServer3D.map_get_closest_point(map, spot)
		if Vector2(on_floor.x - spot.x, on_floor.z - spot.z).length() < 0.1 and capsule_fits(spot):
			return Vector3(spot.x, 0.0, spot.z)
	var fallback := NavigationServer3D.map_get_closest_point(map, spots[0])
	return Vector3(fallback.x, 0.0, fallback.z)


## True if the standing capsule at `spot` touches no wall, furniture part or device.
func capsule_fits(spot: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape.shape
	query.transform = Transform3D(Basis.IDENTITY, Vector3(spot.x, 0.85, spot.z))
	query.collision_mask = Layers.WALLS | Layers.FURNITURE | Layers.DEVICES
	var exclude: Array[RID] = [get_rid()]
	query.exclude = exclude
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## Runs `step(t)` for t in 0..1 over `duration` seconds (physics frames). Always ends, even if
## the game hangs a frame: t is clamped and the loop has a hard time limit.
func _animate(duration: float, step: Callable) -> void:
	var elapsed := 0.0
	var limit := minf(duration * 3.0, TRANSITION_TIMEOUT)
	while elapsed < duration and elapsed < limit:
		step.call(clampf(elapsed / duration, 0.0, 1.0))
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	step.call(1.0)
