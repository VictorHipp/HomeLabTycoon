extends TestCase
## The save files on disk (game/save/save_service.gd, ADR 0015): a backup that takes over when
## the save is damaged, a slot that is never left empty, and an autosave that never replaces the
## player's save. Uses its own folder under user://, never the player's files.

const SLOT := "user://test_saves/partida.json"

var _old_slot: String


func before_each() -> void:
	_old_slot = SaveService.slot_path
	SaveService.slot_path = SLOT
	for path: String in _files():
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _files() -> Array[String]:
	var result: Array[String] = []
	for base: String in [SLOT, SaveService.autosave_path()]:
		for suffix: String in ["", ".bak", ".tmp"]:
			result.append(base + suffix)
	return result


func _done() -> void:
	for path: String in _files():
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	SaveService.slot_path = _old_slot


func _document(credits: int) -> Dictionary:
	var world := BedroomScenario.create()
	world.credits = credits
	return SaveGame.build(world, {})


func _damage(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{ esto no es una partida")
	file.close()


func _credits(result: Dictionary) -> int:
	return int(((result["document"] as Dictionary)["sim"] as Dictionary)["credits"])


func test_write_then_read() -> void:
	assert_false(SaveService.has_save(), "nothing yet")
	assert_false(SaveService.read()["ok"], "reading nothing fails with a reason")
	assert_true(SaveService.write(_document(111))["ok"], "write")
	var r := SaveService.read()
	assert_true(r["ok"], "read")
	assert_eq(_credits(r), 111, "the same game")
	assert_false(r["from_backup"], "from the save itself")
	assert_false(FileAccess.file_exists(SLOT + ".tmp"), "no temporary file left")
	_done()


func test_damaged_save_falls_back_to_the_backup() -> void:
	SaveService.write(_document(111))
	SaveService.write(_document(222))
	assert_true(FileAccess.file_exists(SLOT + ".bak"), "the previous save is kept")
	_damage(SLOT)
	var r := SaveService.read()
	assert_true(r["ok"], "still readable")
	assert_true(r["from_backup"], "from the backup")
	assert_eq(_credits(r), 111, "the previous game")
	assert_contains(r["message"], "copia de seguridad", "and it says so")
	# Saving over a damaged file keeps the good backup instead of replacing it with the damage.
	SaveService.write(_document(333))
	_damage(SLOT)
	assert_eq(_credits(SaveService.read()), 111, "the good backup survived")
	# A missing save with a backup is still a game that can be loaded.
	DirAccess.remove_absolute(SLOT)
	assert_true(SaveService.has_save(), "backup alone counts")
	assert_eq(_credits(SaveService.read()), 111, "backup alone loads")
	_done()


func test_damaged_save_without_backup_says_why() -> void:
	SaveService.write(_document(111))
	_damage(SLOT)
	var r := SaveService.read()
	assert_false(r["ok"], "not readable")
	assert_true(String(r["message"]) != "", "with a reason")
	_done()


func test_autosave_never_replaces_the_players_save() -> void:
	SaveService.write(_document(111))
	assert_true(SaveService.write(_document(999), SaveService.autosave_path())["ok"], "autosave")
	assert_eq(_credits(SaveService.read()), 111, "the player's save is untouched")
	assert_eq(_credits(SaveService.read(SaveService.autosave_path())), 999, "the autosave is its own file")
	assert_true(SaveService.autosave_path() != SaveService.slot_path, "two files")
	_done()


func test_continue_takes_the_most_recent() -> void:
	assert_false(SaveService.read_latest()["ok"], "nothing to continue")
	SaveService.write(_document(111), SaveService.autosave_path())
	var only_auto := SaveService.read_latest()
	assert_true(only_auto["ok"] and only_auto["auto"], "an autosave alone can be continued")
	OS.delay_msec(20)
	SaveService.write(_document(222))
	var latest := SaveService.read_latest()
	assert_false(latest["auto"], "the save written last wins")
	assert_eq(_credits(latest), 222, "its game")
	OS.delay_msec(20)
	SaveService.write(_document(333), SaveService.autosave_path())
	latest = SaveService.read_latest()
	assert_true(latest["auto"], "then the newer autosave wins")
	assert_eq(_credits(latest), 333, "its game")
	# A damaged autosave does not hide the player's save.
	_damage(SaveService.autosave_path())
	DirAccess.remove_absolute(SaveService.autosave_path() + ".bak")
	assert_eq(_credits(SaveService.read_latest()), 222, "falls back to the player's save")
	_done()


func test_describe() -> void:
	var world := BedroomScenario.create()
	world.credits = 840
	var text := SaveService.describe(SaveGame.build(world, {}))
	assert_contains(text, "840 créditos", "credits")
	assert_contains(text, "día 1", "day")
	_done()
