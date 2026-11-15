class_name SaveGame
extends RefCounted
## Versioned save format (docs/ARCHITECTURE.md §7): one JSON document with a header, the
## simulation section and the presentation section (character, camera). Pure data: reading and
## writing files is done by the game layer (game/save/save_service.gd).

const FORMAT := "homelab-tycoon-save"
const VERSION := 1


## Builds the document. `session` is owned by the presentation (character, camera...).
static func build(world: SimWorld, session: Dictionary) -> Dictionary:
	return {"format": FORMAT, "version": VERSION, "sim": world.save_state(), "session": session}


static func to_text(document: Dictionary) -> String:
	return JSON.stringify(document, "\t", true, true)


## Parses and migrates a document. Returns {"ok": bool, "message": String, "document": Dictionary}.
static func parse(text: String) -> Dictionary:
	var json := JSON.new() # the instance API reports errors without printing them
	var data: Variant = json.data if json.parse(text) == OK else null
	if not (data is Dictionary) or data.get("format") != FORMAT:
		return {"ok": false, "message": "El archivo no es una partida de HomeLab Tycoon.", "document": {}}
	var version := int(data.get("version", 0))
	if version > VERSION:
		return {"ok": false, "message": "La partida es de una versión más nueva del juego (%d)." % version, "document": {}}
	var document: Dictionary = data
	# Migrations are chained here, one function per version step (v1 is the first format).
	if not (document.get("sim") is Dictionary):
		return {"ok": false, "message": "La partida está incompleta.", "document": {}}
	return {"ok": true, "message": "", "document": document}
