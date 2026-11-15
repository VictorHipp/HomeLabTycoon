extends SceneTree
## Headless smoke test for the project skeleton.
##
##   godot_console --headless --path . --script res://tests/smoke_test.gd
##
## Exit code 0 = everything OK, 1 = at least one check failed.
## Every failure is printed with the prefix "SMOKE FAIL" so it is easy to grep.

## Directories that are not part of our own code and are not checked here.
const SKIPPED_DIRS: PackedStringArray = ["addons"]
## File types that must load without errors. `--import` and running the main
## scene do NOT parse scripts nobody references, so we load everything.
const CHECKED_EXTENSIONS: PackedStringArray = ["gd", "tscn", "tres", "res"]

var _failures: Array[String] = []


func _initialize() -> void:
	_check_all_files_load()
	_check_catalog()
	_check_main_scene()

	if _failures.is_empty():
		print("SMOKE OK")
		quit(0)
	else:
		for message: String in _failures:
			printerr("SMOKE FAIL: " + message)
		quit(1)


func _check_all_files_load() -> void:
	var paths: Array[String] = []
	_collect_files("res://", paths)
	for path: String in paths:
		# A script with a parse error makes load() return null and prints
		# "SCRIPT ERROR: Parse Error ..." to stderr, which the harness also reads.
		if OS.get_environment("SMOKE_VERBOSE") == "1":
			print("loading ", path)
		if ResourceLoader.load(path) == null:
			_failures.append("failed to load " + path)
	print("Loaded %d project files" % paths.size())


func _collect_files(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		_failures.append("cannot open directory " + dir_path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not SKIPPED_DIRS.has(entry):
				_collect_files(full, out)
		elif CHECKED_EXTENSIONS.has(entry.get_extension()):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _check_catalog() -> void:
	# Detailed catalog rules live in tests/unit/test_catalog.gd; this only proves the data loads.
	var rack := load("res://data/catalog/rack_12u_open.tres") as HardwareDefinition
	if rack == null:
		_failures.append("rack_12u_open.tres did not load as HardwareDefinition")
		return
	_expect(rack.id == &"rack_12u_open", "rack id is rack_12u_open")
	_expect(rack.category == &"rack", "rack category is rack")
	var spec := rack.get_spec(RackSpec) as RackSpec
	_expect(spec != null and spec.capacity_u == 12, "rack has a 12U RackSpec")


func _check_main_scene() -> void:
	var packed := load("res://game/main/main.tscn") as PackedScene
	if packed == null:
		_failures.append("main.tscn did not load")
		return
	var main := packed.instantiate()
	root.add_child(main)
	var sun := main.get_node_or_null("Sun") as DirectionalLight3D
	_expect(sun != null, "Sun node exists")
	if sun != null:
		_expect(is_equal_approx(sun.rotation_degrees.x, -50.0), "Sun rotation_degrees was applied from the scene")
	_expect(main.get_node_or_null("Camera3D") != null, "Camera3D node exists")


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
