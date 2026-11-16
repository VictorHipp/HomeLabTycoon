class_name CharacterCreator
extends Control
## Character creator of a new game (docs/ART_STYLE.md §6.1): one row per slot of
## AppearanceOptions (body, skin, hair and its colour, beard, glasses, top and its colour,
## trousers, trainers) with ◀ ▶ buttons, and a preview of the character under the room's light
## turning slowly (drag to turn it).

signal back_requested
signal start_requested(look: Dictionary)

const TURN_SPEED := 0.35 ## rad/s when not dragged

var look: CharacterAppearance = CharacterAppearance.default_look()
var preview_model: Node3D
var _value_labels: Dictionary = {} ## slot id -> Label
var _swatches: Dictionary = {} ## slot id -> ColorRect
var _pivot: Node3D
var _dragging: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT) # added to the tree already: offsets too
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		row.set("offset_" + side, 28 if side in ["left", "top"] else -28)
	row.add_theme_constant_override("separation", 20)
	add_child(row)
	row.add_child(_build_panel())
	row.add_child(_build_preview())
	_refresh()


func _build_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(430, 0)
	panel.add_theme_stylebox_override("panel", UiStyle.panel(Color("#1E2430"), 12, 18))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	box.add_child(UiStyle.label(TranslationServer.translate("Tu personaje"), 26, UiStyle.HIGHLIGHT))
	var note := UiStyle.label(TranslationServer.translate("Elige cómo es. Es solo el aspecto: no cambia nada del juego."), 14, UiStyle.MIST)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	scroll.add_child(rows)
	for s: Dictionary in CharacterAppearance.options().slots:
		rows.add_child(_slot_row(s))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	var back := UiStyle.button(TranslationServer.translate("Volver"), func() -> void: back_requested.emit())
	back.name = "Back"
	buttons.add_child(back)
	var random := UiStyle.button(TranslationServer.translate("Al azar"), _randomize)
	random.name = "Random"
	buttons.add_child(random)
	var start := UiStyle.button(TranslationServer.translate("Empezar partida"), func() -> void: start_requested.emit(look.to_dict()))
	start.name = "Start"
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(start)
	return panel


func _slot_row(s: Dictionary) -> Control:
	var slot_id := String(s["id"])
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	var name_label := UiStyle.label(TranslationServer.translate(String(s["label"])), 15, UiStyle.MIST)
	name_label.custom_minimum_size = Vector2(150, 0)
	line.add_child(name_label)
	var prev := UiStyle.button("◀", _step.bind(slot_id, -1))
	prev.name = "Prev_" + slot_id
	line.add_child(prev)
	if s.has("material"):
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(18, 18)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(swatch)
		_swatches[slot_id] = swatch
	var value := UiStyle.label("", 15, UiStyle.BONE)
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_child(value)
	_value_labels[slot_id] = value
	var next := UiStyle.button("▶", _step.bind(slot_id, 1))
	next.name = "Next_" + slot_id
	line.add_child(next)
	return line


func _build_preview() -> Control:
	var container := SubViewportContainer.new()
	container.name = "Preview"
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.gui_input.connect(_on_preview_input)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	GameSettings.apply_viewport(viewport)
	container.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	RoomLighting.add_to(world, false)
	var floor_disc := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.7
	disc.bottom_radius = 0.7
	disc.height = 0.02
	disc.radial_segments = 24
	floor_disc.mesh = disc
	floor_disc.position = Vector3(0.0, -0.01, 0.0)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("#C98F5A")
	floor_disc.material_override = wood
	world.add_child(floor_disc)
	_pivot = Node3D.new()
	world.add_child(_pivot)
	preview_model = ModelUtil.instance_model(PlayerCharacter.MODEL)
	_pivot.add_child(preview_model)
	_pivot.rotation.y = deg_to_rad(200.0) # faces the camera, lit by the window light
	var camera := Camera3D.new()
	camera.fov = 30.0
	world.add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 1.3, -4.2), Vector3(0.0, 0.9, 0.0))
	camera.current = true
	return container


func _process(delta: float) -> void:
	if _pivot != null and not _dragging:
		_pivot.rotation.y += TURN_SPEED * delta


## Esc goes back to the title menu, as the "Volver" button.
func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"close_interaction"):
		get_viewport().set_input_as_handled()
		back_requested.emit()


func _on_preview_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = button.pressed
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		_pivot.rotation.y += motion.relative.x * 0.01


func _step(slot_id: String, step: int) -> void:
	look.cycle(slot_id, step)
	_refresh()


func _randomize() -> void:
	_rng.randomize()
	look.randomize_all(_rng)
	_refresh()


func _refresh() -> void:
	for slot_id: String in _value_labels:
		(_value_labels[slot_id] as Label).text = look.option_label(slot_id)
		if _swatches.has(slot_id):
			(_swatches[slot_id] as ColorRect).color = look.option_color(slot_id)
	if preview_model != null:
		look.apply(preview_model)
