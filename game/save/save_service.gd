class_name SaveService
extends RefCounted
## Writes and reads the save files (docs/ARCHITECTURE.md §7, ADR 0015): JSON in user://saves/,
## written to a temporary file and renamed (atomic), keeping the previous file as .bak. If the
## file cannot be read, its .bak is used instead and the message says so.
## Two files: the player's save (`slot_path`, written only by "Guardar partida") and the
## autosave next to it (`autosave_path()`, written by the game on its own). Neither overwrites
## the other.

const DEFAULT_SLOT := "user://saves/partida.json"

## The automated walkthrough uses its own file so it never overwrites the player's game.
static var slot_path: String = DEFAULT_SLOT


## The autosave that goes with the current slot ("partida.json" -> "partida_auto.json").
static func autosave_path() -> String:
	return slot_path.get_basename() + "_auto." + slot_path.get_extension()


static func has_save(path: String = "") -> bool:
	var file := _path(path)
	return FileAccess.file_exists(file) or FileAccess.file_exists(file + ".bak")


## Returns {"ok": bool, "message": String}.
static func write(document: Dictionary, path: String = "") -> Dictionary:
	var file_path := _path(path)
	DirAccess.make_dir_recursive_absolute(file_path.get_base_dir())
	var tmp := file_path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "message": TranslationServer.translate("No se pudo escribir la partida (%s).") % error_string(FileAccess.get_open_error())}
	# When it was written (real time): "Continuar" picks the most recent of the two files.
	var stamped := document.duplicate()
	stamped["saved_at"] = Time.get_unix_time_from_system()
	file.store_string(SaveGame.to_text(stamped))
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(tmp)
		return {"ok": false, "message": TranslationServer.translate("No se pudo escribir la partida (%s).") % error_string(write_error)}
	var backup := file_path + ".bak"
	var had_previous := FileAccess.file_exists(file_path)
	if had_previous:
		# Only a file that can be read becomes the backup: a damaged one must not replace a
		# good backup.
		if SaveGame.parse(FileAccess.get_file_as_string(file_path))["ok"]:
			if FileAccess.file_exists(backup):
				DirAccess.remove_absolute(backup)
			DirAccess.rename_absolute(file_path, backup)
		else:
			DirAccess.remove_absolute(file_path)
			had_previous = false
	var err := DirAccess.rename_absolute(tmp, file_path)
	if err != OK:
		if had_previous: # put the previous save back: the slot is never left empty
			DirAccess.rename_absolute(backup, file_path)
		DirAccess.remove_absolute(tmp)
		return {"ok": false, "message": TranslationServer.translate("No se pudo guardar la partida (%s).") % error_string(err)}
	return {"ok": true, "message": TranslationServer.translate("Partida guardada.")}


## Returns {"ok": bool, "message": String, "document": Dictionary, "from_backup": bool}.
static func read(path: String = "") -> Dictionary:
	var file_path := _path(path)
	if not has_save(file_path):
		return {"ok": false, "message": TranslationServer.translate("Todavía no hay ninguna partida guardada."), "document": {}, "from_backup": false}
	var result := {"ok": false, "message": "", "document": {}}
	if FileAccess.file_exists(file_path):
		result = SaveGame.parse(FileAccess.get_file_as_string(file_path))
	result["from_backup"] = false
	if result["ok"] or not FileAccess.file_exists(file_path + ".bak"):
		return result
	var backup := SaveGame.parse(FileAccess.get_file_as_string(file_path + ".bak"))
	if not backup["ok"]:
		return result
	backup["from_backup"] = true
	backup["message"] = TranslationServer.translate("El archivo de la partida estaba dañado: se ha recuperado la copia de seguridad anterior.")
	return backup


## The most recent readable game, the player's save or the autosave (what "Continuar" loads).
## Returns {"ok", "message", "document", "from_backup", "auto": bool}.
static func read_latest() -> Dictionary:
	var manual := read()
	manual["auto"] = false
	var auto := read(autosave_path())
	auto["auto"] = true
	if not auto["ok"]:
		return manual
	if not manual["ok"]:
		return auto
	return auto if _saved_at(auto, autosave_path()) > _saved_at(manual, slot_path) else manual


## "día 2, 09:15 · 840 créditos" for a save document (title screen and menu).
static func describe(document: Dictionary) -> String:
	var sim: Dictionary = document.get("sim", {})
	var minutes := int(float(sim.get("time_minutes", 0.0)))
	return TranslationServer.translate("día %d, %02d:%02d · %d créditos") % [
		minutes / 1440 + 1, (minutes % 1440) / 60, minutes % 60, int(sim.get("credits", 0))]


static func _path(path: String) -> String:
	return slot_path if path == "" else path


static func _saved_at(result: Dictionary, path: String) -> float:
	var document: Dictionary = result["document"]
	if document.has("saved_at"):
		return float(document["saved_at"])
	return float(FileAccess.get_modified_time(path)) if FileAccess.file_exists(path) else 0.0
