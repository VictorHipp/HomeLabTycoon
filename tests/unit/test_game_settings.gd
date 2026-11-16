extends TestCase
## The player's settings (game/settings/game_settings.gd, ADR 0015): defaults, values kept in
## their own file, bad values refused. Uses its own file, never the player's.

const FILE := "user://test_settings.cfg"

var _old_path: String
var _old_apply: bool


func before_each() -> void:
	_old_path = GameSettings.path
	_old_apply = GameSettings.apply_to_window
	GameSettings.path = FILE
	GameSettings.apply_to_window = false
	if FileAccess.file_exists(FILE):
		DirAccess.remove_absolute(FILE)
	GameSettings.read_file()


func _done() -> void:
	if FileAccess.file_exists(FILE):
		DirAccess.remove_absolute(FILE)
	GameSettings.path = _old_path
	GameSettings.apply_to_window = _old_apply
	GameSettings.read_file()


func test_defaults() -> void:
	assert_eq(GameSettings.path, FILE, "the tests use their own file, not the player's")
	for spec: Dictionary in GameSettings.SPECS:
		assert_eq(GameSettings.value(spec["id"]), spec["default"], "%s starts at its default" % spec["id"])
		assert_true(GameSettings.value_label(spec["id"]) != "", "%s has a text" % spec["id"])
	assert_false(FileAccess.file_exists(FILE), "reading does not write a file")
	_done()


func test_values_are_kept_in_the_file() -> void:
	GameSettings.set_value("invert_y", true)
	GameSettings.set_value("autosave_minutes", 10)
	GameSettings.read_file()
	assert_eq(GameSettings.value("invert_y"), true, "bool kept")
	assert_eq(GameSettings.value("autosave_minutes"), 10, "choice kept")
	assert_eq(GameSettings.value("vsync"), true, "the rest keep their defaults")
	_done()


func test_bad_values_are_refused() -> void:
	assert_eq(GameSettings.set_value("msaa", 17), 2, "unknown choice -> default")
	assert_eq(GameSettings.set_value("fullscreen", "sí"), false, "wrong type -> default")
	assert_eq(GameSettings.set_value("no_such_setting", 1), null, "unknown setting")
	# A file edited by hand.
	var config := ConfigFile.new()
	config.set_value(GameSettings.SECTION, "camera_sensitivity", 99.0)
	config.set_value(GameSettings.SECTION, "invert_x", "quizá")
	config.save(FILE)
	GameSettings.read_file()
	assert_eq(GameSettings.value("camera_sensitivity"), 1.0, "out of range -> default")
	assert_eq(GameSettings.value("invert_x"), false, "wrong type -> default")
	_done()


func test_cycle_wraps_round() -> void:
	assert_eq(GameSettings.cycle("msaa", 1), 3, "next")
	assert_eq(GameSettings.cycle("msaa", 1), 0, "wraps")
	assert_eq(GameSettings.cycle("msaa", -1), 3, "previous")
	assert_eq(GameSettings.cycle("show_fps", 1), true, "a bool flips")
	assert_eq(GameSettings.cycle("show_fps", -1), false, "either way")
	_done()


func test_camera_settings_reach_the_rig() -> void:
	var rig := OverviewCameraRig.new()
	GameSettings.set_value("camera_sensitivity", 2.0)
	GameSettings.set_value("invert_x", true)
	GameSettings.apply_camera(rig)
	assert_almost(rig.drag_sensitivity_deg, OverviewCameraRig.DEFAULT_DRAG_SENSITIVITY_DEG * 2.0, 0.0001, "sensitivity")
	assert_true(rig.invert_drag_x, "invert x")
	assert_false(rig.invert_drag_y, "invert y untouched")
	rig.free()
	_done()
