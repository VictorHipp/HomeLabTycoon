class_name OverviewCameraRig
extends Node3D
## Third-person overview camera (docs/CAMERA_SYSTEM.md §3). Orbits a focus point with smooth,
## damped yaw / pitch / zoom and pans the focus inside the room.
## Mouse: drag with the RIGHT or MIDDLE button to rotate (horizontal) and tilt (vertical);
## wheel zooms. Keys (named actions): hold Q / E to rotate, W A S D to pan, F to recenter.
## Presentation only: it never touches the simulation.

signal recenter_requested

const DRAG_THRESHOLD_PX := 4.0

@export var camera: Camera3D
@export_group("Rotation")
@export var key_rotate_speed_deg: float = 100.0 ## Degrees per second while Q / E are held.
@export var drag_sensitivity_deg: float = 0.3 ## Degrees per pixel of mouse drag.
@export var invert_drag_x: bool = false
@export var invert_drag_y: bool = false
@export var pitch_min_deg: float = 25.0
@export var pitch_max_deg: float = 65.0
@export_group("Zoom")
@export var distance_min: float = 3.0
@export var distance_max: float = 12.0
@export var zoom_step: float = 0.88 ## Distance multiplier per wheel notch.
@export_group("Pan")
@export var pan_speed: float = 2.5 ## Metres per second at the reference distance (7.5 m).
@export var bounds: AABB = AABB(Vector3(-1.75, 0.0, -1.5), Vector3(3.5, 1.5, 3.0))
@export_group("Feel")
@export var smoothing: float = 10.0 ## Higher = snappier.

var active: bool = true
var target_yaw_deg: float = 37.4
var target_pitch_deg: float = 30.6
var target_distance: float = 7.46
var target_focus: Vector3 = Vector3(0.1, 0.5, -0.3)

var _yaw_deg: float
var _pitch_deg: float
var _distance: float
var _focus: Vector3
var _drag_button: int = MOUSE_BUTTON_NONE
var _drag_travel: float = 0.0
var _dragging: bool = false


func _ready() -> void:
	InputBindings.ensure_defaults()
	snap()


## Jump to the target values with no smoothing.
func snap() -> void:
	_yaw_deg = target_yaw_deg
	_pitch_deg = target_pitch_deg
	_distance = target_distance
	_focus = target_focus
	_apply()


func rotate_by(degrees: float) -> void:
	target_yaw_deg += degrees


func tilt_by(degrees: float) -> void:
	target_pitch_deg = clampf(target_pitch_deg + degrees, pitch_min_deg, pitch_max_deg)


func zoom_by(factor: float) -> void:
	target_distance = clampf(target_distance * factor, distance_min, distance_max)


## Pan in camera-relative horizontal metres: x = right, y = forward.
func pan_by(amount: Vector2) -> void:
	var yaw := deg_to_rad(target_yaw_deg)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	set_focus(target_focus + right * amount.x + forward * amount.y)


func set_focus(point: Vector3) -> void:
	target_focus = Vector3(
		clampf(point.x, bounds.position.x, bounds.end.x),
		clampf(point.y, bounds.position.y, bounds.end.y),
		clampf(point.z, bounds.position.z, bounds.end.z))


## Camera transform for the current (smoothed) values.
func current_pose() -> Transform3D:
	return pose_for(_focus, _yaw_deg, _pitch_deg, _distance)


static func pose_for(focus: Vector3, yaw_deg: float, pitch_deg: float, dist: float) -> Transform3D:
	var offset := Basis.from_euler(Vector3(deg_to_rad(-pitch_deg), deg_to_rad(yaw_deg), 0.0)) * Vector3(0.0, 0.0, dist)
	var origin := focus + offset
	return Transform3D(Basis.looking_at(focus - origin, Vector3.UP), origin)


## Advance the smoothing by `delta` seconds and move the camera.
func step(delta: float) -> void:
	var t := 1.0 - exp(-smoothing * delta)
	_yaw_deg = lerpf(_yaw_deg, target_yaw_deg, t)
	_pitch_deg = lerpf(_pitch_deg, target_pitch_deg, t)
	_distance = lerpf(_distance, target_distance, t)
	_focus = _focus.lerp(target_focus, t)
	_apply()


func is_dragging() -> bool:
	return _dragging


func _process(delta: float) -> void:
	if not active:
		return
	var turn := Input.get_axis(&"camera_rotate_left", &"camera_rotate_right")
	if turn != 0.0:
		rotate_by(turn * key_rotate_speed_deg * delta)
	var pan := Vector2(Input.get_axis(&"camera_pan_left", &"camera_pan_right"),
		Input.get_axis(&"camera_pan_back", &"camera_pan_forward"))
	if pan != Vector2.ZERO:
		pan_by(pan * pan_speed * delta * (target_distance / 7.5))
	step(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	var button := event as InputEventMouseButton
	if button != null:
		if button.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if button.pressed:
				_drag_button = button.button_index
				_drag_travel = 0.0
				_dragging = false
			elif button.button_index == _drag_button:
				if _dragging:
					get_viewport().set_input_as_handled()
				_drag_button = MOUSE_BUTTON_NONE
				_dragging = false
			return
		if button.pressed and event.is_action(&"camera_zoom_in"):
			zoom_by(zoom_step)
			get_viewport().set_input_as_handled()
		elif button.pressed and event.is_action(&"camera_zoom_out"):
			zoom_by(1.0 / zoom_step)
			get_viewport().set_input_as_handled()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _drag_button != MOUSE_BUTTON_NONE:
		_drag_travel += motion.relative.length()
		if _drag_travel > DRAG_THRESHOLD_PX:
			_dragging = true
		if _dragging:
			# "Grab the world": dragging right turns the room to the right.
			rotate_by(-motion.relative.x * drag_sensitivity_deg * (-1.0 if invert_drag_x else 1.0))
			tilt_by(motion.relative.y * drag_sensitivity_deg * (-1.0 if invert_drag_y else 1.0))
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"camera_recenter"):
		recenter_requested.emit()


func _apply() -> void:
	if camera != null:
		camera.global_transform = current_pose()
