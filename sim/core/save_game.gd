class_name SaveGame
extends RefCounted
## Versioned save format (docs/ARCHITECTURE.md §7): one JSON document with a header, the
## simulation section and the presentation section (character, camera). Pure data: reading and
## writing files is done by the game layer (game/save/save_service.gd).

const FORMAT := "homelab-tycoon-save"
## 1: first format. 2 (2026-11-16): economy (ledger, passive income), device "used", XP already
## granted per mission requirement. 3 (2026-11-16): furniture layout and what each piece carries.
const VERSION := 3


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
	# Migrations are chained here, one step per version.
	if not (document.get("sim") is Dictionary):
		return {"ok": false, "message": "La partida está incompleta.", "document": {}}
	if version < 2:
		# v1 -> v2: the new parts start empty (SimWorld, SimDevice and MissionTracker fill the
		# defaults: no ledger lines, "used" for what is installed, requirement XP already given
		# when the mission was completed).
		document["version"] = 2
	if int(document["version"]) < 3:
		# v2 -> v3: no furniture key = the starting layout (BedroomScenario.restore attaches the
		# house devices to their furniture).
		document["version"] = 3
	return {"ok": true, "message": "", "document": document}
