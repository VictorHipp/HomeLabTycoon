class_name CameraDirector
extends Node
## Smooth transitions between the overview rig and close-up anchors (docs/CAMERA_SYSTEM.md §5):
## the camera passes over the character's shoulder and ends on the anchor at eye level.
## The single Camera3D is shared; the rig is paused while a close-up is active.

signal transition_finished

const DURATION_IN := 0.8
const DURATION_OUT := 0.65

var camera: Camera3D
var rig: OverviewCameraRig
var busy: bool = false
var in_closeup: bool = false
var reduce_motion: bool = false

var _from: Transform3D
var _via: Vector3
var _to: Transform3D
var _fov_from: float
var _fov_to: float
var _tween: Tween


func setup(cam: Camera3D, overview_rig: OverviewCameraRig) -> void:
	camera = cam
	rig = overview_rig


## Fly to `anchor` (camera transform; it looks along its -Z), passing near `over_point`.
func focus_on(anchor: Transform3D, over_point: Vector3, fov: float = 50.0) -> void:
	rig.active = false
	in_closeup = true
	var shoulder := over_point + Vector3(0.0, 0.5, 0.0) + (over_point - anchor.origin).normalized() * 0.4
	_play(camera.global_transform, shoulder, anchor, camera.fov, fov, DURATION_IN)


## Change to another anchor while in close-up (e.g. rack front <-> rear).
func switch_anchor(anchor: Transform3D, fov: float = 50.0) -> void:
	var mid := (camera.global_position + anchor.origin) * 0.5 + Vector3(0.0, 0.4, 0.0)
	_play(camera.global_transform, mid, anchor, camera.fov, fov, 0.45)


func return_to_overview() -> void:
	in_closeup = false
	var target := rig.current_pose()
	var mid := (camera.global_position + target.origin) * 0.5 + Vector3(0.0, 0.6, 0.0)
	_play(camera.global_transform, mid, target, camera.fov, 42.0, DURATION_OUT)
	await transition_finished
	if not in_closeup:
		rig.active = true


## Finish the current transition immediately (click during a transition).
func skip() -> void:
	if _tween != null and _tween.is_running():
		_tween.custom_step(10.0)


func _play(from: Transform3D, via: Vector3, to: Transform3D, fov_from: float, fov_to: float, duration: float) -> void:
	if _tween != null:
		_tween.kill()
	_from = from
	_via = via
	_to = to
	_fov_from = fov_from
	_fov_to = fov_to
	busy = true
	if reduce_motion:
		_blend(1.0)
		_finish()
		return
	_tween = create_tween()
	_tween.tween_method(_blend, 0.0, 1.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.finished.connect(_finish)


func _blend(t: float) -> void:
	# Quadratic Bézier for the position, quaternion slerp for the orientation.
	var a := _from.origin.lerp(_via, t)
	var b := _via.lerp(_to.origin, t)
	var origin := a.lerp(b, t)
	var basis := Basis(_from.basis.get_rotation_quaternion().slerp(_to.basis.get_rotation_quaternion(), t))
	camera.global_transform = Transform3D(basis, origin)
	camera.fov = lerpf(_fov_from, _fov_to, t)


func _finish() -> void:
	busy = false
	transition_finished.emit()
