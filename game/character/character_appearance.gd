class_name CharacterAppearance
extends RefCounted
## The look of the player character (docs/ART_STYLE.md §6.1): one option id per slot of
## AppearanceOptions. It is presentation, saved in the "session" part of the save
## (GameSession.capture_presentation). Missing or unknown ids fall back to the slot default, so
## saves from before the character creator keep the look the character had then.

const OPTIONS_PATH := "res://data/character/appearance_options.tres"
## The three tones of each colour in the model (tools/blender/build_prototype_models.py TONES).
const TONES: Array[float] = [1.0, 0.87, 1.09]

static var _options: AppearanceOptions = null
static var _materials: Dictionary = {} ## "material|colour" -> StandardMaterial3D (never modified)

var choices: Dictionary = {} ## slot id -> option id


static func options() -> AppearanceOptions:
	if _options == null:
		_options = load(OPTIONS_PATH) as AppearanceOptions
	return _options


static func default_look() -> CharacterAppearance:
	return from_dict({})


## A look from saved data; every slot gets a valid option.
static func from_dict(data: Dictionary) -> CharacterAppearance:
	var look := CharacterAppearance.new()
	for s: Dictionary in options().slots:
		var slot_id := String(s["id"])
		var wanted := str(data.get(slot_id, ""))
		look.choices[slot_id] = wanted if not options().option(slot_id, wanted).is_empty() else String(s["default"])
	return look


func to_dict() -> Dictionary:
	return choices.duplicate()


func choice(slot_id: String) -> String:
	return String(choices.get(slot_id, ""))


## The next (`step` 1) or previous (-1) option of a slot, wrapping round.
func cycle(slot_id: String, step: int) -> void:
	var list: Array = options().slot(slot_id).get("options", [])
	if list.is_empty():
		return
	var index := 0
	for i: int in list.size():
		if String((list[i] as Dictionary)["id"]) == choice(slot_id):
			index = i
	choices[slot_id] = String((list[posmod(index + step, list.size())] as Dictionary)["id"])


## Every slot at a random option (the creator's "Aleatorio").
func randomize_all(rng: RandomNumberGenerator) -> void:
	for s: Dictionary in options().slots:
		var list: Array = s["options"]
		choices[String(s["id"])] = String((list[rng.randi_range(0, list.size() - 1)] as Dictionary)["id"])


func option_label(slot_id: String) -> String:
	return TranslationServer.translate(String(options().option(slot_id, choice(slot_id)).get("label", "")))


## The colour chosen for a colour slot, or null for a style slot.
func option_color(slot_id: String) -> Variant:
	var o := options().option(slot_id, choice(slot_id))
	return o["color"] if o.has("color") else null


## Is a model piece part of this look?
func shows(piece_name: String) -> bool:
	for s: Dictionary in options().slots:
		if s.has("material"):
			continue
		var claimed := false
		for o: Dictionary in s["options"]:
			if _listed(piece_name, o["pieces"]):
				claimed = true
				break
		if claimed and not _listed(piece_name, options().option(String(s["id"]), choice(String(s["id"]))).get("pieces", PackedStringArray())):
			return false
	return true


## Shows the pieces of this look in `model` (an instance of character_player.glb) and recolours
## its c_* materials, keeping their three tones. Colours go in per-instance override materials:
## the imported materials are shared and stay as they are.
func apply(model: Node3D) -> void:
	var colors := _material_colors()
	for mesh: MeshInstance3D in ModelUtil.find_meshes_with_prefix(model, ""):
		mesh.visible = shows(String(mesh.name))
		for i: int in mesh.mesh.get_surface_count():
			var base := mesh.mesh.surface_get_material(i) as StandardMaterial3D
			mesh.set_surface_override_material(i, _recoloured(base, colors))


## Material name (without "M_" and tone) -> chosen colour.
func _material_colors() -> Dictionary:
	var colors := {}
	for s: Dictionary in options().slots:
		if s.has("material"):
			colors[String(s["material"])] = option_color(String(s["id"]))
	for material: String in options().derived:
		var rule: Array = options().derived[material]
		if colors.has(String(rule[0])):
			var c: Color = colors[String(rule[0])]
			var k := float(rule[1])
			colors[material] = Color(minf(c.r * k, 1.0), minf(c.g * k, 1.0), minf(c.b * k, 1.0), c.a)
	return colors


static func _recoloured(base: StandardMaterial3D, colors: Dictionary) -> Material:
	if base == null or not base.resource_name.begins_with("M_c_"):
		return null
	var name := base.resource_name.trim_prefix("M_")
	var tone := 0
	for t: int in [1, 2]:
		if name.ends_with("_t%d" % t):
			tone = t
			name = name.trim_suffix("_t%d" % t)
	if not colors.has(name):
		return null
	var c: Color = colors[name]
	var toned := Color(minf(c.r * TONES[tone], 1.0), minf(c.g * TONES[tone], 1.0), minf(c.b * TONES[tone], 1.0), c.a)
	var key := "%s|%s" % [base.resource_name, toned.to_html()]
	if not _materials.has(key):
		var m := base.duplicate() as StandardMaterial3D
		m.albedo_color = toned
		_materials[key] = m
	return _materials[key]


static func _listed(piece_name: String, prefixes: PackedStringArray) -> bool:
	for prefix: String in prefixes:
		if piece_name.begins_with(prefix):
			return true
	return false
