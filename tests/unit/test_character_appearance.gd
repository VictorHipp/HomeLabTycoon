extends TestCase
## The player character's look (game/character/character_appearance.gd,
## data/character/appearance_options.tres): every combination of body, hair, beard, glasses and
## top shows exactly one torso, one pair of hips, one mouth and one hair style; every listed piece
## exists in the model; colours go in per-instance materials; bad or missing data falls back to
## the defaults (old saves keep the original look).

const STYLE_SLOTS: Array[String] = ["body", "hair", "beard", "glasses", "top"]


func _model() -> Node3D:
	return ModelUtil.instance_model(PlayerCharacter.MODEL)


func _visible_names(model: Node3D) -> Array[String]:
	var names: Array[String] = []
	for mesh: MeshInstance3D in ModelUtil.find_meshes_with_prefix(model, ""):
		if mesh.visible:
			names.append(String(mesh.name))
	return names


func test_every_listed_piece_exists() -> void:
	var model := _model()
	var names: Array[String] = []
	for mesh: MeshInstance3D in ModelUtil.find_meshes_with_prefix(model, ""):
		names.append(String(mesh.name))
	for s: Dictionary in CharacterAppearance.options().slots:
		for o: Dictionary in s["options"]:
			for prefix: String in o.get("pieces", PackedStringArray()):
				assert_true(names.any(func(n: String) -> bool: return n.begins_with(prefix)), "%s/%s: piece %s exists" % [s["id"], o["id"], prefix])
	model.free()


func test_every_combination_is_complete_and_single() -> void:
	var model := _model()
	var combos: Array[Dictionary] = [{}]
	for slot_id: String in STYLE_SLOTS:
		var next: Array[Dictionary] = []
		for partial: Dictionary in combos:
			for o: Dictionary in CharacterAppearance.options().slot(slot_id)["options"]:
				var d := partial.duplicate()
				d[slot_id] = String(o["id"])
				next.append(d)
		combos = next
	assert_eq(combos.size(), 2 * 4 * 4 * 2 * 3, "all style combinations")
	for combo: Dictionary in combos:
		var look := CharacterAppearance.from_dict(combo)
		look.apply(model)
		var shown := _visible_names(model)
		var label := str(combo)
		var torso := "torso_%s_%s_" % [combo["body"], combo["top"]]
		var torsos := shown.filter(func(n: String) -> bool: return n.begins_with("torso_"))
		assert_true(not torsos.is_empty() and torsos.all(func(n: String) -> bool: return n.begins_with(torso)), "%s: only the %s torso (%s)" % [label, torso, torsos])
		var hips := shown.filter(func(n: String) -> bool: return n.begins_with("hips_"))
		assert_true(hips.size() == 3 and hips.all(func(n: String) -> bool: return n.begins_with("hips_%s_" % combo["body"])), "%s: one pair of hips" % label)
		assert_eq(shown.filter(func(n: String) -> bool: return n.begins_with("mouth_")).size(), 1, "%s: one mouth" % label)
		var hair := shown.filter(func(n: String) -> bool: return n.begins_with("hair_"))
		assert_true(not hair.is_empty() and hair.all(func(n: String) -> bool: return n.begins_with("hair_%s_" % combo["hair"])), "%s: one hair style" % label)
		var long_sleeves := shown.any(func(n: String) -> bool: return n.begins_with("sleeve_long_"))
		var bare_arms := shown.any(func(n: String) -> bool: return n.begins_with("arm_skin_") or n.begins_with("sleeve_short_"))
		assert_true(long_sleeves != bare_arms and long_sleeves == (combo["top"] != "tshirt"), "%s: one kind of sleeves" % label)
		assert_eq(shown.has("glasses_bridge"), combo["glasses"] == "yes", "%s: glasses" % label)
		assert_eq(shown.has("beard_full_jaw"), combo["beard"] == "full", "%s: beard" % label)
		for always: String in ["head", "neck", "hand_1", "thigh_-1", "shoe_1", "nose"]:
			assert_true(shown.has(always), "%s: %s always shown" % [label, always])
	model.free()


func test_colours_are_per_instance() -> void:
	var a := _model()
	var b := _model()
	var look_a := CharacterAppearance.from_dict({"top_color": "terracota", "hair_color": "rubio"})
	var look_b := CharacterAppearance.default_look()
	look_a.apply(a)
	look_b.apply(b)
	var jacket_a := a.find_child("torso_m_overshirt_jacket", true, false) as MeshInstance3D
	var jacket_b := b.find_child("torso_m_overshirt_jacket", true, false) as MeshInstance3D
	var mat_a := jacket_a.get_surface_override_material(0) as StandardMaterial3D
	var mat_b := jacket_b.get_surface_override_material(0) as StandardMaterial3D
	assert_true(mat_a.albedo_color.is_equal_approx(look_a.option_color("top_color")), "A: terracotta top")
	assert_true(mat_b.albedo_color.is_equal_approx(look_b.option_color("top_color")), "B: sage top")
	assert_false(mat_a.albedo_color.is_equal_approx(mat_b.albedo_color), "two characters do not share a colour")
	var imported := jacket_a.mesh.surface_get_material(0) as StandardMaterial3D
	assert_true(imported != mat_a and imported != mat_b, "the imported material is never changed")
	# The darker tones keep their ratio and the trim follows the top.
	var collar := a.find_child("torso_m_overshirt_collar", true, false) as MeshInstance3D
	var trim := collar.get_surface_override_material(0) as StandardMaterial3D
	assert_true(trim.albedo_color.r < mat_a.albedo_color.r, "the collar is a darker shade of the top")
	# Fixed materials (glasses, eyes, belt) are left alone.
	var bridge := a.find_child("glasses_bridge", true, false) as MeshInstance3D
	assert_eq(bridge.get_surface_override_material(0), null, "glasses keep their material")
	a.free()
	b.free()


func test_bad_or_missing_data_falls_back_to_the_default() -> void:
	var look := CharacterAppearance.from_dict({"body": "x", "hair": 7, "top_color": "rosa_chicle"})
	var default := CharacterAppearance.default_look()
	assert_eq(look.to_dict(), default.to_dict(), "unknown ids -> defaults")
	assert_eq(default.choice("body"), "m", "the original character is the default")
	assert_eq(default.choice("beard"), "full", "with his short beard")
	assert_eq(default.choice("glasses"), "yes", "and glasses")


func test_cycle_wraps_round() -> void:
	var look := CharacterAppearance.default_look()
	look.cycle("glasses", 1)
	assert_eq(look.choice("glasses"), "no", "next")
	look.cycle("glasses", 1)
	assert_eq(look.choice("glasses"), "yes", "wraps")
	look.cycle("beard", -1)
	assert_eq(look.choice("beard"), "none", "previous")
