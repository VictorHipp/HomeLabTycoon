extends Node3D
## Development showcase of the first low-poly models (visual spike, Hito 1).
## NOT the game camera system (that is CameraDirector, docs/CAMERA_SYSTEM.md); this dev tool
## reads keys directly, which game code must not do (docs/ARCHITECTURE.md §10).
##
## Controls: 1-5 switch view · on the overview: Q/E or ←/→ orbit, mouse wheel zoom · Esc quits.
## The scale mannequin is only shown on the overview (it is not the final character).
## Capture mode (tools/capture_showcase.ps1):
##   godot_console --path . --resolution 1600x900 res://game/showcase/model_showcase.tscn -- --capture=<dir>

## view -> [camera position, look-at target, fov, show mannequin]
const VIEWS := {
	&"overview": [Vector3(4.0, 4.3, 4.8), Vector3(0.1, 0.5, -0.3), 42.0, true],
	&"rack": [Vector3(1.62, 0.80, 1.05), Vector3(1.20, 0.36, 0.0), 38.0, false],
	&"rack_rear": [Vector3(1.12, 0.40, -0.98), Vector3(1.22, 0.29, -0.50), 50.0, false],
	&"desk": [Vector3(1.05, 1.50, 0.55), Vector3(0.35, 0.90, -1.25), 45.0, false],
	&"room": [Vector3(-1.35, 1.7, 1.25), Vector3(0.75, 0.6, -0.75), 55.0, false],
}
const VIEW_ORDER: Array[StringName] = [&"overview", &"rack", &"rack_rear", &"desk", &"room"]
const ORBIT_STEP_DEG := 15.0
const SETTLE_FRAMES := 30

@onready var _camera: Camera3D = $Camera3D
@onready var _mannequin: Node3D = $Mannequin

var _view_index: int = 0
var _orbit_yaw: float = 0.0
var _orbit_zoom: float = 1.0
var _walls: Array[Dictionary] = []


func _ready() -> void:
	get_viewport().msaa_3d = Viewport.MSAA_4X
	_walls = RoomView.find_walls(self) # same wall cutaway as the game
	_apply_view(0)
	var capture_dir := _capture_dir()
	if capture_dir != "":
		_capture_all(capture_dir)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				_apply_view(key.keycode - KEY_1)
			KEY_Q, KEY_LEFT:
				_orbit(-ORBIT_STEP_DEG)
			KEY_E, KEY_RIGHT:
				_orbit(ORBIT_STEP_DEG)
			KEY_ESCAPE:
				get_tree().quit()
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and _view_index == 0:
		if mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit_zoom = clampf(_orbit_zoom * 0.9, 0.4, 1.6)
			_apply_view(0)
		elif mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit_zoom = clampf(_orbit_zoom / 0.9, 0.4, 1.6)
			_apply_view(0)


func _orbit(degrees: float) -> void:
	_orbit_yaw += deg_to_rad(degrees)
	_apply_view(0)


func _apply_view(index: int) -> void:
	_view_index = index
	var spec: Array = VIEWS[VIEW_ORDER[index]]
	var pos: Vector3 = spec[0]
	var target: Vector3 = spec[1]
	if index == 0:
		pos = target + (pos - target).rotated(Vector3.UP, _orbit_yaw) * _orbit_zoom
	_camera.fov = spec[2]
	_camera.look_at_from_position(pos, target)
	_mannequin.visible = spec[3]
	RoomView.apply_cutaway(_walls, pos)


func _capture_dir() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			return arg.trim_prefix("--capture=")
	return ""


func _capture_all(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for i: int in VIEW_ORDER.size():
		_apply_view(i)
		for _frame: int in SETTLE_FRAMES:   # let shaders compile and SSAO / glow settle
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var path := dir.path_join("showcase_%s.png" % VIEW_ORDER[i])
		var err := image.save_png(path)
		print("CAPTURE %s -> %s (%s)" % [VIEW_ORDER[i], path, error_string(err)])
	get_tree().quit()
