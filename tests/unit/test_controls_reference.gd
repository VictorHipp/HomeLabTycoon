extends TestCase
## Settings > Controls must show the controls that really work (game/input/controls_reference.gd).


func test_every_action_is_listed() -> void:
	InputBindings.ensure_defaults()
	var listed := ControlsReference.listed_actions()
	for action: StringName in InputBindings.DEFAULTS:
		assert_true(listed.has(action), "%s appears in Settings > Controls" % action)
	for action: StringName in listed:
		assert_true(InputMap.has_action(action), "%s exists in the InputMap" % action)


func test_keys_come_from_the_input_map() -> void:
	InputBindings.ensure_defaults()
	assert_eq(ControlsReference.keys_for([&"camera_rotate_left", &"camera_rotate_right"]), "Q / E", "rotate keys")
	assert_eq(ControlsReference.keys_for([&"close_interaction"]), "Esc", "escape")
	assert_eq(ControlsReference.keys_for([&"open_manual"]), "F1", "manual key")
	assert_eq(ControlsReference.keys_for([&"interact"]), "Clic izquierdo", "left click")
	assert_contains(ControlsReference.keys_for([&"camera_pan_forward", &"camera_pan_left", &"camera_pan_back", &"camera_pan_right"]), "W / A / S / D", "pan keys")
	# A remapped key shows up on the page.
	var events := InputMap.action_get_events(&"rotate_object")
	InputMap.action_erase_events(&"rotate_object")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_T
	InputMap.action_add_event(&"rotate_object", key)
	assert_eq(ControlsReference.keys_for([&"rotate_object"]), "T", "remapped key shown")
	InputMap.action_erase_events(&"rotate_object")
	for e: InputEvent in events:
		InputMap.action_add_event(&"rotate_object", e)


func test_every_group_has_rows() -> void:
	InputBindings.ensure_defaults()
	for group: Array in ControlsReference.groups():
		assert_true((group[1] as Array).size() > 0, "%s has controls" % group[0])
		for row: Array in group[1]:
			assert_true(String(row[1]) != "" and not String(row[1]).contains("?"), "%s: %s has a key" % [group[0], row[0]])
