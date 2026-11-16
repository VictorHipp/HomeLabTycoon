class_name InputBindings
extends RefCounted
## Default bindings of the named input actions (docs/ARCHITECTURE.md §10). Game code reads
## actions, never raw keys, so controls can be remapped later. Actions already defined in the
## project settings (or by a future remapping screen) are left untouched.

const DEFAULTS := {
	&"camera_rotate_left": [[&"key", KEY_Q]],
	&"camera_rotate_right": [[&"key", KEY_E]],
	&"camera_pan_forward": [[&"key", KEY_W], [&"key", KEY_UP]],
	&"camera_pan_back": [[&"key", KEY_S], [&"key", KEY_DOWN]],
	&"camera_pan_left": [[&"key", KEY_A], [&"key", KEY_LEFT]],
	&"camera_pan_right": [[&"key", KEY_D], [&"key", KEY_RIGHT]],
	&"camera_zoom_in": [[&"mouse", MOUSE_BUTTON_WHEEL_UP]],
	&"camera_zoom_out": [[&"mouse", MOUSE_BUTTON_WHEEL_DOWN]],
	&"camera_recenter": [[&"key", KEY_F]],
	&"interact": [[&"mouse", MOUSE_BUTTON_LEFT]],
	&"secondary": [[&"mouse", MOUSE_BUTTON_RIGHT]],
	&"close_interaction": [[&"key", KEY_ESCAPE]],
	&"rotate_object": [[&"key", KEY_R]],
	&"open_manual": [[&"key", KEY_F1]],
	&"time_pause": [[&"key", KEY_SPACE]],
	&"time_speed_1": [[&"key", KEY_1]],
	&"time_speed_2": [[&"key", KEY_2]],
	&"time_speed_4": [[&"key", KEY_3]],
	&"quick_save": [[&"key", KEY_F5]],
}


static func ensure_defaults() -> void:
	for action: StringName in DEFAULTS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for spec: Array in DEFAULTS[action]:
			InputMap.action_add_event(action, _event(spec))


static func _event(spec: Array) -> InputEvent:
	if spec[0] == &"key":
		var key := InputEventKey.new()
		key.physical_keycode = spec[1]
		return key
	var button := InputEventMouseButton.new()
	button.button_index = spec[1]
	return button
