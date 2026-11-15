extends SceneTree
## Minimal headless test runner (decision 4, docs/TEST_PLAN.md §3).
##
##   godot_console --headless --path . --script res://tests/run_tests.gd
##
## Discovers res://tests/unit/**/test_*.gd and res://tests/integration/**/test_*.gd,
## runs every test_* method and exits with 0 (all passed) or 1.

const ROOTS: PackedStringArray = ["res://tests/unit", "res://tests/integration"]


func _initialize() -> void:
	var files: Array[String] = []
	for dir_path: String in ROOTS:
		_collect(dir_path, files)
	files.sort()
	var total := 0
	var failed: Array[String] = []
	for path: String in files:
		var script := load(path) as GDScript
		if script == null:
			failed.append("%s: could not load" % path)
			continue
		var methods: Array[String] = []
		for info: Dictionary in script.get_script_method_list():
			var name: String = info["name"]
			if name.begins_with("test_") and not methods.has(name):
				methods.append(name)
		methods.sort()
		for method: String in methods:
			var case := script.new() as TestCase
			case.current_test = "%s::%s" % [path.get_file(), method]
			case.before_each()
			case.call(method)
			total += 1
			failed.append_array(case.failures)
	if failed.is_empty():
		print("TESTS OK (%d tests in %d files)" % [total, files.size()])
		quit(0)
	else:
		for line: String in failed:
			printerr("TEST FAIL: " + line)
		printerr("TESTS FAILED: %d failure(s) in %d tests" % [failed.size(), total])
		quit(1)


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
	for file: String in dir.get_files():
		if file.begins_with("test_") and file.get_extension() == "gd":
			out.append(dir_path.path_join(file))
