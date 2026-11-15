class_name SaveService
extends RefCounted
## Writes and reads the save file (docs/ARCHITECTURE.md §7): JSON in user://saves/, written to a
## temporary file and renamed (atomic), keeping the previous save as .bak. One slot for now.

const DEFAULT_SLOT := "user://saves/partida.json"

## The automated walkthrough uses its own file so it never overwrites the player's game.
static var slot_path: String = DEFAULT_SLOT


static func has_save() -> bool:
	return FileAccess.file_exists(slot_path)


## Returns {"ok": bool, "message": String}.
static func write(document: Dictionary) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(slot_path.get_base_dir())
	var tmp := slot_path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "message": "No se pudo escribir la partida (%s)." % error_string(FileAccess.get_open_error())}
	file.store_string(SaveGame.to_text(document))
	file.close()
	if FileAccess.file_exists(slot_path):
		var backup := slot_path + ".bak"
		if FileAccess.file_exists(backup):
			DirAccess.remove_absolute(backup)
		DirAccess.rename_absolute(slot_path, backup)
	var err := DirAccess.rename_absolute(tmp, slot_path)
	if err != OK:
		return {"ok": false, "message": "No se pudo guardar la partida (%s)." % error_string(err)}
	return {"ok": true, "message": "Partida guardada."}


## Returns {"ok": bool, "message": String, "document": Dictionary}.
static func read() -> Dictionary:
	if not has_save():
		return {"ok": false, "message": "Todavía no hay ninguna partida guardada.", "document": {}}
	var text := FileAccess.get_file_as_string(slot_path)
	return SaveGame.parse(text)
