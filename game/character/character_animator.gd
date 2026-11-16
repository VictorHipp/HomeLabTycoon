class_name CharacterAnimator
extends RefCounted
## Procedural animation of the articulated character (tools/blender: J_hip_*, J_knee_*, J_ankle_*,
## J_shoulder_*, J_elbow_*). No AnimationPlayer: the walk is driven by the distance really
## travelled (measured after move_and_slide), so the legs stop when the body stops (blocked
## against something) and the feet keep pace with the ground at any speed.
##
## Gait (per leg, u = position in the cycle 0..1, the other leg half a cycle later):
##   stance, u in [0, STANCE): the foot goes back relative to the body LINEARLY, exactly as fast
##     as the body goes forward (one cycle = CYCLE_M metres), so it stays planted on the floor;
##     the body goes down just enough to keep that foot at floor height;
##   swing, the rest: the foot travels forward in the air with the knee bent.
## Godot axes of the model: +Z forward, +Y up; a NEGATIVE rotation about +X swings a limb forward.

const LEG := 0.77 ## hip to ankle (straight leg): the ankle is the point that stays planted
const CYCLE_M := 1.2 ## metres per full gait cycle (two steps of 0.6 m)
const STANCE := 0.6 ## fraction of the cycle with the foot on the floor
const REACH := CYCLE_M * STANCE / 2.0 ## foot ahead of / behind the hip at the ends of the stance
const THIGH := 0.40 ## hip -> knee (model: 0.84 -> 0.44)
const SHIN := 0.37 ## knee -> ankle (model: 0.44 -> 0.07)
const LIFT := 0.09 ## how high the ankle rises at mid-swing
const ARM_SWING := 0.30 ## rad
const BLEND_RATE := 8.0 ## 1/s, idle <-> walk <-> sit
const WALK_SPEED_FULL := 0.6 ## m/s at which the walk is fully blended in

## Seated pose (hips over the seat, thighs horizontal, shins down, hands towards the keyboard).
const SIT_DROP := 0.84 - 0.53 ## how much the body goes down onto a 0.505 m seat
const SIT_HIP := -1.5359 # -88°
const SIT_KNEE := 1.5359 # 88°
const SIT_SHOULDER := -0.8378 # -48°
const SIT_ELBOW := -0.7330 # -42°

var phase: float = 0.0 ## 0..1
var walk_weight: float = 0.0
var sit_weight: float = 0.0 ## 0 standing, 1 seated (set by the character during transitions)

var _model: Node3D
var _base_y: float = 0.0
var _joints: Dictionary = {} ## name -> Node3D
var _rest: Dictionary = {} ## name -> Basis


func setup(model: Node3D) -> void:
	_model = model
	_base_y = model.position.y
	for joint: String in ["J_hip_L", "J_hip_R", "J_knee_L", "J_knee_R", "J_ankle_L", "J_ankle_R",
			"J_shoulder_L", "J_shoulder_R", "J_elbow_L", "J_elbow_R"]:
		var node := model.find_child(joint, true, false) as Node3D
		if node != null:
			_joints[joint] = node
			_rest[joint] = node.basis


func is_articulated() -> bool:
	return _joints.size() == 10


## `distance` = horizontal metres travelled this frame, `speed` = their rate (m/s).
func update(delta: float, distance: float, speed: float) -> void:
	var target_walk := clampf(speed / WALK_SPEED_FULL, 0.0, 1.0) * (1.0 - sit_weight)
	walk_weight = lerpf(walk_weight, target_walk, 1.0 - exp(-BLEND_RATE * delta))
	if distance > 0.0:
		phase = fposmod(phase + distance / CYCLE_M, 1.0)
	_pose()


## True while that foot is on the floor (for the no-sliding check of the walkthrough).
func in_stance(side: String) -> bool:
	return _leg_u(side) < STANCE


func _leg_u(side: String) -> float:
	return fposmod(phase + (0.0 if side == "L" else 0.5), 1.0)


## Ankle target relative to the hip: x = ahead of the hip along the walk (m), y = lift above the
## floor (m, only while the foot swings in the air).
static func _leg(u: float) -> Vector2:
	if u < STANCE:
		return Vector2(REACH - 2.0 * REACH * u / STANCE, 0.0)
	var s := (u - STANCE) / (1.0 - STANCE)
	return Vector2(-REACH + 2.0 * REACH * smoothstep(0.0, 1.0, s), LIFT * sin(PI * s))


## Two-bone inverse kinematics: hip and knee angles that put the ankle `x` ahead of the hip and
## `down` below it (knee bending backwards, like a real knee).
static func _ik(x: float, down: float) -> Vector2:
	var d := clampf(sqrt(x * x + down * down), 0.05, THIGH + SHIN - 0.0005)
	var knee := PI - acos(clampf((THIGH * THIGH + SHIN * SHIN - d * d) / (2.0 * THIGH * SHIN), -1.0, 1.0))
	var hip := -(atan2(x, down) + acos(clampf((THIGH * THIGH + d * d - SHIN * SHIN) / (2.0 * THIGH * d), -1.0, 1.0)))
	return Vector2(hip, knee)


func _pose() -> void:
	if not is_articulated():
		return
	var w := walk_weight
	var s := sit_weight
	var targets := {}
	var drop := 0.0
	for side: String in ["L", "R"]:
		var u := _leg_u(side)
		var leg := _leg(u) * w
		targets[side] = leg
		if u < STANCE:
			# The body goes down as much as the most stretched planted leg needs.
			drop = maxf(drop, LEG - sqrt(maxf(LEG * LEG - leg.x * leg.x, 0.0)))
	var down := LEG - drop
	for side: String in ["L", "R"]:
		var leg: Vector2 = targets[side]
		var angles := _ik(leg.x, down - leg.y) # planted feet exactly on the floor, the other lifted
		_bend("J_hip_" + side, lerpf(angles.x, SIT_HIP, s))
		_bend("J_knee_" + side, lerpf(angles.y, SIT_KNEE, s))
		_bend("J_ankle_" + side, lerpf(-(angles.x + angles.y) * 0.85, 0.0, s))
		var arm := ARM_SWING * (leg.x / REACH) # back while the leg on that side is forward
		_bend("J_shoulder_" + side, lerpf(arm, SIT_SHOULDER, s))
		_bend("J_elbow_" + side, lerpf(-0.15 * w - 0.2 * absf(arm), SIT_ELBOW, s))
	_model.position.y = _base_y - drop - SIT_DROP * s


func _bend(joint: String, angle: float) -> void:
	(_joints[joint] as Node3D).basis = (_rest[joint] as Basis) * Basis(Vector3.RIGHT, angle)


## World position of the ankle of a foot (for the no-sliding check).
func foot_position(side: String) -> Vector3:
	var ankle := _joints.get("J_ankle_" + side) as Node3D
	return ankle.global_position if ankle != null else Vector3.INF
