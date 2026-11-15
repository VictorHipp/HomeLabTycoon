extends TestCase
## ADR 0003 / 0009: the simulation never depends on the presentation.

const FORBIDDEN: PackedStringArray = ["extends Node", "get_node(", "get_tree(", "PackedScene", "res://game/"]


func test_sim_has_no_scene_dependencies() -> void:
	var files: Array[String] = []
	_collect("res://sim", files)
	assert_true(files.size() > 5, "sim scripts found")
	for path: String in files:
		var text := FileAccess.get_file_as_string(path)
		for token: String in FORBIDDEN:
			if text.contains(token):
				_fail("%s contains «%s»" % [path, token])


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
	for file: String in dir.get_files():
		if file.get_extension() == "gd":
			out.append(dir_path.path_join(file))
