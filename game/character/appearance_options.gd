class_name AppearanceOptions
extends Resource
## What the player can choose for the character (docs/ART_STYLE.md §6.1), in the order the
## character creator shows it. Data: data/character/appearance_options.tres.
##
## Each slot is {"id", "label", "default", "options": [...]} and either
##   - a style: every option is {"id", "label", "pieces": PackedStringArray} with the name
##     prefixes of the model pieces it shows. A piece that any option of the slot lists is
##     hidden unless the chosen option lists it too (so pieces shared by two options, and
##     pieces that depend on two slots, need no special rule); or
##   - a colour ("material": the c_* material of the model it recolours): every option is
##     {"id", "label", "color": Color}.

@export var slots: Array[Dictionary] = []
## Materials that follow another one: {"c_top_trim": ["c_top", 0.8]} = the top colour × 0.8.
@export var derived: Dictionary = {}


func slot(slot_id: String) -> Dictionary:
	for s: Dictionary in slots:
		if String(s["id"]) == slot_id:
			return s
	return {}


func option(slot_id: String, option_id: String) -> Dictionary:
	for o: Dictionary in slot(slot_id).get("options", []):
		if String(o["id"]) == option_id:
			return o
	return {}
